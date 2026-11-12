locals {
  effective_gold_project_id    = var.gold_project_id != "" ? var.gold_project_id : var.compute_project_id
  effective_landing_project_id = var.landing_bucket_project_id != "" ? var.landing_bucket_project_id : var.compute_project_id
  workflow_sa_account_id       = trimsuffix(substr(lower("${replace(var.prefix, "_", "-")}-workflow-sa"), 0, 30), "-")
  alert_topic_name             = trimsuffix(substr(lower(replace("${var.prefix}-pipeline-alerts", "_", "-")), 0, 64), "-")
  workflow_name                = trimsuffix(substr(lower(replace("${var.prefix}-medallion-pipeline", "_", "-")), 0, 64), "-")

  dataform_repo_path = "projects/${var.compute_project_id}/locations/${var.region}/repositories/${var.dataform_repository_name}"
  dataform_release_config = (
    var.dataform_release_config_name != ""
    ? "${local.dataform_repo_path}/releaseConfigs/${var.dataform_release_config_name}"
    : ""
  )

  batch_job_short_name = var.batch_job_name != "" ? element(split("/", var.batch_job_name), length(split("/", var.batch_job_name)) - 1) : ""
  batch_job_full_path = (
    var.batch_job_name == ""
    ? ""
    : (startswith(var.batch_job_name, "projects/")
      ? var.batch_job_name
      : "projects/${var.compute_project_id}/locations/${var.region}/jobs/${var.batch_job_name}"
    )
  )

  effective_workflow_source = (
    var.workflow_source_contents != ""
    ? var.workflow_source_contents
    : file("${path.module}/../../../workflows/medallion_pipeline.workflows.yaml")
  )
}

resource "terraform_data" "validate_eventarc_bucket" {
  lifecycle {
    precondition {
      condition     = !var.enable_gcs_eventarc_trigger || var.landing_bucket_name != ""
      error_message = "landing_bucket_name is required when enable_gcs_eventarc_trigger is true."
    }
  }
}

resource "google_pubsub_topic" "alerts" {
  project      = var.compute_project_id
  name         = local.alert_topic_name
  kms_key_name = var.kms_key_id != "" ? var.kms_key_id : null
  labels       = var.labels

  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
}

resource "google_bigquery_table" "pipeline_runs" {
  project             = var.compute_project_id
  dataset_id          = var.ops_telemetry_dataset_id
  table_id            = "pipeline_runs"
  description         = "Execution telemetry logged by Cloud Workflows pipeline runs."
  deletion_protection = !var.delete_contents_on_destroy
  labels              = var.labels

  time_partitioning {
    type  = "DAY"
    field = "recorded_at"
  }

  schema = jsonencode([
    { name = "execution_id", type = "STRING", mode = "REQUIRED", description = "Cloud Workflows execution ID." },
    { name = "status", type = "STRING", mode = "REQUIRED", description = "Final run status (SUCCEEDED or FAILED)." },
    { name = "compilation_name", type = "STRING", mode = "NULLABLE", description = "Dataform compilation result name." },
    { name = "invocation_name", type = "STRING", mode = "NULLABLE", description = "Dataform workflow invocation name." },
    { name = "recorded_at", type = "TIMESTAMP", mode = "REQUIRED", description = "UTC timestamp recorded in BigQuery." },
  ])

  dynamic "encryption_configuration" {
    for_each = var.kms_key_id != "" ? [var.kms_key_id] : []
    content {
      kms_key_name = encryption_configuration.value
    }
  }
}

resource "google_service_account" "workflow" {
  project      = var.compute_project_id
  account_id   = local.workflow_sa_account_id
  display_name = "${var.prefix} Pipeline Workflow"
  description  = "Least-privilege service account for Cloud Workflows pipeline execution."
}

resource "google_project_iam_member" "dataform_editor" {
  project = var.compute_project_id
  role    = "roles/dataform.editor"
  member  = google_service_account.workflow.member
}

resource "google_service_account_iam_member" "dataform_sa_user" {
  count = var.dataform_service_account_email != "" ? 1 : 0

  service_account_id = "projects/${var.compute_project_id}/serviceAccounts/${var.dataform_service_account_email}"
  role               = "roles/iam.serviceAccountUser"
  member             = google_service_account.workflow.member
}

resource "google_project_iam_member" "dataplex_scan_editor" {
  count = var.dataplex_scan_name != "" ? 1 : 0

  project = local.effective_gold_project_id
  role    = "roles/dataplex.dataScanEditor"
  member  = google_service_account.workflow.member
}

resource "google_cloud_run_v2_job_iam_member" "batch_job_developer" {
  count = var.batch_job_name != "" ? 1 : 0

  project  = var.compute_project_id
  location = var.region
  name     = local.batch_job_short_name
  role     = "roles/run.developer"
  member   = google_service_account.workflow.member
}

resource "google_bigquery_dataset_iam_member" "ops_telemetry_editor" {
  project    = var.compute_project_id
  dataset_id = var.ops_telemetry_dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = google_service_account.workflow.member
}

resource "google_project_iam_member" "telemetry_job_user" {
  project = var.compute_project_id
  role    = "roles/bigquery.jobUser"
  member  = google_service_account.workflow.member
}

resource "google_pubsub_topic_iam_member" "alert_publisher" {
  project = var.compute_project_id
  topic   = google_pubsub_topic.alerts.name
  role    = "roles/pubsub.publisher"
  member  = google_service_account.workflow.member
}

resource "google_project_iam_member" "log_writer" {
  project = var.compute_project_id
  role    = "roles/logging.logWriter"
  member  = google_service_account.workflow.member
}

resource "google_project_iam_member" "workflows_invoker" {
  count = var.enable_schedule || var.enable_gcs_eventarc_trigger ? 1 : 0

  project = var.compute_project_id
  role    = "roles/workflows.invoker"
  member  = google_service_account.workflow.member
}

resource "google_project_iam_member" "eventarc_receiver" {
  count = var.enable_gcs_eventarc_trigger ? 1 : 0

  project = var.compute_project_id
  role    = "roles/eventarc.eventReceiver"
  member  = google_service_account.workflow.member
}

data "google_storage_project_service_account" "landing" {
  count = var.enable_gcs_eventarc_trigger ? 1 : 0

  project = local.effective_landing_project_id
}

resource "google_project_iam_member" "gcs_eventarc_pubsub_publisher" {
  count = var.enable_gcs_eventarc_trigger ? 1 : 0

  project = local.effective_landing_project_id
  role    = "roles/pubsub.publisher"
  member  = data.google_storage_project_service_account.landing[0].member
}

resource "google_workflows_workflow" "this" {
  project             = var.compute_project_id
  region              = var.region
  name                = local.workflow_name
  description         = "Parameter-driven Dataform, Cloud Run batch, Dataplex, and telemetry pipeline."
  service_account     = google_service_account.workflow.id
  crypto_key_name     = var.kms_key_id != "" ? var.kms_key_id : null
  deletion_protection = !var.delete_contents_on_destroy
  call_log_level      = "LOG_ERRORS_ONLY"
  source_contents     = local.effective_workflow_source
  labels              = var.labels

  user_env_vars = {
    COMPUTE_PROJECT_ID        = var.compute_project_id
    REGION                    = var.region
    DATAFORM_REPO_PATH        = local.dataform_repo_path
    DATAFORM_RELEASE_CONFIG   = local.dataform_release_config
    BATCH_JOB_NAME            = local.batch_job_full_path
    DEFAULT_RUN_BATCH_JOB     = var.default_run_batch_job ? "true" : "false"
    DATAPLEX_SCAN_NAME        = var.dataplex_scan_name
    DEFAULT_RUN_DATAPLEX_SCAN = var.default_run_dataplex_scan ? "true" : "false"
    OPS_TELEMETRY_DATASET     = var.ops_telemetry_dataset_id
    ALERT_PUBSUB_TOPIC        = google_pubsub_topic.alerts.id
  }

  depends_on = [
    google_bigquery_table.pipeline_runs,
    google_project_iam_member.dataform_editor,
    google_service_account_iam_member.dataform_sa_user,
    google_project_iam_member.dataplex_scan_editor,
    google_cloud_run_v2_job_iam_member.batch_job_developer,
    google_bigquery_dataset_iam_member.ops_telemetry_editor,
    google_project_iam_member.telemetry_job_user,
    google_pubsub_topic_iam_member.alert_publisher,
    google_project_iam_member.log_writer,
  ]
}

resource "google_cloud_scheduler_job" "this" {
  count = var.enable_schedule ? 1 : 0

  project     = var.compute_project_id
  region      = var.region
  name        = "${local.workflow_name}-schedule"
  description = "Scheduled trigger for the Medallion Cloud Workflow."
  schedule    = var.schedule_cron
  time_zone   = var.schedule_time_zone

  http_target {
    http_method = "POST"
    uri         = "https://workflowexecutions.googleapis.com/v1/${google_workflows_workflow.this.id}/executions"
    body        = base64encode(jsonencode({ argument = jsonencode(var.schedule_payload) }))
    headers = {
      "Content-Type" = "application/json"
    }

    oauth_token {
      service_account_email = google_service_account.workflow.email
    }
  }

  depends_on = [google_project_iam_member.workflows_invoker]
}

resource "google_eventarc_trigger" "gcs" {
  count = var.enable_gcs_eventarc_trigger ? 1 : 0

  project         = var.compute_project_id
  location        = var.region
  name            = "${local.workflow_name}-gcs-trigger"
  service_account = google_service_account.workflow.email
  labels          = var.labels

  destination {
    workflow = google_workflows_workflow.this.id
  }

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.storage.object.v1.finalized"
  }

  matching_criteria {
    attribute = "bucket"
    value     = var.landing_bucket_name
  }

  depends_on = [
    terraform_data.validate_eventarc_bucket,
    google_project_iam_member.workflows_invoker,
    google_project_iam_member.eventarc_receiver,
    google_project_iam_member.gcs_eventarc_pubsub_publisher,
  ]
}
