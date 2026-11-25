"""Idempotent GCS-to-BigQuery Bronze batch loader with atomic watermark claiming."""

from __future__ import annotations

import argparse
from dataclasses import dataclass, replace
from datetime import datetime, timezone
import json
import logging
import os
from pathlib import PurePosixPath
import re
import sys
import time
from typing import Any
import uuid

from google.api_core.exceptions import GoogleAPICallError
from google.cloud import bigquery
from google.cloud import storage

LOGGER = logging.getLogger("gcs_to_bronze")
VALID_PROJECT_ID_RE = re.compile(r"^[a-z][a-z0-9-]{0,29}$")
VALID_BQ_IDENTIFIER_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]{0,1023}$")
MAX_MERGE_RETRIES = 3
WATERMARK_URI_BATCH_SIZE = 10000
TRANSIENT_HTTP_CODES = frozenset({429, 500, 502, 503, 504})
TRANSIENT_EXCEPTION_NAMES = frozenset({
    "TooManyRequests",
    "InternalServerError",
    "BadGateway",
    "ServiceUnavailable",
    "DeadlineExceeded",
    "RetryError",
})

SUPPORTED_SOURCE_FORMATS = {
    "CSV": bigquery.SourceFormat.CSV,
    "NEWLINE_DELIMITED_JSON": bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
    "PARQUET": bigquery.SourceFormat.PARQUET,
}

WATERMARK_SCHEMA = [
    bigquery.SchemaField("gcs_uri", "STRING", mode="REQUIRED"),
    bigquery.SchemaField("generation", "INT64", mode="REQUIRED"),
    bigquery.SchemaField("status", "STRING", mode="REQUIRED"),
    bigquery.SchemaField("claim_token", "STRING", mode="REQUIRED"),
    bigquery.SchemaField("row_count", "INT64", mode="REQUIRED"),
    bigquery.SchemaField("job_id", "STRING", mode="REQUIRED"),
    bigquery.SchemaField("claimed_at", "TIMESTAMP", mode="REQUIRED"),
    bigquery.SchemaField("loaded_at", "TIMESTAMP", mode="REQUIRED"),
]


class QuarantineError(RuntimeError):
    """Raised when one or more input blobs are quarantined and fail-fast is enabled."""


@dataclass(frozen=True)
class LoaderConfig:
    """Runtime configuration parsed from environment variables or CLI flags."""

    bronze_project: str
    bronze_dataset: str
    execution_project: str
    landing_bucket: str
    source_prefix: str
    target_table: str
    source_format: str = "NEWLINE_DELIMITED_JSON"
    kms_key_id: str = ""
    quarantine_prefix: str = "quarantine/"
    watermark_table: str = "_ingestion_watermarks"
    fail_on_quarantine: bool = True
    target_object: str = ""
    watermark_lookback_days: int = 365
    stale_claim_minutes: int = 30

    def __post_init__(self) -> None:
        """Validate BigQuery identifiers and runtime guardrails."""
        for label, proj in (
            ("bronze_project", self.bronze_project),
            ("execution_project", self.execution_project),
        ):
            if not VALID_PROJECT_ID_RE.fullmatch(proj):
                raise ValueError(f"Invalid GCP project identifier for {label}: {proj!r}")
        for label, ident in (
            ("bronze_dataset", self.bronze_dataset),
            ("target_table", self.target_table),
            ("watermark_table", self.watermark_table),
        ):
            if not VALID_BQ_IDENTIFIER_RE.fullmatch(ident):
                raise ValueError(f"Invalid BigQuery identifier for {label}: {ident!r}")
        if self.watermark_lookback_days < 0:
            raise ValueError("watermark_lookback_days must be non-negative")
        if self.stale_claim_minutes < 1:
            raise ValueError("stale_claim_minutes must be at least 1")
        if self.target_object:
            parts = PurePosixPath(self.target_object.lstrip("/")).parts
            if ".." in parts:
                raise ValueError(f"Invalid target_object path traversal: {self.target_object!r}")

    @classmethod
    def from_env(cls, target_object_override: str = "") -> "LoaderConfig":
        """Build configuration from required environment variables."""
        bronze_project = _require_env("BRONZE_PROJECT")
        bronze_dataset = _require_env("BRONZE_DATASET")
        landing_bucket = _require_env("LANDING_BUCKET")
        target_table = _require_env("TARGET_TABLE")
        execution_project = os.environ.get("EXECUTION_PROJECT", "").strip() or bronze_project
        source_prefix = _normalize_prefix(os.environ.get("SOURCE_PREFIX", "incoming/"))
        source_format = os.environ.get("SOURCE_FORMAT", "NEWLINE_DELIMITED_JSON").strip().upper()
        if source_format not in SUPPORTED_SOURCE_FORMATS:
            raise ValueError(f"Unsupported SOURCE_FORMAT: {source_format}")
        kms_key_id = os.environ.get("KMS_KEY_ID", "").strip()
        quarantine_prefix = _normalize_prefix(os.environ.get("QUARANTINE_PREFIX", "quarantine/"))
        watermark_table = os.environ.get("WATERMARK_TABLE", "_ingestion_watermarks").strip() or "_ingestion_watermarks"
        fail_raw = os.environ.get("FAIL_ON_QUARANTINE", "true").strip().lower()
        fail_on_quarantine = fail_raw in ("1", "true", "yes")
        target_object_raw = target_object_override or os.environ.get("TARGET_OBJECT", "")
        target_object = target_object_raw.strip().lstrip("/")
        lookback_raw = os.environ.get("WATERMARK_LOOKBACK_DAYS", "365").strip() or "365"
        stale_raw = os.environ.get("STALE_CLAIM_MINUTES", "30").strip() or "30"
        return cls(
            bronze_project=bronze_project,
            bronze_dataset=bronze_dataset,
            execution_project=execution_project,
            landing_bucket=landing_bucket,
            source_prefix=source_prefix,
            target_table=target_table,
            source_format=source_format,
            kms_key_id=kms_key_id,
            quarantine_prefix=quarantine_prefix,
            watermark_table=watermark_table,
            fail_on_quarantine=fail_on_quarantine,
            target_object=target_object,
            watermark_lookback_days=int(lookback_raw),
            stale_claim_minutes=int(stale_raw),
        )


@dataclass(frozen=True)
class BatchResult:
    """Summary counters produced by a single loader run."""

    loaded_files: int
    skipped_files: int
    quarantined_files: int
    loaded_rows: int


def _require_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise ValueError(f"Missing required environment variable: {name}")
    return value


def _normalize_prefix(prefix: str) -> str:
    cleaned = prefix.strip().lstrip("/")
    if cleaned and not cleaned.endswith("/"):
        cleaned += "/"
    return cleaned


def _relative_object_path(blob_name: str, source_prefix: str) -> str:
    clean_name = blob_name.lstrip("/")
    if source_prefix and clean_name.startswith(source_prefix):
        rel = clean_name[len(source_prefix):].lstrip("/")
        if rel:
            return rel
    return clean_name or blob_name.rsplit("/", 1)[-1]


def ensure_watermark_table(
    bq_client: bigquery.Client,
    watermark_table_id: str,
    kms_key_id: str = "",
) -> None:
    """Create the DAY-partitioned BigQuery watermark table when absent."""
    table = bigquery.Table(watermark_table_id, schema=WATERMARK_SCHEMA)
    table.time_partitioning = bigquery.TimePartitioning(
        type_=bigquery.TimePartitioningType.DAY,
        field="loaded_at",
    )
    if kms_key_id:
        table.encryption_configuration = bigquery.EncryptionConfiguration(
            kms_key_name=kms_key_id,
        )
    bq_client.create_table(table, exists_ok=True)


def is_transient_api_error(exc: Exception) -> bool:
    """Return True for transient infrastructure/quota errors safe for Cloud Run retry."""
    code = getattr(exc, "code", None)
    if code is None:
        resp = getattr(exc, "response", None)
        code = getattr(resp, "status_code", None)
    if isinstance(code, int) and not isinstance(code, bool) and code in TRANSIENT_HTTP_CODES:
        return True
    return type(exc).__name__ in TRANSIENT_EXCEPTION_NAMES


def is_quarantinable_load_error(exc: Exception) -> bool:
    """Return True only for HTTP 400 / BadRequest data or schema payload errors."""
    if is_transient_api_error(exc):
        return False
    code = getattr(exc, "code", None)
    if code is None:
        resp = getattr(exc, "response", None)
        code = getattr(resp, "status_code", None)
    if isinstance(code, int) and not isinstance(code, bool):
        return code == 400
    return type(exc).__name__ == "BadRequest"


def fetch_loaded_watermarks(
    bq_client: bigquery.Client,
    watermark_table_id: str,
    lookback_days: int = 365,
    blob_uris: list[str] | None = None,
) -> set[tuple[str, int]]:
    """Return already-loaded (gcs_uri, generation) pairs with partition pruning."""
    if blob_uris is not None and len(blob_uris) == 0:
        return set()

    uri_batches: list[list[str] | None]
    if blob_uris is None:
        uri_batches = [None]
    else:
        uri_batches = [
            blob_uris[idx : idx + WATERMARK_URI_BATCH_SIZE]
            for idx in range(0, len(blob_uris), WATERMARK_URI_BATCH_SIZE)
        ]

    watermarks: set[tuple[str, int]] = set()
    for batch_uris in uri_batches:
        predicates = ["status = 'LOADED'"]
        params: list[Any] = []
        if batch_uris is not None:
            predicates.append("gcs_uri IN UNNEST(@blob_uris)")
            params.append(bigquery.ArrayQueryParameter("blob_uris", "STRING", batch_uris))
        if lookback_days > 0:
            predicates.append(
                "loaded_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL @lookback_days DAY)"
            )
            params.append(bigquery.ScalarQueryParameter("lookback_days", "INT64", int(lookback_days)))
        query = (
            f"SELECT gcs_uri, generation FROM `{watermark_table_id}` "
            f"WHERE {' AND '.join(predicates)}"
        )
        job_config = bigquery.QueryJobConfig(use_legacy_sql=False, query_parameters=params)
        rows = bq_client.query(query, job_config=job_config).result()
        for row in rows:
            uri = row["gcs_uri"] if isinstance(row, dict) else row.gcs_uri
            gen = row["generation"] if isinstance(row, dict) else row.generation
            watermarks.add((str(uri), int(gen)))
    return watermarks


def claim_watermark(
    bq_client: bigquery.Client,
    watermark_table_id: str,
    gcs_uri: str,
    generation: int,
    claim_token: str,
    stale_claim_minutes: int = 30,
    lookback_days: int = 365,
) -> bool:
    """Atomically claim (gcs_uri, generation) using partition-pruned BigQuery MERGE."""
    partition_guard = (
        "AND T.loaded_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL @lookback_days DAY) "
        if lookback_days > 0
        else ""
    )
    query = (
        f"MERGE `{watermark_table_id}` AS T "
        "USING (SELECT @gcs_uri AS gcs_uri, @generation AS generation) AS S "
        f"ON T.gcs_uri = S.gcs_uri AND T.generation = S.generation {partition_guard}"
        "WHEN MATCHED AND T.status = 'IN_PROGRESS' "
        "AND T.claimed_at < TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL @stale_minutes MINUTE) THEN "
        "UPDATE SET status = 'IN_PROGRESS', claim_token = @claim_token, "
        "claimed_at = CURRENT_TIMESTAMP(), loaded_at = CURRENT_TIMESTAMP(), job_id = '' "
        "WHEN NOT MATCHED THEN "
        "INSERT (gcs_uri, generation, status, claim_token, row_count, job_id, claimed_at, loaded_at) "
        "VALUES (S.gcs_uri, S.generation, 'IN_PROGRESS', @claim_token, 0, '', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP())"
    )
    params = [
        bigquery.ScalarQueryParameter("gcs_uri", "STRING", gcs_uri),
        bigquery.ScalarQueryParameter("generation", "INT64", int(generation)),
        bigquery.ScalarQueryParameter("claim_token", "STRING", claim_token),
        bigquery.ScalarQueryParameter("stale_minutes", "INT64", int(stale_claim_minutes)),
    ]
    if lookback_days > 0:
        params.append(bigquery.ScalarQueryParameter("lookback_days", "INT64", int(lookback_days)))
    job_config = bigquery.QueryJobConfig(
        use_legacy_sql=False,
        query_parameters=params,
    )

    for attempt in range(MAX_MERGE_RETRIES):
        try:
            claim_job = bq_client.query(query, job_config=job_config)
            claim_job.result()
            affected = getattr(claim_job, "num_dml_affected_rows", None)
            if isinstance(affected, bool) or not isinstance(affected, int):
                return False
            return affected > 0
        except GoogleAPICallError as exc:
            msg = str(exc).lower()
            if ("serialize" in msg or "concurrent" in msg) and attempt + 1 < MAX_MERGE_RETRIES:
                time.sleep(0.2 * (attempt + 1))
                continue
            raise
    return False


def complete_watermark(
    bq_client: bigquery.Client,
    watermark_table_id: str,
    gcs_uri: str,
    generation: int,
    claim_token: str,
    row_count: int,
    job_id: str,
    lookback_days: int = 365,
) -> None:
    """Promote an IN_PROGRESS watermark claim to LOADED after BigQuery load completes."""
    partition_guard = (
        "AND loaded_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL @lookback_days DAY)"
        if lookback_days > 0
        else ""
    )
    query = (
        f"UPDATE `{watermark_table_id}` "
        "SET status = 'LOADED', "
        "row_count = @row_count, "
        "job_id = @job_id, "
        "loaded_at = CURRENT_TIMESTAMP() "
        "WHERE gcs_uri = @gcs_uri "
        "AND generation = @generation "
        "AND claim_token = @claim_token "
        f"{partition_guard}"
    ).strip()
    params = [
        bigquery.ScalarQueryParameter("gcs_uri", "STRING", gcs_uri),
        bigquery.ScalarQueryParameter("generation", "INT64", int(generation)),
        bigquery.ScalarQueryParameter("claim_token", "STRING", claim_token),
        bigquery.ScalarQueryParameter("row_count", "INT64", int(row_count)),
        bigquery.ScalarQueryParameter("job_id", "STRING", job_id),
    ]
    if lookback_days > 0:
        params.append(bigquery.ScalarQueryParameter("lookback_days", "INT64", int(lookback_days)))
    job_config = bigquery.QueryJobConfig(use_legacy_sql=False, query_parameters=params)
    for attempt in range(MAX_MERGE_RETRIES):
        try:
            bq_client.query(query, job_config=job_config).result()
            return
        except GoogleAPICallError as exc:
            msg = str(exc).lower()
            is_retryable = is_transient_api_error(exc) or "serialize" in msg or "concurrent" in msg
            if is_retryable and attempt + 1 < MAX_MERGE_RETRIES:
                time.sleep(0.2 * (attempt + 1))
                continue
            raise


def release_watermark(
    bq_client: bigquery.Client,
    watermark_table_id: str,
    gcs_uri: str,
    generation: int,
    claim_token: str,
    lookback_days: int = 365,
) -> None:
    """Delete an IN_PROGRESS watermark claim when a load fails or retries."""
    partition_guard = (
        "AND loaded_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL @lookback_days DAY)"
        if lookback_days > 0
        else ""
    )
    query = (
        f"DELETE FROM `{watermark_table_id}` "
        "WHERE gcs_uri = @gcs_uri "
        "AND generation = @generation "
        "AND claim_token = @claim_token "
        "AND status = 'IN_PROGRESS' "
        f"{partition_guard}"
    ).strip()
    params = [
        bigquery.ScalarQueryParameter("gcs_uri", "STRING", gcs_uri),
        bigquery.ScalarQueryParameter("generation", "INT64", int(generation)),
        bigquery.ScalarQueryParameter("claim_token", "STRING", claim_token),
    ]
    if lookback_days > 0:
        params.append(bigquery.ScalarQueryParameter("lookback_days", "INT64", int(lookback_days)))
    job_config = bigquery.QueryJobConfig(use_legacy_sql=False, query_parameters=params)
    bq_client.query(query, job_config=job_config).result()


def stamp_batch_metadata(
    bq_client: bigquery.Client,
    target_table_id: str,
    batch_ingested_at: datetime,
    partition_lookback_days: int = 7,
) -> None:
    """Populate _ingested_at, _op_type, and _cdc_sequence_num once post-batch with partition pruning."""
    try:
        table = bq_client.get_table(target_table_id)
    except GoogleAPICallError:
        return
    schema = getattr(table, "schema", None)
    if not isinstance(schema, (list, tuple)):
        return
    field_by_name = {
        f.name: f for f in schema if isinstance(getattr(f, "name", None), str)
    }
    assignments: list[str] = []
    null_checks: list[str] = []
    params: list[Any] = []
    if "_ingested_at" in field_by_name and not getattr(field_by_name["_ingested_at"], "default_value_expression", None):
        assignments.append("_ingested_at = COALESCE(_ingested_at, @batch_ingested_at)")
        null_checks.append("_ingested_at IS NULL")
        params.append(
            bigquery.ScalarQueryParameter(
                "batch_ingested_at", "TIMESTAMP", batch_ingested_at.isoformat()
            )
        )
    if "_op_type" in field_by_name and not getattr(field_by_name["_op_type"], "default_value_expression", None):
        assignments.append("_op_type = COALESCE(_op_type, 'BATCH')")
        null_checks.append("_op_type IS NULL")
    if "_cdc_sequence_num" in field_by_name and not getattr(field_by_name["_cdc_sequence_num"], "default_value_expression", None):
        assignments.append("_cdc_sequence_num = COALESCE(_cdc_sequence_num, 0)")
        null_checks.append("_cdc_sequence_num IS NULL")
    if not assignments:
        return

    where_parts = [f"({' OR '.join(null_checks)})"]
    tp = getattr(table, "time_partitioning", None)
    tp_field = getattr(tp, "field", None) if tp is not None else None
    lookback = max(1, int(partition_lookback_days))
    if isinstance(tp_field, str) and tp_field in field_by_name and tp_field != "_ingested_at":
        tp_type = str(getattr(field_by_name[tp_field], "field_type", "DATE")).upper()
        params.append(bigquery.ScalarQueryParameter("partition_lookback_days", "INT64", lookback))
        if tp_type == "TIMESTAMP":
            where_parts.append(
                f"({tp_field} IS NULL OR {tp_field} >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL @partition_lookback_days DAY))"
            )
        elif tp_type == "DATETIME":
            where_parts.append(
                f"({tp_field} IS NULL OR {tp_field} >= CAST(TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL @partition_lookback_days DAY) AS DATETIME))"
            )
        else:
            where_parts.append(
                f"({tp_field} IS NULL OR {tp_field} >= DATE_SUB(CURRENT_DATE(), INTERVAL @partition_lookback_days DAY))"
            )
    elif tp is not None and tp_field is None:
        params.append(bigquery.ScalarQueryParameter("partition_lookback_days", "INT64", lookback))
        where_parts.append(
            "(_PARTITIONTIME IS NULL OR _PARTITIONTIME >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL @partition_lookback_days DAY))"
        )

    query = (
        f"UPDATE `{target_table_id}` "
        f"SET {', '.join(assignments)} "
        f"WHERE {' AND '.join(where_parts)}"
    )
    job_config = bigquery.QueryJobConfig(use_legacy_sql=False, query_parameters=params)
    for attempt in range(MAX_MERGE_RETRIES):
        try:
            bq_client.query(query, job_config=job_config).result()
            return
        except GoogleAPICallError as exc:
            msg = str(exc).lower()
            is_retryable = is_transient_api_error(exc) or "serialize" in msg or "concurrent" in msg
            if is_retryable and attempt + 1 < MAX_MERGE_RETRIES:
                time.sleep(0.2 * (attempt + 1))
                continue
            raise


def table_exists(bq_client: bigquery.Client, table_id: str) -> bool:
    """Return True when the BigQuery destination table already exists."""
    try:
        bq_client.get_table(table_id)
        return True
    except GoogleAPICallError as exc:
        if getattr(exc, "code", None) == 404 or type(exc).__name__ == "NotFound":
            return False
        raise


def build_load_job_config(
    source_format: str,
    kms_key_id: str = "",
    autodetect: bool = True,
) -> bigquery.LoadJobConfig:
    """Construct LoadJobConfig for Bronze append loads."""
    if source_format not in SUPPORTED_SOURCE_FORMATS:
        raise ValueError(f"Unsupported SOURCE_FORMAT: {source_format}")
    kwargs: dict[str, Any] = {
        "source_format": SUPPORTED_SOURCE_FORMATS[source_format],
        "write_disposition": bigquery.WriteDisposition.WRITE_APPEND,
        "autodetect": autodetect,
    }
    if not autodetect:
        kwargs["schema_update_options"] = [
            bigquery.SchemaUpdateOption.ALLOW_FIELD_ADDITION,
        ]
    if source_format == "CSV":
        kwargs["skip_leading_rows"] = 1
    if kms_key_id:
        kwargs["destination_encryption_configuration"] = bigquery.EncryptionConfiguration(
            kms_key_name=kms_key_id,
        )
    return bigquery.LoadJobConfig(**kwargs)


def quarantine_blob(
    bucket: Any,
    blob: Any,
    quarantine_prefix: str,
    gcs_uri: str,
    error_message: str,
    source_prefix: str = "incoming/",
) -> str:
    """Copy a failing object plus error metadata into quarantine while preserving relative paths."""
    rel_path = _relative_object_path(blob.name, source_prefix)
    quarantine_name = f"{quarantine_prefix}{rel_path}"
    bucket.copy_blob(blob, bucket, quarantine_name)
    error_payload = {
        "gcs_uri": gcs_uri,
        "generation": int(blob.generation),
        "quarantine_object": quarantine_name,
        "error_message": error_message,
        "quarantined_at": datetime.now(timezone.utc).isoformat(),
    }
    error_blob = bucket.blob(f"{quarantine_name}.error.json")
    error_blob.upload_from_string(
        json.dumps(error_payload, indent=2) + "\n",
        content_type="application/json",
    )
    blob.delete()
    return f"gs://{bucket.name}/{quarantine_name}"


def _resolve_target_blobs(
    cfg: LoaderConfig,
    gcs: storage.Client,
    bucket: Any,
) -> list[Any] | Any:
    if not cfg.target_object:
        return gcs.list_blobs(cfg.landing_bucket, prefix=cfg.source_prefix)

    target = cfg.target_object.lstrip("/")
    if target.endswith("/") or (cfg.quarantine_prefix and target.startswith(cfg.quarantine_prefix)):
        LOGGER.info("Skipping non-ingestible target object %s", target)
        return []
    if cfg.source_prefix and not target.startswith(cfg.source_prefix):
        LOGGER.info("Skipping target object %s outside source_prefix %s", target, cfg.source_prefix)
        return []
    blob = bucket.get_blob(target)
    if blob is None:
        LOGGER.warning("Target object gs://%s/%s no longer exists", cfg.landing_bucket, target)
        return []
    return [blob]


def run_batch(
    config: LoaderConfig | None = None,
    bq_client: bigquery.Client | None = None,
    storage_client: storage.Client | None = None,
) -> BatchResult:
    """Execute one incremental or single-object GCS-to-Bronze load pass."""
    cfg = config or LoaderConfig.from_env()
    bq = bq_client or bigquery.Client(project=cfg.execution_project)
    gcs = storage_client or storage.Client(project=cfg.execution_project)

    target_table_id = f"{cfg.bronze_project}.{cfg.bronze_dataset}.{cfg.target_table}"
    watermark_table_id = f"{cfg.bronze_project}.{cfg.bronze_dataset}.{cfg.watermark_table}"

    ensure_watermark_table(bq, watermark_table_id, cfg.kms_key_id)
    target_exists = table_exists(bq, target_table_id)

    bucket = gcs.bucket(cfg.landing_bucket)
    raw_blobs = _resolve_target_blobs(cfg, gcs, bucket)
    candidate_blobs = [
        blob
        for blob in raw_blobs
        if not blob.name.endswith("/")
        and not (cfg.quarantine_prefix and blob.name.startswith(cfg.quarantine_prefix))
    ]
    candidate_uris = [f"gs://{cfg.landing_bucket}/{blob.name}" for blob in candidate_blobs]
    loaded_watermarks: set[tuple[str, int]] = set()
    if candidate_uris:
        loaded_watermarks = fetch_loaded_watermarks(
            bq,
            watermark_table_id,
            lookback_days=cfg.watermark_lookback_days,
            blob_uris=candidate_uris,
        )

    batch_run_ts = datetime.now(timezone.utc)
    loaded_files = 0
    skipped_files = 0
    quarantined_files = 0
    loaded_rows = 0
    quarantine_errors: list[str] = []

    for blob in candidate_blobs:
        gcs_uri = f"gs://{cfg.landing_bucket}/{blob.name}"
        generation = int(blob.generation)
        key = (gcs_uri, generation)
        if key in loaded_watermarks:
            skipped_files += 1
            LOGGER.info("Skipping already loaded object %s (generation %s)", gcs_uri, generation)
            continue

        claim_token = uuid.uuid4().hex
        if not claim_watermark(
            bq,
            watermark_table_id,
            gcs_uri=gcs_uri,
            generation=generation,
            claim_token=claim_token,
            stale_claim_minutes=cfg.stale_claim_minutes,
            lookback_days=cfg.watermark_lookback_days,
        ):
            skipped_files += 1
            LOGGER.info("Skipping object %s (generation %s) already claimed or loaded", gcs_uri, generation)
            continue

        job_config = build_load_job_config(
            cfg.source_format,
            cfg.kms_key_id,
            autodetect=not target_exists,
        )
        try:
            load_job = bq.load_table_from_uri(
                gcs_uri,
                target_table_id,
                job_config=job_config,
            )
            load_job.result()
        except GoogleAPICallError as exc:
            error_msg = str(exc)
            try:
                release_watermark(
                    bq,
                    watermark_table_id,
                    gcs_uri=gcs_uri,
                    generation=generation,
                    claim_token=claim_token,
                    lookback_days=cfg.watermark_lookback_days,
                )
            except GoogleAPICallError as release_exc:
                LOGGER.warning("Failed to release claim for %s: %s", gcs_uri, release_exc)

            if not is_quarantinable_load_error(exc):
                LOGGER.error("Non-quarantinable API error loading %s: %s", gcs_uri, error_msg)
                raise

            LOGGER.error("Load failed for %s: %s", gcs_uri, error_msg)
            quarantined_uri = quarantine_blob(
                bucket=bucket,
                blob=blob,
                quarantine_prefix=cfg.quarantine_prefix,
                gcs_uri=gcs_uri,
                error_message=error_msg,
                source_prefix=cfg.source_prefix,
            )
            quarantined_files += 1
            quarantine_errors.append(f"{gcs_uri} -> {quarantined_uri}: {error_msg}")
            continue

        target_exists = True
        rows = int(load_job.output_rows or 0)
        complete_watermark(
            bq,
            watermark_table_id,
            gcs_uri=gcs_uri,
            generation=generation,
            claim_token=claim_token,
            row_count=rows,
            job_id=str(load_job.job_id),
            lookback_days=cfg.watermark_lookback_days,
        )
        loaded_watermarks.add(key)
        loaded_files += 1
        loaded_rows += rows
        LOGGER.info(
            "Loaded %s (%s rows, job %s)",
            gcs_uri,
            rows,
            load_job.job_id,
        )

    if loaded_rows > 0:
        stamp_batch_metadata(bq, target_table_id, batch_run_ts)

    if quarantined_files > 0 and cfg.fail_on_quarantine:
        raise QuarantineError(
            f"Quarantined {quarantined_files} object(s): " + "; ".join(quarantine_errors)
        )

    return BatchResult(
        loaded_files=loaded_files,
        skipped_files=skipped_files,
        quarantined_files=quarantined_files,
        loaded_rows=loaded_rows,
    )


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Load GCS objects into BigQuery Bronze tables.")
    parser.add_argument(
        "--target-object",
        default="",
        help="Optional single GCS object key relative to the landing bucket.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """CLI entrypoint for Cloud Run batch job executions."""
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    args = _parse_args(argv)
    try:
        cfg = LoaderConfig.from_env(target_object_override=args.target_object)
        if args.target_object and not cfg.target_object:
            cfg = replace(cfg, target_object=args.target_object.strip().lstrip("/"))
        result = run_batch(config=cfg)
    except Exception as exc:
        LOGGER.error("Batch ingestion job failed: %s", exc)
        return 1

    LOGGER.info(
        "Batch ingestion completed: loaded_files=%s skipped_files=%s quarantined_files=%s loaded_rows=%s",
        result.loaded_files,
        result.skipped_files,
        result.quarantined_files,
        result.loaded_rows,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
