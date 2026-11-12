"""Idempotent GCS-to-BigQuery Bronze batch loader with watermark tracking."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import json
import logging
import os
import re
import sys
from typing import Any

from google.api_core.exceptions import GoogleAPICallError
from google.cloud import bigquery
from google.cloud import storage

LOGGER = logging.getLogger("gcs_to_bronze")
VALID_PROJECT_ID_RE = re.compile(r"^[a-z][a-z0-9-]{0,29}$")
VALID_BQ_IDENTIFIER_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]{0,1023}$")

SUPPORTED_SOURCE_FORMATS = {
    "CSV": bigquery.SourceFormat.CSV,
    "NEWLINE_DELIMITED_JSON": bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
    "PARQUET": bigquery.SourceFormat.PARQUET,
}

WATERMARK_SCHEMA = [
    bigquery.SchemaField("gcs_uri", "STRING", mode="REQUIRED"),
    bigquery.SchemaField("generation", "INT64", mode="REQUIRED"),
    bigquery.SchemaField("row_count", "INT64", mode="REQUIRED"),
    bigquery.SchemaField("job_id", "STRING", mode="REQUIRED"),
    bigquery.SchemaField("loaded_at", "TIMESTAMP", mode="REQUIRED"),
]


class QuarantineError(RuntimeError):
    """Raised when one or more input blobs are quarantined and fail-fast is enabled."""


@dataclass(frozen=True)
class LoaderConfig:
    """Runtime configuration parsed from environment variables."""

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

    def __post_init__(self) -> None:
        """Validate BigQuery project, dataset, and table identifiers against injection."""
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

    @classmethod
    def from_env(cls) -> "LoaderConfig":
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


def ensure_watermark_table(
    bq_client: bigquery.Client,
    watermark_table_id: str,
    kms_key_id: str = "",
) -> None:
    """Create the BigQuery watermark table when absent."""
    table = bigquery.Table(watermark_table_id, schema=WATERMARK_SCHEMA)
    if kms_key_id:
        table.encryption_configuration = bigquery.EncryptionConfiguration(
            kms_key_name=kms_key_id,
        )
    bq_client.create_table(table, exists_ok=True)


def fetch_loaded_watermarks(
    bq_client: bigquery.Client,
    watermark_table_id: str,
) -> set[tuple[str, int]]:
    """Return already-loaded (gcs_uri, generation) pairs from BigQuery."""
    query = f"SELECT gcs_uri, generation FROM `{watermark_table_id}`"
    rows = bq_client.query(query).result()
    watermarks: set[tuple[str, int]] = set()
    for row in rows:
        uri = row["gcs_uri"] if isinstance(row, dict) else row.gcs_uri
        gen = row["generation"] if isinstance(row, dict) else row.generation
        watermarks.add((str(uri), int(gen)))
    return watermarks


def build_load_job_config(source_format: str, kms_key_id: str = "") -> bigquery.LoadJobConfig:
    """Construct LoadJobConfig for Bronze append loads."""
    if source_format not in SUPPORTED_SOURCE_FORMATS:
        raise ValueError(f"Unsupported SOURCE_FORMAT: {source_format}")
    kwargs: dict[str, Any] = {
        "source_format": SUPPORTED_SOURCE_FORMATS[source_format],
        "write_disposition": bigquery.WriteDisposition.WRITE_APPEND,
        "autodetect": True,
    }
    if source_format == "CSV":
        kwargs["skip_leading_rows"] = 1
    if kms_key_id:
        kwargs["destination_encryption_configuration"] = bigquery.EncryptionConfiguration(
            kms_key_name=kms_key_id,
        )
    return bigquery.LoadJobConfig(**kwargs)


def record_watermark(
    bq_client: bigquery.Client,
    watermark_table_id: str,
    gcs_uri: str,
    generation: int,
    row_count: int,
    job_id: str,
) -> None:
    """Insert an idempotent load watermark row using parameterized SQL."""
    query = (
        f"INSERT INTO `{watermark_table_id}` "
        "(gcs_uri, generation, row_count, job_id, loaded_at) "
        "VALUES (@gcs_uri, @generation, @row_count, @job_id, CURRENT_TIMESTAMP())"
    )
    job_config = bigquery.QueryJobConfig(
        use_legacy_sql=False,
        query_parameters=[
            bigquery.ScalarQueryParameter("gcs_uri", "STRING", gcs_uri),
            bigquery.ScalarQueryParameter("generation", "INT64", int(generation)),
            bigquery.ScalarQueryParameter("row_count", "INT64", int(row_count)),
            bigquery.ScalarQueryParameter("job_id", "STRING", job_id),
        ],
    )
    bq_client.query(query, job_config=job_config).result()


def quarantine_blob(
    bucket: Any,
    blob: Any,
    quarantine_prefix: str,
    gcs_uri: str,
    error_message: str,
) -> str:
    """Copy a failing source object plus error metadata into quarantine and delete the source."""
    filename = blob.name.rsplit("/", 1)[-1]
    quarantine_name = f"{quarantine_prefix}{filename}"
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


def run_batch(
    config: LoaderConfig | None = None,
    bq_client: bigquery.Client | None = None,
    storage_client: storage.Client | None = None,
) -> BatchResult:
    """Execute one incremental GCS-to-Bronze load pass with watermark deduplication."""
    cfg = config or LoaderConfig.from_env()
    bq = bq_client or bigquery.Client(project=cfg.execution_project)
    gcs = storage_client or storage.Client(project=cfg.execution_project)

    target_table_id = f"{cfg.bronze_project}.{cfg.bronze_dataset}.{cfg.target_table}"
    watermark_table_id = f"{cfg.bronze_project}.{cfg.bronze_dataset}.{cfg.watermark_table}"

    ensure_watermark_table(bq, watermark_table_id, cfg.kms_key_id)
    loaded_watermarks = fetch_loaded_watermarks(bq, watermark_table_id)

    bucket = gcs.bucket(cfg.landing_bucket)
    blobs = gcs.list_blobs(cfg.landing_bucket, prefix=cfg.source_prefix)

    loaded_files = 0
    skipped_files = 0
    quarantined_files = 0
    loaded_rows = 0
    quarantine_errors: list[str] = []

    for blob in blobs:
        if blob.name.endswith("/") or (
            cfg.quarantine_prefix and blob.name.startswith(cfg.quarantine_prefix)
        ):
            continue

        gcs_uri = f"gs://{cfg.landing_bucket}/{blob.name}"
        generation = int(blob.generation)
        key = (gcs_uri, generation)
        if key in loaded_watermarks:
            skipped_files += 1
            LOGGER.info("Skipping already loaded object %s (generation %s)", gcs_uri, generation)
            continue

        job_config = build_load_job_config(cfg.source_format, cfg.kms_key_id)
        try:
            load_job = bq.load_table_from_uri(
                gcs_uri,
                target_table_id,
                job_config=job_config,
            )
            load_job.result()
            rows = int(load_job.output_rows or 0)
            record_watermark(
                bq,
                watermark_table_id,
                gcs_uri=gcs_uri,
                generation=generation,
                row_count=rows,
                job_id=str(load_job.job_id),
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
        except GoogleAPICallError as exc:
            error_msg = str(exc)
            LOGGER.error("Load failed for %s: %s", gcs_uri, error_msg)
            quarantined_uri = quarantine_blob(
                bucket=bucket,
                blob=blob,
                quarantine_prefix=cfg.quarantine_prefix,
                gcs_uri=gcs_uri,
                error_message=error_msg,
            )
            quarantined_files += 1
            quarantine_errors.append(f"{gcs_uri} -> {quarantined_uri}: {error_msg}")

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


def main() -> int:
    """CLI entrypoint for Cloud Run batch job executions."""
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    try:
        result = run_batch()
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
