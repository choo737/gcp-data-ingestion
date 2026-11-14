"""Hermetic tests for batch loader, workflows, Composer DAG, linker, and IAM."""

from __future__ import annotations

import ast
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import MagicMock

REPO_ROOT = Path(__file__).resolve().parent.parent


def _install_google_cloud_test_shims() -> type[Exception]:
    """Provide minimal Google Cloud SDK types inside tests when wheels are absent."""
    try:
        from google.api_core.exceptions import GoogleAPICallError  # type: ignore
        from google.cloud import bigquery, storage  # type: ignore  # noqa: F401
        return GoogleAPICallError
    except ImportError:
        pass

    class _FakeGoogleAPICallError(Exception):
        pass

    google_mod = types.ModuleType("google")
    api_core_mod = types.ModuleType("google.api_core")
    exceptions_mod = types.ModuleType("google.api_core.exceptions")
    exceptions_mod.GoogleAPICallError = _FakeGoogleAPICallError

    cloud_mod = types.ModuleType("google.cloud")
    bigquery_mod = types.ModuleType("google.cloud.bigquery")
    storage_mod = types.ModuleType("google.cloud.storage")

    class _SourceFormat:
        CSV = "CSV"
        NEWLINE_DELIMITED_JSON = "NEWLINE_DELIMITED_JSON"
        PARQUET = "PARQUET"

    class _WriteDisposition:
        WRITE_APPEND = "WRITE_APPEND"

    class _TimePartitioningType:
        DAY = "DAY"

    class _TimePartitioning:
        def __init__(self, type_: str = "DAY", field: str | None = None) -> None:
            self.type_ = type_
            self.field = field

    class _SchemaUpdateOption:
        ALLOW_FIELD_ADDITION = "ALLOW_FIELD_ADDITION"

    class _SchemaField:
        def __init__(self, name: str, field_type: str, mode: str = "NULLABLE") -> None:
            self.name = name
            self.field_type = field_type
            self.mode = mode

    class _EncryptionConfiguration:
        def __init__(self, kms_key_name: str) -> None:
            self.kms_key_name = kms_key_name

    class _Table:
        def __init__(self, table_ref: str, schema=None) -> None:
            self.table_ref = table_ref
            self.schema = schema
            self.encryption_configuration = None
            self.time_partitioning = None

    class _LoadJobConfig:
        def __init__(self, **kwargs) -> None:
            self.kwargs = kwargs

    class _ScalarQueryParameter:
        def __init__(self, name: str, param_type: str, value) -> None:
            self.name = name
            self.param_type = param_type
            self.value = value

    class _QueryJobConfig:
        def __init__(self, **kwargs) -> None:
            self.kwargs = kwargs

    bigquery_mod.SourceFormat = _SourceFormat
    bigquery_mod.WriteDisposition = _WriteDisposition
    bigquery_mod.TimePartitioningType = _TimePartitioningType
    bigquery_mod.TimePartitioning = _TimePartitioning
    bigquery_mod.SchemaUpdateOption = _SchemaUpdateOption
    bigquery_mod.SchemaField = _SchemaField
    bigquery_mod.EncryptionConfiguration = _EncryptionConfiguration
    bigquery_mod.Table = _Table
    bigquery_mod.LoadJobConfig = _LoadJobConfig
    bigquery_mod.ScalarQueryParameter = _ScalarQueryParameter
    bigquery_mod.QueryJobConfig = _QueryJobConfig
    bigquery_mod.Client = MagicMock

    storage_mod.Client = MagicMock

    sys.modules["google"] = google_mod
    sys.modules["google.api_core"] = api_core_mod
    sys.modules["google.api_core.exceptions"] = exceptions_mod
    sys.modules["google.cloud"] = cloud_mod
    sys.modules["google.cloud.bigquery"] = bigquery_mod
    sys.modules["google.cloud.storage"] = storage_mod
    return _FakeGoogleAPICallError


GoogleAPICallError = _install_google_cloud_test_shims()
LOADER_PATH = REPO_ROOT / "jobs" / "gcs_to_bronze" / "loader.py"
LOADER_SPEC = importlib.util.spec_from_file_location("gcs_to_bronze_loader", LOADER_PATH)
assert LOADER_SPEC and LOADER_SPEC.loader
loader = importlib.util.module_from_spec(LOADER_SPEC)
sys.modules["gcs_to_bronze_loader"] = loader
LOADER_SPEC.loader.exec_module(loader)


class IngestionAndWorkflowsTest(unittest.TestCase):
    """Verify loader logic, Cloud Workflows YAML, Composer DAG, linker, and IAM."""

    def test_loader_watermark_partitioned_merge_claim_and_complete(self) -> None:
        cfg = loader.LoaderConfig(
            bronze_project="bronze-proj",
            bronze_dataset="ent_bronze_raw",
            execution_project="etl-proj",
            landing_bucket="bronze-proj-landing",
            source_prefix="incoming/",
            target_table="pos_orders_batch_cdc",
            source_format="NEWLINE_DELIMITED_JSON",
            kms_key_id="projects/net/locations/asia-southeast1/keyRings/kr/cryptoKeys/k",
        )

        bq_client = MagicMock()
        select_query_job = MagicMock()
        select_query_job.result.return_value = [
            {"gcs_uri": "gs://bronze-proj-landing/incoming/already.json", "generation": 100},
        ]
        merge_claim_job = MagicMock()
        merge_claim_job.num_dml_affected_rows = 1
        merge_claim_job.result.return_value = []
        complete_update_job = MagicMock()
        complete_update_job.result.return_value = []
        bq_client.query.side_effect = [select_query_job, merge_claim_job, complete_update_job]

        load_job = MagicMock()
        load_job.job_id = "bq-load-123"
        load_job.output_rows = 42
        load_job.result.return_value = None
        bq_client.load_table_from_uri.return_value = load_job

        dir_blob = MagicMock()
        dir_blob.name = "incoming/"
        dir_blob.generation = 1

        quarantine_blob = MagicMock()
        quarantine_blob.name = "quarantine/old.json"
        quarantine_blob.generation = 2

        already_blob = MagicMock()
        already_blob.name = "incoming/already.json"
        already_blob.generation = 100

        new_blob = MagicMock()
        new_blob.name = "incoming/new_orders.json"
        new_blob.generation = 200

        storage_client = MagicMock()
        storage_client.list_blobs.return_value = [
            dir_blob,
            quarantine_blob,
            already_blob,
            new_blob,
        ]

        result = loader.run_batch(config=cfg, bq_client=bq_client, storage_client=storage_client)

        self.assertEqual(result.loaded_files, 1)
        self.assertEqual(result.skipped_files, 1)
        self.assertEqual(result.quarantined_files, 0)
        self.assertEqual(result.loaded_rows, 42)

        bq_client.create_table.assert_called_once()
        created_table = bq_client.create_table.call_args.args[0]
        self.assertIsNotNone(created_table.time_partitioning)
        self.assertEqual(created_table.time_partitioning.field, "loaded_at")
        self.assertEqual(created_table.time_partitioning.type_, "DAY")

        bq_client.load_table_from_uri.assert_called_once()
        load_args, load_kwargs = bq_client.load_table_from_uri.call_args
        self.assertEqual(load_args[0], "gs://bronze-proj-landing/incoming/new_orders.json")
        self.assertEqual(load_args[1], "bronze-proj.ent_bronze_raw.pos_orders_batch_cdc")
        job_cfg = load_kwargs["job_config"]
        cfg_attrs = getattr(job_cfg, "kwargs", None) or vars(job_cfg)
        self.assertFalse(cfg_attrs.get("autodetect", getattr(job_cfg, "autodetect", True)))
        schema_opts = cfg_attrs.get(
            "schema_update_options", getattr(job_cfg, "schema_update_options", [])
        )
        self.assertEqual(schema_opts, ["ALLOW_FIELD_ADDITION"])

        self.assertEqual(bq_client.query.call_count, 3)
        select_sql = bq_client.query.call_args_list[0].args[0]
        self.assertIn("TIMESTAMP_SUB", select_sql)
        self.assertIn("@lookback_days", select_sql)

        merge_sql = bq_client.query.call_args_list[1].args[0]
        self.assertIn("MERGE `bronze-proj.ent_bronze_raw._ingestion_watermarks`", merge_sql)
        self.assertIn("IN_PROGRESS", merge_sql)
        self.assertIn("@stale_minutes", merge_sql)
        self.assertNotIn("new_orders.json", merge_sql)

        update_sql = bq_client.query.call_args_list[2].args[0]
        self.assertIn("UPDATE `bronze-proj.ent_bronze_raw._ingestion_watermarks`", update_sql)
        self.assertIn("status = 'LOADED'", update_sql)

    def test_loader_concurrent_merge_claim_zero_rows_skips_load(self) -> None:
        cfg = loader.LoaderConfig(
            bronze_project="bronze-proj",
            bronze_dataset="ent_bronze_raw",
            execution_project="etl-proj",
            landing_bucket="bronze-proj-landing",
            source_prefix="incoming/",
            target_table="pos_orders_batch_cdc",
            target_object="incoming/2026/01/orders.json",
        )

        bq_client = MagicMock()
        merge_lost_job = MagicMock()
        merge_lost_job.num_dml_affected_rows = 0
        merge_lost_job.result.return_value = []
        bq_client.query.return_value = merge_lost_job

        blob = MagicMock()
        blob.name = "incoming/2026/01/orders.json"
        blob.generation = 555

        bucket = MagicMock()
        bucket.get_blob.return_value = blob
        storage_client = MagicMock()
        storage_client.bucket.return_value = bucket

        result = loader.run_batch(config=cfg, bq_client=bq_client, storage_client=storage_client)
        self.assertEqual(result.loaded_files, 0)
        self.assertEqual(result.skipped_files, 1)
        storage_client.list_blobs.assert_not_called()
        bucket.get_blob.assert_called_once_with("incoming/2026/01/orders.json")
        bq_client.load_table_from_uri.assert_not_called()

    def test_loader_target_object_ignores_quarantine_and_supports_cli_arg(self) -> None:
        env_backup = os.environ.copy()
        try:
            os.environ.update({
                "BRONZE_PROJECT": "bronze-proj",
                "BRONZE_DATASET": "ent_bronze_raw",
                "LANDING_BUCKET": "bronze-proj-landing",
                "TARGET_TABLE": "pos_orders_batch_cdc",
            })
            args = loader._parse_args(["--target-object", "incoming/day1/part.json"])
            self.assertEqual(args.target_object, "incoming/day1/part.json")
            cfg = loader.LoaderConfig.from_env(target_object_override=args.target_object)
            self.assertEqual(cfg.target_object, "incoming/day1/part.json")

            quarantine_cfg = loader.LoaderConfig(
                bronze_project="bronze-proj",
                bronze_dataset="ent_bronze_raw",
                execution_project="etl-proj",
                landing_bucket="bronze-proj-landing",
                source_prefix="incoming/",
                target_table="pos_orders_batch_cdc",
                target_object="quarantine/day1/part.json",
            )
            bq_client = MagicMock()
            storage_client = MagicMock()
            result = loader.run_batch(config=quarantine_cfg, bq_client=bq_client, storage_client=storage_client)
            self.assertEqual(result.loaded_files, 0)
            self.assertEqual(result.skipped_files, 0)
            bq_client.load_table_from_uri.assert_not_called()
        finally:
            os.environ.clear()
            os.environ.update(env_backup)

    def test_loader_autodetects_first_blob_only_when_target_missing(self) -> None:
        cfg = loader.LoaderConfig(
            bronze_project="bronze-proj",
            bronze_dataset="ent_bronze_raw",
            execution_project="etl-proj",
            landing_bucket="bronze-proj-landing",
            source_prefix="incoming/",
            target_table="new_orders_cdc",
        )

        not_found = GoogleAPICallError("not found")
        setattr(not_found, "code", 404)

        bq_client = MagicMock()
        bq_client.get_table.side_effect = not_found
        select_query_job = MagicMock()
        select_query_job.result.return_value = []
        claim_a = MagicMock()
        claim_a.num_dml_affected_rows = 1
        claim_a.result.return_value = []
        complete_a = MagicMock()
        complete_a.result.return_value = []
        claim_b = MagicMock()
        claim_b.num_dml_affected_rows = 1
        claim_b.result.return_value = []
        complete_b = MagicMock()
        complete_b.result.return_value = []
        bq_client.query.side_effect = [select_query_job, claim_a, complete_a, claim_b, complete_b]

        load_job = MagicMock()
        load_job.job_id = "bq-load-new"
        load_job.output_rows = 2
        load_job.result.return_value = None
        bq_client.load_table_from_uri.return_value = load_job

        blob_a = MagicMock()
        blob_a.name = "incoming/part_a.json"
        blob_a.generation = 11
        blob_b = MagicMock()
        blob_b.name = "incoming/part_b.json"
        blob_b.generation = 12

        storage_client = MagicMock()
        storage_client.list_blobs.return_value = [blob_a, blob_b]

        result = loader.run_batch(config=cfg, bq_client=bq_client, storage_client=storage_client)
        self.assertEqual(result.loaded_files, 2)
        self.assertEqual(result.loaded_rows, 4)

        calls = bq_client.load_table_from_uri.call_args_list
        self.assertEqual(len(calls), 2)
        cfg_0 = calls[0].kwargs["job_config"]
        cfg_1 = calls[1].kwargs["job_config"]
        auto_0 = cfg_0.kwargs["autodetect"] if hasattr(cfg_0, "kwargs") else cfg_0.autodetect
        auto_1 = cfg_1.kwargs["autodetect"] if hasattr(cfg_1, "kwargs") else cfg_1.autodetect
        self.assertTrue(auto_0)
        self.assertFalse(auto_1)

    def test_loader_quarantines_nested_relative_path_and_releases_claim(self) -> None:
        cfg = loader.LoaderConfig(
            bronze_project="bronze-proj",
            bronze_dataset="ent_bronze_raw",
            execution_project="etl-proj",
            landing_bucket="bronze-proj-landing",
            source_prefix="incoming/",
            target_table="pos_orders_batch_cdc",
            fail_on_quarantine=True,
        )

        bq_client = MagicMock()
        select_query_job = MagicMock()
        select_query_job.result.return_value = []
        claim_job = MagicMock()
        claim_job.num_dml_affected_rows = 1
        claim_job.result.return_value = []
        release_job = MagicMock()
        release_job.result.return_value = []
        bq_client.query.side_effect = [select_query_job, claim_job, release_job]
        bq_client.load_table_from_uri.side_effect = GoogleAPICallError("schema mismatch")

        bad_blob = MagicMock()
        bad_blob.name = "incoming/2026/01/orders.json"
        bad_blob.generation = 999

        error_sidecar = MagicMock()
        bucket = MagicMock()
        bucket.name = "bronze-proj-landing"
        bucket.blob.return_value = error_sidecar

        storage_client = MagicMock()
        storage_client.bucket.return_value = bucket
        storage_client.list_blobs.return_value = [bad_blob]

        with self.assertLogs("gcs_to_bronze", level="ERROR") as log_ctx:
            with self.assertRaises(loader.QuarantineError):
                loader.run_batch(config=cfg, bq_client=bq_client, storage_client=storage_client)
        self.assertTrue(any("schema mismatch" in msg for msg in log_ctx.output))

        bucket.copy_blob.assert_called_once_with(bad_blob, bucket, "quarantine/2026/01/orders.json")
        bucket.blob.assert_called_once_with("quarantine/2026/01/orders.json.error.json")
        error_sidecar.upload_from_string.assert_called_once()
        bad_blob.delete.assert_called_once()
        release_sql = bq_client.query.call_args_list[2].args[0]
        self.assertIn("DELETE FROM `bronze-proj.ent_bronze_raw._ingestion_watermarks`", release_sql)

    def test_loader_from_env_rejects_missing_and_invalid_format(self) -> None:
        with self.assertRaises(ValueError):
            loader.LoaderConfig.from_env()

        env_backup = os.environ.copy()
        try:
            os.environ.update({
                "BRONZE_PROJECT": "p",
                "BRONZE_DATASET": "d",
                "LANDING_BUCKET": "b",
                "TARGET_TABLE": "t",
                "SOURCE_FORMAT": "AVRO",
            })
            with self.assertRaises(ValueError):
                loader.LoaderConfig.from_env()
        finally:
            os.environ.clear()
            os.environ.update(env_backup)

    def test_workflows_yaml_ga_v1_bounded_polls_and_env_parity(self) -> None:
        wf_path = REPO_ROOT / "workflows" / "medallion_pipeline.workflows.yaml"
        wf_text = wf_path.read_text(encoding="utf-8")

        try:
            import yaml  # type: ignore

            parsed = yaml.safe_load(wf_text)
            self.assertIn("main", parsed)
            self.assertEqual(parsed["main"]["params"], ["input"])
        except ImportError:
            self.assertIn("main:", wf_text)
            self.assertIn("params: [input]", wf_text)

        self.assertNotIn("v1beta1", wf_text)
        required_fragments = (
            "https://run.googleapis.com/v2/",
            "https://dataform.googleapis.com/v1/",
            "/compilationResults",
            "compilationErrors",
            "/workflowInvocations",
            "codeCompilationConfig:",
            "defaultDatabase:",
            "assertionSchema:",
            "effective_release_config",
            "BRONZE_PROJECT_ID",
            "BRONZE_DATASET_ID",
            "SILVER_PROJECT_ID",
            "SILVER_DATASET_ID",
            "GOLD_PROJECT_ID",
            "GOLD_DATASET_ID",
            "ASSERTIONS_DATASET_ID",
            "include_stream_orders:",
            "include_batch_orders:",
            "pii_restricted_policy_tag:",
            "pii_masked_policy_tag:",
            "allow_untagged_pii:",
            "https://dataplex.googleapis.com/v1/",
            "DATAPLEX_SCAN_ID",
            "DATAPLEX_QUALITY_SCAN_ID",
            "max_polls: 120",
            "poll_interval_seconds: 10",
            "IGNORED_QUARANTINE_OBJECT",
            'name: "TARGET_OBJECT"',
            "https://bigquery.googleapis.com/bigquery/v2/projects/",
            "useLegacySql: false",
            'parameterMode: "NAMED"',
            "queryParameters:",
            "base64.encode(json.encode(alert_payload))",
            "https://pubsub.googleapis.com/v1/",
            "raise:",
        )
        for fragment in required_fragments:
            self.assertIn(fragment, wf_text)

        for expr in re.findall(r"'\$\{(.+)\}'", wf_text):
            stripped_strings = re.sub(r'"[^"]*"', '""', expr)
            self.assertNotIn("{", stripped_strings, f"Inline brace literal inside expression: {expr}")
            self.assertNotIn("?", stripped_strings, f"Unsupported ternary operator inside Cloud Workflows expression: {expr}")

        for match in re.finditer(r"\{(\d+)(?:,(\d+))?\}", wf_text):
            upper = int(match.group(2) or match.group(1))
            self.assertLessEqual(upper, 100, f"RE2 quantifier > 100 in workflow YAML: {match.group(0)}")

        wf_main = (REPO_ROOT / "modules/ingestion/pipeline-workflows/main.tf").read_text(encoding="utf-8")
        env_calls = set(re.findall(r'sys\.get_env\("([A-Z0-9_]+)"\)', wf_text))
        user_env_calls = [e for e in env_calls if not e.startswith("GOOGLE_CLOUD_WORKFLOW_")]
        self.assertLessEqual(
            len(user_env_calls),
            20,
            f"Cloud Workflows enforces <= 20 user_env_vars, found {len(user_env_calls)}: {sorted(user_env_calls)}",
        )
        for env_name in sorted(user_env_calls):
            self.assertIn(f"{env_name}", wf_main, f"Workflow env var {env_name} missing from pipeline-workflows user_env_vars")

    def test_composer_reference_dag_valid_python_and_operators(self) -> None:
        dag_path = REPO_ROOT / "composer_reference" / "medallion_composer3_dag.py"
        dag_text = dag_path.read_text(encoding="utf-8")
        tree = ast.parse(dag_text, filename=str(dag_path))
        self.assertIsInstance(tree, ast.Module)
        for symbol in (
            "DataformCreateCompilationResultOperator",
            "DataformCreateWorkflowInvocationOperator",
            "DataplexCreateOrUpdateDataQualityScanOperator",
            "DataplexRunDataProfileScanOperator",
        ):
            self.assertIn(symbol, dag_text)

    def test_link_stages_script_local_gcs_and_env_modes(self) -> None:
        script_path = REPO_ROOT / "scripts" / "link-stages.sh"
        self.assertTrue(script_path.is_file())
        self.assertTrue(script_path.stat().st_mode & stat.S_IXUSR)

        syntax = subprocess.run(["bash", "-n", str(script_path)], capture_output=True, text=True, check=False)
        self.assertEqual(syntax.returncode, 0, syntax.stderr)

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            gcs_store = tmp_path / "gcs_store"
            src_a = tmp_path / "stage_a"
            src_b = tmp_path / "stage_b"
            dst = tmp_path / "stage_dst"
            for directory in (bin_dir, gcs_store, src_a, src_b, dst):
                directory.mkdir()
            (src_a / "staging").mkdir()
            (src_b / "staging").mkdir()

            (dst / "variables.tf").write_text(
                'variable "core_storage_project_id" {\n  type = string\n}\n'
                'variable "kms_key_id" {\n  type = string\n}\n'
                'variable "environment" {\n  type = string\n}\n'
                'variable "secret_val" {\n  type = string\n}\n'
                'variable "stale_var" {\n  type = string\n}\n',
                encoding="utf-8",
            )
            linked_path = dst / "00_linked.auto.tfvars.json"
            linked_path.write_text('{"stale_var": "old"}\n', encoding="utf-8")

            tf_shim = bin_dir / "terraform"
            tf_shim.write_text(
                "#!/usr/bin/env python3\n"
                "import json, sys\n"
                "arg = next(a for a in sys.argv[1:] if a.startswith('-chdir='))\n"
                "src = arg.split('=', 1)[1]\n"
                "if 'stage_a' in src:\n"
                "    val = 'proj-core-stg' if src.endswith('/staging') else 'proj-core'\n"
                "    print(json.dumps({'core_storage_project_id': {'value': val}, 'secret_val': {'value': 's', 'sensitive': True}, 'unused': {'value': 'x'}}))\n"
                "else:\n"
                "    print(json.dumps({'kms_key_id': {'value': 'projects/p/locations/r/keyRings/k/cryptoKeys/c'}}))\n",
                encoding="utf-8",
            )
            tf_shim.chmod(0o755)

            gcloud_shim = bin_dir / "gcloud"
            gcloud_shim.write_text(
                "#!/usr/bin/env python3\n"
                "from pathlib import Path\n"
                "import shutil, sys\n"
                f"store = Path({str(gcs_store)!r})\n"
                "args = sys.argv[1:]\n"
                "assert args[:2] == ['storage', 'cp']\n"
                "src, dst = args[2], args[3]\n"
                "if dst.startswith('gs://'):\n"
                "    target = store / dst.replace('gs://', '').replace('/', '__')\n"
                "    shutil.copyfile(src, target)\n"
                "elif src.startswith('gs://') and dst == '-':\n"
                "    source = store / src.replace('gs://', '').replace('/', '__')\n"
                "    sys.stdout.write(source.read_text(encoding='utf-8'))\n",
                encoding="utf-8",
            )
            gcloud_shim.chmod(0o755)

            env = os.environ.copy()
            env["PATH"] = f"{bin_dir}:{env['PATH']}"

            local_res = subprocess.run(
                [str(script_path), str(src_a), str(src_b), str(dst)],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(local_res.returncode, 0, local_res.stderr)
            expected = {
                "core_storage_project_id": "proj-core",
                "kms_key_id": "projects/p/locations/r/keyRings/k/cryptoKeys/c",
            }
            self.assertEqual(json.loads(linked_path.read_text(encoding="utf-8")), expected)
            self.assertEqual(stat.S_IMODE(linked_path.stat().st_mode), 0o600)

            linked_path.unlink()
            gcs_uri = "gs://example-state/outputs.json"
            export_res = subprocess.run(
                [str(script_path), "--export-gcs", gcs_uri, str(src_a), str(src_b)],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(export_res.returncode, 0, export_res.stderr)

            from_gcs_res = subprocess.run(
                [str(script_path), "--from-gcs", gcs_uri, str(dst)],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(from_gcs_res.returncode, 0, from_gcs_res.stderr)
            self.assertEqual(json.loads(linked_path.read_text(encoding="utf-8")), expected)

            linked_path.unlink()
            env_export_res = subprocess.run(
                [str(script_path), "--env", "staging", "--export-gcs", gcs_uri, str(src_a), str(src_b)],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(env_export_res.returncode, 0, env_export_res.stderr)
            self.assertTrue((gcs_store / "example-state__staging__outputs.json").is_file())

            env_from_gcs_res = subprocess.run(
                [str(script_path), "--env", "staging", "--from-gcs", gcs_uri, str(dst)],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(env_from_gcs_res.returncode, 0, env_from_gcs_res.stderr)
            self.assertEqual(
                json.loads(linked_path.read_text(encoding="utf-8")),
                {
                    "core_storage_project_id": "proj-core-stg",
                    "environment": "staging",
                    "kms_key_id": "projects/p/locations/r/keyRings/k/cryptoKeys/c",
                },
            )

    def test_least_privilege_iam_policy_tags_and_security_invariants(self) -> None:
        cdc_main = (REPO_ROOT / "modules/ingestion/datastream-cdc/main.tf").read_text(encoding="utf-8")
        self.assertIn("secret_manager_stored_password = var.db_password_secret_version", cdc_main)
        self.assertNotRegex(cdc_main, r"(?m)^\s*password\s*=")
        self.assertIn("psc_interface_config", cdc_main)
        self.assertIn("project = local.effective_compute_project_id", cdc_main)
        self.assertNotIn("project = var.bronze_project_id\n  role    = \"roles/bigquery.jobUser\"", cdc_main)

        pubsub_main = (REPO_ROOT / "modules/ingestion/pubsub-bigquery/main.tf").read_text(encoding="utf-8")
        self.assertIn("google_bigquery_table_iam_member", pubsub_main)
        self.assertNotIn("google_project_iam_member", pubsub_main)
        self.assertIn("dead_letter_policy", pubsub_main)
        self.assertIn("_quarantine", pubsub_main)
        self.assertIn("customer_ic_number", pubsub_main)
        self.assertIn("customer_email", pubsub_main)
        self.assertIn("order_status", pubsub_main)
        self.assertIn("tax_amount", pubsub_main)
        self.assertNotIn("string status =", pubsub_main)
        self.assertIn("policyTags", pubsub_main)

        batch_main = (REPO_ROOT / "modules/ingestion/batch-elt-job/main.tf").read_text(encoding="utf-8")
        self.assertIn("google_storage_bucket_iam_member", batch_main)
        self.assertIn("google_bigquery_dataset_iam_member", batch_main)
        self.assertIn("google_bigquery_table", batch_main)
        self.assertIn("policyTags", batch_main)
        self.assertIn("tax_amount", batch_main)
        self.assertIn("_ingested_at", batch_main)
        self.assertIn("_cdc_sequence_num", batch_main)
        self.assertIn("_op_type", batch_main)
        self.assertIn("field = local.effective_partition_field != \"\" ? local.effective_partition_field : null", batch_main)
        self.assertIn("parallelism = 1", batch_main)
        self.assertIn("vpc_access", batch_main)
        self.assertIn("network_interfaces", batch_main)
        self.assertNotIn("roles/storage.objectAdmin", batch_main)
        project_iam_blocks = re.findall(
            r'resource\s+"google_project_iam_member"\s+"[^"]+"\s*\{([^}]*)\}',
            batch_main,
        )
        self.assertEqual(len(project_iam_blocks), 1)
        self.assertIn('roles/bigquery.jobUser', project_iam_blocks[0])
        self.assertNotIn('roles/bigquery.dataEditor', project_iam_blocks[0])
        self.assertNotIn('roles/storage.', project_iam_blocks[0])

        batch_vars = (REPO_ROOT / "modules/ingestion/batch-elt-job/variables.tf").read_text(encoding="utf-8")
        self.assertIn('default     = ["order_status", "store_id"]', batch_vars)

        sandbox_main = (REPO_ROOT / "stages/sandbox/main.tf").read_text(encoding="utf-8")
        self.assertIn('matches_prefix = ["incoming/"]', sandbox_main)

        sandbox_vars = (REPO_ROOT / "stages/sandbox/variables.tf").read_text(encoding="utf-8")
        for var_name in (
            "project_id",
            "region",
            "prefix",
            "dataset_ids",
            "bronze_dataset_id",
            "ops_telemetry_dataset_id",
            "dataform_repository_name",
            "dataform_release_config_name",
            "dataform_service_account_email",
            "dataplex_scan_names",
            "pii_restricted_policy_tag_id",
            "pii_masked_policy_tag_id",
        ):
            self.assertIn(f'variable "{var_name}"', sandbox_vars)

        enterprise_vars = (REPO_ROOT / "stages/enterprise/variables.tf").read_text(encoding="utf-8")
        for var_name in (
            "core_storage_project_id",
            "core_project_id",
            "etl_compute_project_id",
            "compute_project_id",
            "primary_gold_project_id",
            "analytics_project_id",
            "bi_project_id",
            "governance_project_id",
            "bronze_dataset_id",
            "silver_dataset_id",
            "gold_dataset_id",
            "quarantine_dataset_id",
            "landing_bucket_name",
            "ops_telemetry_dataset_id",
            "dataform_repository_name",
            "dataform_release_config_name",
            "dataform_release_config_id",
            "dataform_service_account_email",
            "dataform_sa_email",
            "batch_loader_sa_email",
            "pubsub_writer_sa_email",
            "dataplex_scan_names",
            "dataplex_profile_scan_id",
            "dataplex_quality_scan_id",
            "kms_key_id",
            "kms_key_name",
            "pii_restricted_policy_tag_id",
            "pii_masked_policy_tag_id",
            "artifact_registry_repository_uri",
            "vpc_id",
            "network_id",
            "subnet_id",
            "batch_vpc_egress",
            "datastream_network_attachment_id",
            "notification_channel_ids",
            "region",
            "environment",
            "prefix",
            "delete_contents_on_destroy",
        ):
            self.assertIn(f'variable "{var_name}"', enterprise_vars)

        wf_main = (REPO_ROOT / "modules/ingestion/pipeline-workflows/main.tf").read_text(encoding="utf-8")
        self.assertIn("google_bigquery_dataset_iam_member", wf_main)
        self.assertIn("var.ops_telemetry_dataset_id", wf_main)
        self.assertIn('resource "google_service_account" "trigger_invoker"', wf_main)
        self.assertIn('resource "google_dataform_repository_iam_member" "dataform_editor"', wf_main)
        self.assertNotIn("roles/dataform.editor", wf_main.split("google_dataform_repository_iam_member")[0])
        self.assertRegex(wf_main, r'service\s*=\s*"eventarc\.googleapis\.com"')
        self.assertRegex(wf_main, r'role\s*=\s*"roles/storage\.bucketViewer"')
        self.assertRegex(
            wf_main,
            r'resource\s+"google_project_iam_member"\s+"gcs_eventarc_pubsub_publisher"\s*\{[^}]*project\s*=\s*var\.compute_project_id',
        )
        self.assertIn("google_service_account.trigger_invoker[0].email", wf_main)
        self.assertNotIn("google_service_account.workflow.email", wf_main)

        pyproject = (REPO_ROOT / "jobs/gcs_to_bronze/pyproject.toml").read_text(encoding="utf-8")
        self.assertIn("google-cloud-bigquery==3.47.0", pyproject)
        self.assertIn("google-cloud-storage==3.17.1", pyproject)
        self.assertNotIn("pyarrow", pyproject)

        lock_path = REPO_ROOT / "jobs/gcs_to_bronze/requirements.lock"
        self.assertTrue(lock_path.is_file())
        self.assertIn("--hash=sha256:", lock_path.read_text(encoding="utf-8"))

        dockerfile = (REPO_ROOT / "jobs/gcs_to_bronze/Dockerfile").read_text(encoding="utf-8")
        self.assertRegex(dockerfile, r"FROM python:3\.13-slim@sha256:[0-9a-f]{64}")
        self.assertIn("--require-hashes --no-deps -r requirements.lock", dockerfile)
        self.assertIn("USER 65532:65532", dockerfile)

    def test_agent_docs_skills_makefile_and_ci(self) -> None:
        required_skills = (
            "setup-data-ingestion",
            "add-batch-feed",
            "add-cdc-source",
            "add-streaming-topic",
            "split-domain-ingestion",
        )
        fm_re = re.compile(r"\A---\nname:\s*([a-z0-9-]+)\ndescription:\s*(.+)\n---\n", re.MULTILINE)
        for skill in required_skills:
            skill_path = REPO_ROOT / ".agents/skills" / skill / "SKILL.md"
            self.assertTrue(skill_path.is_file(), f"Missing skill {skill}")
            match = fm_re.match(skill_path.read_text(encoding="utf-8"))
            self.assertIsNotNone(match)
            self.assertEqual(match.group(1), skill)

        for doc_name in ("AGENTS.md", "CLAUDE.md"):
            content = (REPO_ROOT / doc_name).read_text(encoding="utf-8")
            for ref in ("modules/ingestion/", "stages/", "00_linked.auto.tfvars.json", "setup-data-ingestion", "--private"):
                self.assertIn(ref, content, f"{doc_name} missing {ref}")
        self.assertFalse((REPO_ROOT / "GEMINI.md").exists(), "GEMINI.md must not exist")

        makefile = (REPO_ROOT / "Makefile").read_text(encoding="utf-8")
        self.assertIn("ENV ?= dev", makefile)
        self.assertIn("ingestion/$(STAGE)/$(ENV)", makefile)
        self.assertIn("stages/sandbox", makefile)
        self.assertIn("stages/enterprise", makefile)
        self.assertNotIn('.terraform.lock.hcl', makefile)

        for wf_file in ("ci.yml", "build-batch-loader.yml", "terraform-deploy.yml"):
            wf_path = REPO_ROOT / ".github/workflows" / wf_file
            self.assertTrue(wf_path.is_file(), f"Missing workflow {wf_file}")
            wf_content = wf_path.read_text(encoding="utf-8")
            self.assertIn("contents: read", wf_content)
            self.assertRegex(wf_content, r"actions/checkout@[0-9a-f]{40}")

        ci = (REPO_ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
        self.assertIn("1.8.5", ci)
        self.assertRegex(ci, r"hashicorp/setup-terraform@[0-9a-f]{40}")
        self.assertRegex(ci, r"actions/setup-python@[0-9a-f]{40}")

    def test_questionnaire_and_brownfield_doc_alignment(self) -> None:
        questionnaire_path = REPO_ROOT / "QUESTIONNAIRE.md"
        self.assertTrue(questionnaire_path.is_file(), "Missing QUESTIONNAIRE.md")
        q_text = questionnaire_path.read_text(encoding="utf-8")

        required_q_tokens = (
            "https://github.com/choo737/gcp-launchpad",
            "platform-context.json",
            "link-stages.sh",
            "generate-brownfield-link.py",
            "00_linked.auto.tfvars.json",
            "core_project_id",
            "compute_project_id",
            "analytics_project_id",
            "bronze_dataset_id",
            "silver_dataset_id",
            "gold_dataset_id",
            "quarantine_dataset_id",
            "landing_bucket_name",
            "dataform_repository_name",
            "kms_key_id",
            "vpc_id",
            "subnet_id",
            "pii_restricted_policy_tag_id",
            "pii_masked_policy_tag_id",
            "enable_datastream_cdc",
            "enable_pubsub_stream",
            "enable_batch_job",
            "batch_vpc_egress",
            "PRIVATE_RANGES_ONLY",
            "ALL_TRAFFIC",
            "schedule_cron",
            "schedule_time_zone",
            "Asia/Kuala_Lumpur",
            "delete_contents_on_destroy",
            "alert_email_addresses",
            "notification_channel_ids",
        )
        for token in required_q_tokens:
            self.assertIn(token, q_text, f"QUESTIONNAIRE.md missing {token}")

        doc_paths = (
            REPO_ROOT / "README.md",
            REPO_ROOT / "AGENTS.md",
            REPO_ROOT / "CLAUDE.md",
            REPO_ROOT / ".agents/skills/setup-data-ingestion/SKILL.md",
        )
        for doc_path in doc_paths:
            doc_text = doc_path.read_text(encoding="utf-8")
            rel = str(doc_path.relative_to(REPO_ROOT))
            for ref in (
                "QUESTIONNAIRE.md",
                "platform-context.json",
                "https://github.com/choo737/gcp-launchpad",
            ):
                self.assertIn(ref, doc_text, f"{rel} missing {ref}")

        gitignore = (REPO_ROOT / ".gitignore").read_text(encoding="utf-8").splitlines()
        self.assertIn("platform-context.json", gitignore)
        self.assertIn(".cm_project", gitignore)
        self.assertIn(".codemender/", gitignore)
        self.assertNotIn(".terraform.lock.hcl", gitignore)

    def test_batch_elt_job_multi_feed_sa_and_partition_field(self) -> None:
        batch_vars = (REPO_ROOT / "modules/ingestion/batch-elt-job/variables.tf").read_text(encoding="utf-8")
        batch_main = (REPO_ROOT / "modules/ingestion/batch-elt-job/main.tf").read_text(encoding="utf-8")
        batch_outs = (REPO_ROOT / "modules/ingestion/batch-elt-job/outputs.tf").read_text(encoding="utf-8")

        self.assertIn('variable "partition_field"', batch_vars)
        self.assertIn('default     = "order_date"', batch_vars)
        self.assertIn('variable "service_account_email"', batch_vars)

        self.assertIn("count = local.effective_existing_sa == \"\" ? 1 : 0", batch_main)
        self.assertIn("local.default_sa_account_id : local.derived_sa_account_id", batch_main)
        self.assertIn("substr(local.padded_sa_slug, 0, 28)", batch_main)
        self.assertIn("member = local.effective_sa_member", batch_main)
        self.assertIn("service_account = local.effective_sa_email", batch_main)
        self.assertIn("field = local.effective_partition_field != \"\" ? local.effective_partition_field : null", batch_main)
        self.assertIn("value       = local.effective_sa_email", batch_outs)

    def test_enterprise_multi_pipeline_maps_schemas_and_adoption_guide(self) -> None:
        ent_vars = (REPO_ROOT / "stages/enterprise/variables.tf").read_text(encoding="utf-8")
        ent_main = (REPO_ROOT / "stages/enterprise/main.tf").read_text(encoding="utf-8")
        ent_outs = (REPO_ROOT / "stages/enterprise/outputs.tf").read_text(encoding="utf-8")

        for var_name in (
            "pubsub_streams",
            "batch_jobs",
            "datastream_streams",
            "enable_shared_datastream_private_connection",
            "shared_datastream_private_connection_id",
        ):
            self.assertIn(f'variable "{var_name}"', ent_vars)

        for out_name in (
            "additional_pubsub_topics",
            "additional_batch_jobs",
            "additional_datastream_streams",
            "shared_datastream_private_connection_id",
        ):
            self.assertIn(f'output "{out_name}"', ent_outs)

        self.assertIn('resource "google_datastream_private_connection" "shared"', ent_main)
        self.assertIn('module "pubsub_streams"', ent_main)
        self.assertIn('module "batch_jobs"', ent_main)
        self.assertIn('module "datastream_streams"', ent_main)
        self.assertIn("local.any_pubsub_enabled", ent_main)
        self.assertIn("local.any_batch_enabled", ent_main)
        self.assertIn("local.any_datastream_enabled", ent_main)

        schemas_readme = REPO_ROOT / "schemas/README.md"
        proto_path = REPO_ROOT / "schemas/pubsub/crm_events.proto"
        crm_json_path = REPO_ROOT / "schemas/bigquery/crm_events_bronze.json"
        erp_json_path = REPO_ROOT / "schemas/bigquery/erp_invoices_bronze.json"
        for p in (schemas_readme, proto_path, crm_json_path, erp_json_path):
            self.assertTrue(p.is_file(), f"Missing schema asset {p}")

        proto_text = proto_path.read_text(encoding="utf-8")
        self.assertIn('syntax = "proto3";', proto_text)
        self.assertIn("message CrmCustomerEvent", proto_text)

        crm_cols = json.loads(crm_json_path.read_text(encoding="utf-8"))
        crm_names = {c["name"] for c in crm_cols}
        self.assertTrue({"event_id", "customer_id", "subscription_name", "message_id", "publish_time", "attributes"}.issubset(crm_names))

        erp_cols = json.loads(erp_json_path.read_text(encoding="utf-8"))
        erp_names = {c["name"] for c in erp_cols}
        self.assertTrue({"invoice_id", "invoice_date", "vendor_id", "total_amount", "_ingested_at"}.issubset(erp_names))

        guide_path = REPO_ROOT / "docs/03-enterprise-adoption-guide.md"
        self.assertTrue(guide_path.is_file(), "Missing docs/03-enterprise-adoption-guide.md")
        guide_text = guide_path.read_text(encoding="utf-8")
        for token in (
            "flowchart LR",
            "pubsub_streams",
            "batch_jobs",
            "datastream_streams",
            "enable_shared_datastream_private_connection",
            "schemas/pubsub/crm_events.proto",
            "schemas/bigquery/erp_invoices_bronze.json",
            "link-stages.sh",
            "generate-brownfield-link.py",
            "build-batch-loader.yml",
            "terraform-deploy.yml",
            "pipeline_runs",
        ):
            self.assertIn(token, guide_text, f"Adoption guide missing {token}")

        readme_text = (REPO_ROOT / "README.md").read_text(encoding="utf-8")
        for token in (
            "docs/03-enterprise-adoption-guide.md",
            "pubsub_streams",
            "batch_jobs",
            "datastream_streams",
            "schemas/",
        ):
            self.assertIn(token, readme_text, f"README.md missing {token}")

        agents_text = (REPO_ROOT / "AGENTS.md").read_text(encoding="utf-8")
        claude_text = (REPO_ROOT / "CLAUDE.md").read_text(encoding="utf-8")
        for token in ("docs/03-enterprise-adoption-guide.md", "schemas/"):
            self.assertIn(token, agents_text, f"AGENTS.md missing {token}")
            self.assertIn(token, claude_text, f"CLAUDE.md missing {token}")
        self.assertIn("add-batch-feed", agents_text)

    def test_enterprise_terraform_validate_and_path_traversal_rejection(self) -> None:
        tf_bin = shutil.which("terraform")
        if tf_bin is None:
            self.skipTest("terraform binary not installed")

        with tempfile.TemporaryDirectory() as tmp:
            tmp_repo = Path(tmp) / "repo"
            for folder in ("modules", "schemas", "stages", "workflows"):
                shutil.copytree(REPO_ROOT / folder, tmp_repo / folder)

            ent_dir = tmp_repo / "stages" / "enterprise"
            versions_path = ent_dir / "versions.tf"
            versions_path.write_text(
                versions_path.read_text(encoding="utf-8").replace('backend "gcs" {}', 'backend "local" {}'),
                encoding="utf-8",
            )
            shutil.rmtree(ent_dir / ".terraform", ignore_errors=True)
            cached_providers = REPO_ROOT / "stages" / "enterprise" / ".terraform" / "providers"
            init_cmd = [tf_bin, f"-chdir={ent_dir}", "init", "-input=false"]
            if cached_providers.is_dir():
                init_cmd.append(f"-plugin-dir={cached_providers}")
            init_res = subprocess.run(init_cmd, capture_output=True, text=True, check=False)
            self.assertEqual(init_res.returncode, 0, init_res.stderr)

            tfvars = {
                "core_storage_project_id": "core-proj-1",
                "etl_compute_project_id": "etl-proj-1",
                "bronze_dataset_id": "ent_bronze_raw",
                "landing_bucket_name": "core-proj-1-landing",
                "dataform_repository_name": "ent-medallion",
                "batch_container_image": "asia-southeast1-docker.pkg.dev/etl-proj-1/repo/gcs-to-bronze@sha256:" + "0" * 64,
                "enable_shared_datastream_private_connection": True,
                "datastream_network_attachment_id": "projects/net/regions/asia-southeast1/networkAttachments/ds",
                "pubsub_streams": {
                    "crm-events": {
                        "target_table_id": "crm_events_stream",
                        "schema_type": "PROTOCOL_BUFFER",
                        "schema_file": "schemas/pubsub/crm_events.proto",
                        "target_table_schema_file": "schemas/bigquery/crm_events_bronze.json",
                        "target_clustering": ["segment", "event_type"],
                    }
                },
                "batch_jobs": {
                    "erp-invoices": {
                        "source_prefix": "incoming/erp_invoices/",
                        "target_table": "erp_invoices_bronze",
                        "partition_field": "invoice_date",
                        "target_table_schema_file": "schemas/bigquery/erp_invoices_bronze.json",
                    },
                    "hr-roster": {
                        "source_prefix": "incoming/hr_roster/",
                        "target_table": "hr_roster_bronze",
                        "partition_field": "",
                    },
                },
                "datastream_streams": {
                    "erp-db": {
                        "source_engine": "POSTGRESQL",
                        "db_host": "10.20.0.15",
                        "db_username": "datastream_rep",
                        "db_database": "erp_prod",
                        "db_password_secret_version": "projects/etl-proj-1/secrets/erp-pwd/versions/1",
                    },
                    "billing-db": {
                        "source_engine": "MYSQL",
                        "db_host": "10.20.0.16",
                        "db_username": "datastream_rep",
                        "db_password_secret_version": "projects/etl-proj-1/secrets/billing-pwd/versions/1",
                        "cdc_mode": "MERGE",
                    },
                },
            }
            tfvars_path = ent_dir / "multi_pipeline_test.auto.tfvars.json"
            tfvars_path.write_text(json.dumps(tfvars), encoding="utf-8")

            val_res = subprocess.run([tf_bin, f"-chdir={ent_dir}", "validate"], capture_output=True, text=True, check=False)
            self.assertEqual(val_res.returncode, 0, val_res.stdout + val_res.stderr)

            ok_console = subprocess.run(
                [tf_bin, f"-chdir={ent_dir}", "console"],
                input="keys(var.pubsub_streams)\nkeys(var.batch_jobs)\nkeys(var.datastream_streams)\n",
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(ok_console.returncode, 0, ok_console.stderr)
            self.assertEqual(ok_console.stderr.strip(), "")

            tfvars["pubsub_streams"]["crm-events"]["schema_file"] = "schemas/../etc/passwd"
            tfvars_path.write_text(json.dumps(tfvars), encoding="utf-8")
            bad_pubsub = subprocess.run(
                [tf_bin, f"-chdir={ent_dir}", "console"],
                input="keys(var.pubsub_streams)\n",
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertIn("Invalid value for variable", bad_pubsub.stderr)

            tfvars["pubsub_streams"]["crm-events"]["schema_file"] = "schemas/pubsub/crm_events.proto"
            tfvars["batch_jobs"]["erp-invoices"]["target_table_schema_file"] = "../outside.json"
            tfvars_path.write_text(json.dumps(tfvars), encoding="utf-8")
            bad_batch = subprocess.run(
                [tf_bin, f"-chdir={ent_dir}", "console"],
                input="keys(var.batch_jobs)\n",
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertIn("Invalid value for variable", bad_batch.stderr)


if __name__ == "__main__":
    unittest.main()
