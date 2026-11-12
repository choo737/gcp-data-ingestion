# Pipeline Workflows Module

This module deploys the Cloud Workflows runner, alert topic, telemetry table, and split-SA triggers.

## Components

- Creates `${var.prefix}-pipeline-alerts` Pub/Sub topic and optional Cloud Monitoring alert policies.
- Creates `pipeline_runs` BigQuery table inside `ops_telemetry` for run tracking.
- Splits runtime IAM (`workflow-sa`, repo-scoped `roles/dataform.editor`) from trigger IAM (`wf-trigger`, `roles/workflows.invoker`).
- Grants `roles/pubsub.publisher` on `compute_project_id` and `roles/storage.bucketViewer` to the Eventarc agent.
- Deploys `workflows/medallion_pipeline.workflows.yaml` using Dataform GA `v1` and bounded Dataplex scan polls.
