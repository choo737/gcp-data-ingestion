"""Hermetic tests for batch loader, workflows, Composer DAG, stage linker, and IAM."""

from __future__ import annotations

import ast
import importlib.util
import json
import os
from pathlib import Path
import re
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
    """Verify loader logic, Cloud Workflows YAML, Composer DAG, linker, and HCL security."""

    def test_loader_watermark_dedup_and_parameterized_insert(self) -> None:
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
        insert_query_job = MagicMock()
        insert_query_job.result.return_value = []
        bq_client.query.side_effect = [select_query_job, insert_query_job]

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
        bq_client.load_table_from_uri.assert_called_once()
        load_args, load_kwargs = bq_client.load_table_from_uri.call_args
        self.assertEqual(load_args[0], "gs://bronze-proj-landing/incoming/new_orders.json")
        self.assertEqual(load_args[1], "bronze-proj.ent_bronze_raw.pos_orders_batch_cdc")
        self.assertIn("job_config", load_kwargs)

        self.assertEqual(bq_client.query.call_count, 2)
        insert_call = bq_client.query.call_args_list[1]
        insert_sql = insert_call.args[0]
        self.assertIn("INSERT INTO `bronze-proj.ent_bronze_raw._ingestion_watermarks`", insert_sql)
        self.assertIn("@gcs_uri", insert_sql)
        self.assertNotIn("new_orders.json", insert_sql)

    def test_loader_quarantines_failed_blob_and_raises_when_configured(self) -> None:
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
        bq_client.query.return_value = select_query_job
        bq_client.load_table_from_uri.side_effect = GoogleAPICallError("schema mismatch")

        bad_blob = MagicMock()
        bad_blob.name = "incoming/corrupt.json"
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

        bucket.copy_blob.assert_called_once_with(bad_blob, bucket, "quarantine/corrupt.json")
        bucket.blob.assert_called_once_with("quarantine/corrupt.json.error.json")
        error_sidecar.upload_from_string.assert_called_once()
        bad_blob.delete.assert_called_once()

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

    def test_workflows_yaml_structure_and_parameterized_sql(self) -> None:
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

        required_fragments = (
            "https://run.googleapis.com/v2/",
            "/compilationResults",
            "compilationErrors",
            "/workflowInvocations",
            "https://dataplex.googleapis.com/v1/",
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

    def test_link_stages_script_local_and_gcs_modes(self) -> None:
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

            (dst / "variables.tf").write_text(
                'variable "core_storage_project_id" {\n  type = string\n}\n'
                'variable "kms_key_id" {\n  type = string\n}\n'
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
                "if src.endswith('stage_a'):\n"
                "    print(json.dumps({'core_storage_project_id': {'value': 'proj-core'}, 'secret_val': {'value': 's', 'sensitive': True}, 'unused': {'value': 'x'}}))\n"
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
            self.assertEqual(stat.S_IMODE(linked_path.stat().st_mode), 0o600)

    def test_least_privilege_iam_and_security_invariants(self) -> None:
        cdc_main = (REPO_ROOT / "modules/ingestion/datastream-cdc/main.tf").read_text(encoding="utf-8")
        self.assertIn("secret_manager_stored_password = var.db_password_secret_version", cdc_main)
        self.assertNotRegex(cdc_main, r"(?m)^\s*password\s*=")

        pubsub_main = (REPO_ROOT / "modules/ingestion/pubsub-bigquery/main.tf").read_text(encoding="utf-8")
        self.assertIn("google_bigquery_table_iam_member", pubsub_main)
        self.assertNotIn("google_project_iam_member", pubsub_main)
        self.assertIn("dead_letter_policy", pubsub_main)
        self.assertIn("_quarantine", pubsub_main)

        batch_main = (REPO_ROOT / "modules/ingestion/batch-elt-job/main.tf").read_text(encoding="utf-8")
        self.assertIn("google_storage_bucket_iam_member", batch_main)
        self.assertIn("google_bigquery_dataset_iam_member", batch_main)
        self.assertNotIn("roles/storage.objectAdmin", batch_main)
        project_iam_blocks = re.findall(
            r'resource\s+"google_project_iam_member"\s+"[^"]+"\s*\{([^}]*)\}',
            batch_main,
        )
        self.assertEqual(len(project_iam_blocks), 1)
        self.assertIn('roles/bigquery.jobUser', project_iam_blocks[0])
        self.assertNotIn('roles/bigquery.dataEditor', project_iam_blocks[0])
        self.assertNotIn('roles/storage.', project_iam_blocks[0])

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
        ):
            self.assertIn(f'variable "{var_name}"', sandbox_vars)

        enterprise_vars = (REPO_ROOT / "stages/enterprise/variables.tf").read_text(encoding="utf-8")
        for var_name in (
            "core_storage_project_id",
            "etl_compute_project_id",
            "primary_gold_project_id",
            "bronze_dataset_id",
            "landing_bucket_name",
            "ops_telemetry_dataset_id",
            "dataform_repository_name",
            "dataform_release_config_name",
            "dataform_service_account_email",
            "dataplex_scan_names",
            "kms_key_id",
            "vpc_id",
            "network_id",
            "region",
            "prefix",
            "delete_contents_on_destroy",
        ):
            self.assertIn(f'variable "{var_name}"', enterprise_vars)

        wf_main = (REPO_ROOT / "modules/ingestion/pipeline-workflows/main.tf").read_text(encoding="utf-8")
        self.assertIn("google_bigquery_dataset_iam_member", wf_main)
        self.assertIn("var.ops_telemetry_dataset_id", wf_main)

        pyproject = (REPO_ROOT / "jobs/gcs_to_bronze/pyproject.toml").read_text(encoding="utf-8")
        self.assertIn("google-cloud-bigquery==3.47.0", pyproject)
        self.assertIn("google-cloud-storage==3.17.1", pyproject)
        self.assertNotIn("pyarrow", pyproject)

        dockerfile = (REPO_ROOT / "jobs/gcs_to_bronze/Dockerfile").read_text(encoding="utf-8")
        self.assertIn("FROM python:3.13-slim", dockerfile)
        self.assertIn("USER 65532:65532", dockerfile)

    def test_agent_docs_skills_makefile_and_ci(self) -> None:
        required_skills = (
            "setup-data-ingestion",
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

        for doc_name in ("AGENTS.md", "CLAUDE.md", "GEMINI.md"):
            content = (REPO_ROOT / doc_name).read_text(encoding="utf-8")
            for ref in ("modules/ingestion/", "stages/", "00_linked.auto.tfvars.json", "setup-data-ingestion", "--private"):
                self.assertIn(ref, content, f"{doc_name} missing {ref}")

        makefile = (REPO_ROOT / "Makefile").read_text(encoding="utf-8")
        self.assertIn("stages/sandbox", makefile)
        self.assertIn("stages/enterprise", makefile)

        ci = (REPO_ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
        self.assertIn("contents: read", ci)
        self.assertIn("1.8.5", ci)
        self.assertRegex(ci, r"actions/checkout@[0-9a-f]{40}")
        self.assertRegex(ci, r"hashicorp/setup-terraform@[0-9a-f]{40}")
        self.assertRegex(ci, r"actions/setup-python@[0-9a-f]{40}")


if __name__ == "__main__":
    unittest.main()
