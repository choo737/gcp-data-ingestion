# Pipeline Workflows Module

This module deploys the Cloud Workflows runner, alert topic, telemetry table, and optional triggers.

## Components

- Creates `${var.prefix}-pipeline-alerts` Pub/Sub topic for structured failure alerts.
- Creates `pipeline_runs` BigQuery table inside `ops_telemetry` for run tracking.
- Provisions a dedicated workflow service account with scoped Dataform, Dataplex, Run, and BigQuery roles.
- Deploys `workflows/medallion_pipeline.workflows.yaml` as a Cloud Workflow.
- Adds optional Cloud Scheduler and Cloud Storage Eventarc triggers.
