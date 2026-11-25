locals {
  trimmed_bronze_project      = var.bronze_project_id != null ? trimspace(var.bronze_project_id) : ""
  trimmed_bronze_dataset      = var.bronze_dataset_id != null ? trimspace(var.bronze_dataset_id) : ""
  trimmed_silver_project      = var.silver_project_id != null ? trimspace(var.silver_project_id) : ""
  trimmed_silver_dataset      = var.silver_dataset_id != null ? trimspace(var.silver_dataset_id) : ""
  trimmed_gold_project        = var.gold_project_id != null ? trimspace(var.gold_project_id) : ""
  trimmed_gold_dataset        = var.gold_dataset_id != null ? trimspace(var.gold_dataset_id) : ""
  trimmed_gold_retail_project = var.gold_retail_project_id != null ? trimspace(var.gold_retail_project_id) : ""
  trimmed_gold_retail_dataset = var.gold_retail_dataset_id != null ? trimspace(var.gold_retail_dataset_id) : ""
  trimmed_ml_audit_project    = var.ml_audit_project_id != null ? trimspace(var.ml_audit_project_id) : ""
  trimmed_ml_audit_dataset    = var.ml_audit_dataset_id != null ? trimspace(var.ml_audit_dataset_id) : ""
  trimmed_assertions_dataset  = var.assertions_dataset_id != null ? trimspace(var.assertions_dataset_id) : ""
  trimmed_landing_project     = var.landing_bucket_project_id != null ? trimspace(var.landing_bucket_project_id) : ""
  trimmed_dataform_repo       = var.dataform_repository_name != null ? trimspace(var.dataform_repository_name) : ""
  trimmed_release_cfg         = var.dataform_release_config_name != null ? trimspace(var.dataform_release_config_name) : ""
  trimmed_git_commitish       = var.dataform_git_commitish != null ? trimspace(var.dataform_git_commitish) : "main"
  trimmed_dataform_sa         = var.dataform_service_account_email != null ? trimspace(var.dataform_service_account_email) : ""
  trimmed_batch_job           = var.batch_job_name != null ? trimspace(var.batch_job_name) : ""
  raw_quarantine_prefix       = var.quarantine_prefix != null ? trimprefix(trimspace(var.quarantine_prefix), "/") : ""
  effective_quarantine_prefix = local.raw_quarantine_prefix != "" ? (endswith(local.raw_quarantine_prefix, "/") ? local.raw_quarantine_prefix : "${local.raw_quarantine_prefix}/") : "quarantine/"
  trimmed_dataplex_scan       = var.dataplex_scan_name != null ? trimspace(var.dataplex_scan_name) : ""
  trimmed_dataplex_quality    = var.dataplex_quality_scan_name != null ? trimspace(var.dataplex_quality_scan_name) : ""
  trimmed_landing_bucket      = var.landing_bucket_name != null ? trimspace(var.landing_bucket_name) : ""
  trimmed_kms_key_id          = var.kms_key_id != null ? trimspace(var.kms_key_id) : ""
  trimmed_pii_restricted_tag  = var.pii_restricted_policy_tag_id != null ? trimspace(var.pii_restricted_policy_tag_id) : ""
  trimmed_pii_masked_tag      = var.pii_masked_policy_tag_id != null ? trimspace(var.pii_masked_policy_tag_id) : ""
  trimmed_workflow_override   = var.workflow_source_contents != null ? trimspace(var.workflow_source_contents) : ""
  effective_bronze_project_id = local.trimmed_bronze_project != "" ? local.trimmed_bronze_project : var.compute_project_id
  effective_silver_project_id = local.trimmed_silver_project != "" ? local.trimmed_silver_project : local.effective_bronze_project_id
  effective_gold_project_id   = local.trimmed_gold_project != "" ? local.trimmed_gold_project : var.compute_project_id
  dataplex_profile_project = local.trimmed_dataplex_scan == "" ? "" : (
    can(regex("^projects/([^/]+)/", local.trimmed_dataplex_scan))
    ? regex("^projects/([^/]+)/", local.trimmed_dataplex_scan)[0]
    : local.effective_gold_project_id
  )
  dataplex_quality_project = local.trimmed_dataplex_quality == "" ? "" : (
    can(regex("^projects/([^/]+)/", local.trimmed_dataplex_quality))
    ? regex("^projects/([^/]+)/", local.trimmed_dataplex_quality)[0]
    : local.effective_gold_project_id
  )
  dataplex_scan_projects = toset(compact([
    local.dataplex_profile_project,
    local.dataplex_quality_project,
  ]))
  effective_landing_project_id = local.trimmed_landing_project != "" ? local.trimmed_landing_project : var.compute_project_id
  is_cross_project_gcs         = var.enable_gcs_eventarc_trigger && local.effective_landing_project_id != var.compute_project_id
  same_project_channels        = [for ch in var.notification_channel_ids : trimspace(ch) if startswith(trimspace(ch), "projects/${var.compute_project_id}/")]
  alert_email_map              = { for idx, email in var.alert_email_addresses : tostring(idx) => trimspace(email) if trimspace(email) != "" }
  effective_notification_channels = distinct(concat(
    local.same_project_channels,
    [for ch in google_monitoring_notification_channel.email : ch.id],
  ))
  workflow_sa_account_id = trimsuffix(substr(lower("${replace(var.prefix, "_", "-")}-workflow-sa"), 0, 30), "-")
  trigger_sa_account_id  = trimsuffix(substr(lower("${replace(var.prefix, "_", "-")}-wf-trigger"), 0, 30), "-")
  alert_topic_name       = trimsuffix(substr(lower(replace("${var.prefix}-pipeline-alerts", "_", "-")), 0, 64), "-")
  workflow_name          = trimsuffix(substr(lower(replace("${var.prefix}-medallion-pipeline", "_", "-")), 0, 64), "-")

  dataform_repo_short_name = (
    local.trimmed_dataform_repo == ""
    ? ""
    : (startswith(local.trimmed_dataform_repo, "projects/")
      ? element(split("/", local.trimmed_dataform_repo), length(split("/", local.trimmed_dataform_repo)) - 1)
      : local.trimmed_dataform_repo
    )
  )
  dataform_repo_path = (
    local.trimmed_dataform_repo == ""
    ? ""
    : (startswith(local.trimmed_dataform_repo, "projects/")
      ? local.trimmed_dataform_repo
      : "projects/${var.compute_project_id}/locations/${var.region}/repositories/${local.trimmed_dataform_repo}"
    )
  )
  dataform_release_config = (
    local.trimmed_release_cfg == ""
    ? ""
    : (startswith(local.trimmed_release_cfg, "projects/")
      ? local.trimmed_release_cfg
      : "${local.dataform_repo_path}/releaseConfigs/${local.trimmed_release_cfg}"
    )
  )

  batch_job_short_name = local.trimmed_batch_job != "" ? element(split("/", local.trimmed_batch_job), length(split("/", local.trimmed_batch_job)) - 1) : ""
  batch_job_full_path = (
    local.trimmed_batch_job == ""
    ? ""
    : (startswith(local.trimmed_batch_job, "projects/")
      ? local.trimmed_batch_job
      : "projects/${var.compute_project_id}/locations/${var.region}/jobs/${local.trimmed_batch_job}"
    )
  )
  trimmed_additional_batch_jobs = [
    for job in var.additional_batch_job_names : trimspace(job)
    if job != null && trimspace(job) != ""
  ]
  additional_batch_job_full_paths = [
    for job in local.trimmed_additional_batch_jobs : (
      startswith(job, "projects/")
      ? job
      : "projects/${var.compute_project_id}/locations/${var.region}/jobs/${job}"
    )
  ]
  additional_batch_job_iam_map = {
    for idx, job in local.trimmed_additional_batch_jobs :
    tostring(idx) => element(split("/", job), length(split("/", job)) - 1)
  }

  effective_workflow_source = (
    local.trimmed_workflow_override != ""
    ? var.workflow_source_contents
    : file("${path.module}/../../../workflows/medallion_pipeline.workflows.yaml")
  )
}

resource "terraform_data" "validate_eventarc_bucket" {
  lifecycle {
    precondition {
      condition     = !var.enable_gcs_eventarc_trigger || local.trimmed_landing_bucket != ""
      error_message = "landing_bucket_name is required when enable_gcs_eventarc_trigger is true."
    }
  }
}

resource "google_pubsub_topic" "alerts" {
  project      = var.compute_project_id
  name         = local.alert_topic_name
  kms_key_name = local.trimmed_kms_key_id != "" ? local.trimmed_kms_key_id : null
  labels       = var.labels

  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
}

resource "google_bigquery_table" "pipeline_runs" {
  project             = var.compute_project_id
  dataset_id          = var.ops_telemetry_dataset_id
  table_id            = "pipeline_runs"
  description         = "Execution telemetry logged by Workflows pipeline runs."
  deletion_protection = !var.delete_contents_on_destroy
  labels              = var.labels

  time_partitioning {
    type  = "DAY"
    field = "recorded_at"
  }

  schema = jsonencode([
    { name = "execution_id", type = "STRING", mode = "REQUIRED", description = "Workflows execution ID." },
    { name = "status", type = "STRING", mode = "REQUIRED", description = "Final run status (SUCCEEDED or FAILED)." },
    { name = "compilation_name", type = "STRING", mode = "NULLABLE", description = "Dataform compilation result name." },
    { name = "invocation_name", type = "STRING", mode = "NULLABLE", description = "Dataform workflow invocation name." },
    { name = "recorded_at", type = "TIMESTAMP", mode = "REQUIRED", description = "UTC timestamp recorded in BigQuery." },
  ])

  dynamic "encryption_configuration" {
    for_each = local.trimmed_kms_key_id != "" ? [local.trimmed_kms_key_id] : []
    content {
      kms_key_name = encryption_configuration.value
    }
  }
}

resource "google_service_account" "workflow" {
  project      = var.compute_project_id
  account_id   = local.workflow_sa_account_id
  display_name = "${var.prefix} Pipeline Workflow"
  description  = "Least-privilege runtime service account for Workflows pipeline execution."
}

resource "google_service_account" "trigger_invoker" {
  count = var.enable_schedule || var.enable_gcs_eventarc_trigger ? 1 : 0

  project      = var.compute_project_id
  account_id   = local.trigger_sa_account_id
  display_name = "${var.prefix} Workflow Trigger"
  description  = "Minimal invoker service account for Cloud Scheduler and Eventarc triggers."
}

resource "google_dataform_repository_iam_member" "dataform_editor" {
  count = local.dataform_repo_short_name != "" ? 1 : 0

  project    = var.compute_project_id
  region     = var.region
  repository = local.dataform_repo_short_name
  role       = "roles/dataform.editor"
  member     = google_service_account.workflow.member
}

resource "google_service_account_iam_member" "dataform_sa_user" {
  count = local.trimmed_dataform_sa != "" ? 1 : 0

  service_account_id = "projects/${var.compute_project_id}/serviceAccounts/${local.trimmed_dataform_sa}"
  role               = "roles/iam.serviceAccountUser"
  member             = google_service_account.workflow.member
}

resource "google_project_iam_member" "dataplex_scan_editor" {
  for_each = local.dataplex_scan_projects

  project = each.value
  role    = "roles/dataplex.dataScanEditor"
  member  = google_service_account.workflow.member
}

resource "google_cloud_run_v2_job_iam_member" "batch_job_developer" {
  count = local.trimmed_batch_job != "" ? 1 : 0

  project  = var.compute_project_id
  location = var.region
  name     = local.batch_job_short_name
  role     = "roles/run.developer"
  member   = google_service_account.workflow.member
}

resource "google_cloud_run_v2_job_iam_member" "additional_batch_job_developer" {
  for_each = local.additional_batch_job_iam_map

  project  = var.compute_project_id
  location = var.region
  name     = each.value
  role     = "roles/run.developer"
  member   = google_service_account.workflow.member
}

resource "google_project_iam_member" "batch_operations_viewer" {
  count = (local.trimmed_batch_job != "" || length(local.trimmed_additional_batch_jobs) > 0) ? 1 : 0

  project = var.compute_project_id
  role    = "roles/run.viewer"
  member  = google_service_account.workflow.member
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

resource "google_project_iam_member" "trigger_workflows_invoker" {
  count = var.enable_schedule || var.enable_gcs_eventarc_trigger ? 1 : 0

  project = var.compute_project_id
  role    = "roles/workflows.invoker"
  member  = google_service_account.trigger_invoker[0].member
}

resource "google_project_iam_member" "trigger_eventarc_receiver" {
  count = var.enable_gcs_eventarc_trigger ? 1 : 0

  project = var.compute_project_id
  role    = "roles/eventarc.eventReceiver"
  member  = google_service_account.trigger_invoker[0].member
}

data "google_storage_project_service_account" "landing" {
  count = var.enable_gcs_eventarc_trigger ? 1 : 0

  project = local.effective_landing_project_id
}

resource "google_project_service_identity" "eventarc_agent" {
  count    = var.enable_gcs_eventarc_trigger ? 1 : 0
  provider = google-beta

  project = var.compute_project_id
  service = "eventarc.googleapis.com"
}

resource "google_storage_bucket_iam_member" "eventarc_bucket_viewer" {
  count = var.enable_gcs_eventarc_trigger && !local.is_cross_project_gcs ? 1 : 0

  bucket = local.trimmed_landing_bucket
  role   = "roles/storage.bucketViewer"
  member = google_project_service_identity.eventarc_agent[0].member
}

resource "google_project_iam_member" "gcs_eventarc_pubsub_publisher" {
  count = var.enable_gcs_eventarc_trigger && !local.is_cross_project_gcs ? 1 : 0

  project = var.compute_project_id
  role    = "roles/pubsub.publisher"
  member  = data.google_storage_project_service_account.landing[0].member
}

resource "time_sleep" "eventarc_iam_propagation" {
  count = var.enable_gcs_eventarc_trigger ? 1 : 0

  create_duration = var.propagation_wait_seconds

  depends_on = [
    google_project_service_identity.eventarc_agent,
    google_storage_bucket_iam_member.eventarc_bucket_viewer,
    google_project_iam_member.gcs_eventarc_pubsub_publisher,
    google_project_iam_member.trigger_workflows_invoker,
    google_project_iam_member.trigger_eventarc_receiver,
  ]
}

resource "google_pubsub_topic" "gcs_events" {
  count = local.is_cross_project_gcs ? 1 : 0

  project      = var.compute_project_id
  name         = "${local.workflow_name}-gcs-events"
  kms_key_name = local.trimmed_kms_key_id != "" ? local.trimmed_kms_key_id : null
  labels       = var.labels

  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
}

resource "google_pubsub_topic_iam_member" "gcs_events_publisher" {
  count = local.is_cross_project_gcs ? 1 : 0

  project = var.compute_project_id
  topic   = google_pubsub_topic.gcs_events[0].name
  role    = "roles/pubsub.publisher"
  member  = data.google_storage_project_service_account.landing[0].member
}

resource "google_storage_notification" "landing_objects" {
  count = local.is_cross_project_gcs ? 1 : 0

  bucket             = local.trimmed_landing_bucket
  payload_format     = "JSON_API_V1"
  topic              = google_pubsub_topic.gcs_events[0].id
  event_types        = ["OBJECT_FINALIZE"]
  object_name_prefix = var.batch_source_prefix != "" ? var.batch_source_prefix : null

  depends_on = [google_pubsub_topic_iam_member.gcs_events_publisher]
}

resource "google_workflows_workflow" "this" {
  project             = var.compute_project_id
  region              = var.region
  name                = local.workflow_name
  description         = "Parameter-driven Dataform, Cloud Run batch, Knowledge Catalog, and telemetry pipeline."
  service_account     = google_service_account.workflow.id
  crypto_key_name     = local.trimmed_kms_key_id != "" ? local.trimmed_kms_key_id : null
  deletion_protection = !var.delete_contents_on_destroy
  call_log_level      = "LOG_ERRORS_ONLY"
  source_contents     = local.effective_workflow_source
  labels              = var.labels

  user_env_vars = {
    COMPUTE_PROJECT_ID = var.compute_project_id
    REGION             = var.region
    MEDALLION_TARGETS_JSON = jsonencode({
      BRONZE_PROJECT_ID      = local.effective_bronze_project_id
      BRONZE_DATASET_ID      = local.trimmed_bronze_dataset
      SILVER_PROJECT_ID      = local.effective_silver_project_id
      SILVER_DATASET_ID      = local.trimmed_silver_dataset
      GOLD_PROJECT_ID        = local.effective_gold_project_id
      GOLD_DATASET_ID        = local.trimmed_gold_dataset
      GOLD_RETAIL_PROJECT_ID = local.trimmed_gold_retail_project
      GOLD_RETAIL_DATASET_ID = local.trimmed_gold_retail_dataset
      ML_AUDIT_PROJECT_ID    = local.trimmed_ml_audit_project
      ML_AUDIT_DATASET_ID    = local.trimmed_ml_audit_dataset
      ASSERTIONS_DATASET_ID  = local.trimmed_assertions_dataset
    })
    DATAFORM_COMPILATION_VARS_JSON = jsonencode({
      INCLUDE_STREAM_ORDERS     = var.include_stream_orders ? "true" : "false"
      INCLUDE_BATCH_ORDERS      = var.include_batch_orders ? "true" : "false"
      PII_POLICY_TAG            = local.trimmed_pii_masked_tag
      PII_RESTRICTED_POLICY_TAG = local.trimmed_pii_restricted_tag
      PII_MASKED_POLICY_TAG     = local.trimmed_pii_masked_tag
      ALLOW_UNTAGGED_PII        = (local.trimmed_pii_restricted_tag != "" || local.trimmed_pii_masked_tag != "") ? "false" : "true"
    })
    DATAFORM_REPO_PATH              = local.dataform_repo_path
    DATAFORM_RELEASE_CONFIG         = local.dataform_release_config
    DATAFORM_GIT_COMMITISH          = local.trimmed_git_commitish != "" ? local.trimmed_git_commitish : "main"
    BATCH_JOB_NAME                  = local.batch_job_full_path
    ADDITIONAL_BATCH_JOB_NAMES_JSON = jsonencode(local.additional_batch_job_full_paths)
    BATCH_SOURCE_PREFIX             = var.batch_source_prefix
    QUARANTINE_PREFIX               = local.effective_quarantine_prefix
    DEFAULT_RUN_BATCH_JOB           = var.default_run_batch_job ? "true" : "false"
    DATAPLEX_SCAN_ID                = local.trimmed_dataplex_scan
    DATAPLEX_QUALITY_SCAN_ID        = local.trimmed_dataplex_quality
    DEFAULT_RUN_DATAPLEX_SCAN       = var.default_run_dataplex_scan ? "true" : "false"
    OPS_TELEMETRY_DATASET           = var.ops_telemetry_dataset_id
    ALERT_PUBSUB_TOPIC              = google_pubsub_topic.alerts.id
  }

  lifecycle {
    precondition {
      condition     = (local.trimmed_pii_restricted_tag == "") == (local.trimmed_pii_masked_tag == "")
      error_message = "pii_restricted_policy_tag_id and pii_masked_policy_tag_id must both be set or both be empty so column-level PII security never leaves half of PII columns untagged."
    }
  }

  depends_on = [
    google_bigquery_table.pipeline_runs,
    google_dataform_repository_iam_member.dataform_editor,
    google_service_account_iam_member.dataform_sa_user,
    google_project_iam_member.dataplex_scan_editor,
    google_cloud_run_v2_job_iam_member.batch_job_developer,
    google_cloud_run_v2_job_iam_member.additional_batch_job_developer,
    google_project_iam_member.batch_operations_viewer,
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
  description = "Scheduled trigger for the Medallion Workflows pipeline."
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
      service_account_email = google_service_account.trigger_invoker[0].email
    }
  }

  depends_on = [google_project_iam_member.trigger_workflows_invoker]
}

resource "google_eventarc_trigger" "gcs" {
  count = var.enable_gcs_eventarc_trigger && !local.is_cross_project_gcs ? 1 : 0

  project         = var.compute_project_id
  location        = var.region
  name            = "${local.workflow_name}-gcs-trigger"
  service_account = google_service_account.trigger_invoker[0].email
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
    value     = local.trimmed_landing_bucket
  }

  depends_on = [
    terraform_data.validate_eventarc_bucket,
    google_project_iam_member.trigger_workflows_invoker,
    google_project_iam_member.trigger_eventarc_receiver,
    google_project_iam_member.gcs_eventarc_pubsub_publisher,
    google_storage_bucket_iam_member.eventarc_bucket_viewer,
    time_sleep.eventarc_iam_propagation,
  ]
}

resource "google_eventarc_trigger" "gcs_cross_project" {
  count = local.is_cross_project_gcs ? 1 : 0

  project         = var.compute_project_id
  location        = var.region
  name            = "${local.workflow_name}-gcs-trigger"
  service_account = google_service_account.trigger_invoker[0].email
  labels          = var.labels

  destination {
    workflow = google_workflows_workflow.this.id
  }

  transport {
    pubsub {
      topic = google_pubsub_topic.gcs_events[0].id
    }
  }

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.pubsub.topic.v1.messagePublished"
  }

  depends_on = [
    terraform_data.validate_eventarc_bucket,
    google_project_service_identity.eventarc_agent,
    google_project_iam_member.trigger_workflows_invoker,
    google_project_iam_member.trigger_eventarc_receiver,
    google_storage_notification.landing_objects,
    time_sleep.eventarc_iam_propagation,
  ]
}

resource "google_monitoring_notification_channel" "email" {
  for_each = local.alert_email_map

  project      = var.compute_project_id
  display_name = "${local.workflow_name} Alert Email ${each.key}"
  type         = "email"
  labels = {
    email_address = each.value
  }
}

resource "google_monitoring_alert_policy" "workflow_failure" {
  count = (length(local.same_project_channels) > 0 || length(local.alert_email_map) > 0) ? 1 : 0

  project               = var.compute_project_id
  display_name          = "${local.workflow_name} Execution Failure"
  combiner              = "OR"
  notification_channels = local.effective_notification_channels
  user_labels           = var.labels

  conditions {
    display_name = "Workflow execution failed"

    condition_threshold {
      filter          = "resource.type = \"workflows.googleapis.com/Workflow\" AND resource.labels.workflow_id = \"${google_workflows_workflow.this.name}\" AND metric.type = \"workflows.googleapis.com/finished_execution_count\" AND metric.labels.status != \"SUCCEEDED\""
      duration        = "0s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  documentation {
    content   = "Workflows pipeline ${google_workflows_workflow.this.name} recorded a non-SUCCEEDED execution."
    mime_type = "text/markdown"
  }
}
