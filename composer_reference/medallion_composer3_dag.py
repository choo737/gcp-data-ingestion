"""Reference Cloud Composer 3 DAG for Medallion ELT beyond Cloud Workflows."""

from __future__ import annotations

from datetime import datetime, timedelta
import os

from airflow import DAG
from airflow.providers.google.cloud.operators.dataform import (
    DataformCreateCompilationResultOperator,
    DataformCreateWorkflowInvocationOperator,
)
from airflow.providers.google.cloud.operators.dataplex import (
    DataplexCreateOrUpdateDataQualityScanOperator,
    DataplexRunDataProfileScanOperator,
)

PROJECT_ID = os.environ.get("ETL_COMPUTE_PROJECT_ID", "example-etl-project")
GOLD_PROJECT_ID = os.environ.get("PRIMARY_GOLD_PROJECT_ID", "example-gold-project")
GOLD_DATASET_ID = os.environ.get("PRIMARY_GOLD_DATASET_ID", "gold_mart")
REGION = os.environ.get("GCP_REGION", "asia-southeast1")
REPOSITORY_ID = os.environ.get("DATAFORM_REPOSITORY_ID", "ent-medallion")
PROFILE_SCAN_ID = os.environ.get("DATAPLEX_PROFILE_SCAN_ID", "ent-masked-customers-canary-profile")
QUALITY_SCAN_ID = os.environ.get("DATAPLEX_QUALITY_SCAN_ID", "ent-gold-daily-revenue-quality")

DEFAULT_ARGS = {
    "owner": "data-platform",
    "depends_on_past": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}

with DAG(
    dag_id="medallion_composer3_reference",
    default_args=DEFAULT_ARGS,
    description="Reference Airflow DAG compiling Dataform SQLX and running Dataplex checks.",
    schedule="0 2 * * *",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["medallion", "dataform", "dataplex"],
) as dag:
    compile_medallion = DataformCreateCompilationResultOperator(
        task_id="compile_medallion",
        project_id=PROJECT_ID,
        region=REGION,
        repository_id=REPOSITORY_ID,
        compilation_result={
            "release_config": (
                f"projects/{PROJECT_ID}/locations/{REGION}/"
                f"repositories/{REPOSITORY_ID}/releaseConfigs/prod-main"
            ),
        },
    )

    run_medallion = DataformCreateWorkflowInvocationOperator(
        task_id="run_medallion",
        project_id=PROJECT_ID,
        region=REGION,
        repository_id=REPOSITORY_ID,
        workflow_invocation={
            "compilation_result": (
                "{{ task_instance.xcom_pull(task_ids='compile_medallion')['name'] }}"
            ),
            "invocation_config": {
                "transitive_dependencies_included": True,
                "fully_refresh_incremental_tables_enabled": False,
            },
        },
    )

    upsert_quality_scan = DataplexCreateOrUpdateDataQualityScanOperator(
        task_id="upsert_gold_quality_scan",
        project_id=GOLD_PROJECT_ID,
        region=REGION,
        data_scan_id=QUALITY_SCAN_ID,
        body={
            "data": {
                "resource": (
                    f"//bigquery.googleapis.com/projects/{GOLD_PROJECT_ID}/"
                    f"datasets/{GOLD_DATASET_ID}/tables/mart_daily_revenue"
                ),
            },
            "data_quality_spec": {
                "rules": [
                    {
                        "column": "order_date",
                        "non_null_expectation": {},
                    },
                    {
                        "column": "total_net_amount",
                        "range_expectation": {
                            "min_value": "0",
                            "strict_min_enabled": False,
                        },
                    },
                ],
            },
        },
    )

    run_profile_scan = DataplexRunDataProfileScanOperator(
        task_id="run_profile_scan",
        project_id=GOLD_PROJECT_ID,
        region=REGION,
        data_scan_id=PROFILE_SCAN_ID,
    )

    compile_medallion >> run_medallion >> [upsert_quality_scan, run_profile_scan]
