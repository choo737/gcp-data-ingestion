provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

data "google_project" "current" {
  project_id = var.project_id
}

locals {
  dataset_prefix               = replace(var.prefix, "-", "_")
  raw_kms_id                   = var.kms_key_id != null ? trimspace(var.kms_key_id) : ""
  raw_kms_name                 = var.kms_key_name != null ? trimspace(var.kms_key_name) : ""
  effective_kms_key_id         = local.raw_kms_id != "" ? local.raw_kms_id : local.raw_kms_name
  use_cmek                     = local.effective_kms_key_id != ""
  raw_bronze_ds                = var.bronze_dataset_id != null ? trimspace(var.bronze_dataset_id) : ""
  effective_bronze_ds          = local.raw_bronze_ds != "" ? local.raw_bronze_ds : lookup(var.dataset_ids, "bronze_raw", "${local.dataset_prefix}_bronze_raw")
  raw_silver_ds                = var.silver_dataset_id != null ? trimspace(var.silver_dataset_id) : ""
  effective_silver_ds          = local.raw_silver_ds != "" ? local.raw_silver_ds : lookup(var.dataset_ids, "silver_curated", "")
  raw_gold_ds                  = var.gold_dataset_id != null ? trimspace(var.gold_dataset_id) : ""
  effective_gold_ds            = local.raw_gold_ds != "" ? local.raw_gold_ds : lookup(var.dataset_ids, "gold_mart", "")
  raw_assertions_ds            = var.assertions_dataset_id != null ? trimspace(var.assertions_dataset_id) : ""
  effective_assertions_ds      = local.raw_assertions_ds != "" ? local.raw_assertions_ds : lookup(var.dataset_ids, "dataform_assertions", "")
  raw_ops_ds                   = var.ops_telemetry_dataset_id != null ? trimspace(var.ops_telemetry_dataset_id) : ""
  effective_ops_ds             = local.raw_ops_ds != "" ? local.raw_ops_ds : "${local.dataset_prefix}_ops_telemetry"
  raw_df_repo                  = var.dataform_repository_name != null ? trimspace(var.dataform_repository_name) : ""
  effective_df_repo            = local.raw_df_repo != "" ? local.raw_df_repo : "${var.prefix}-medallion"
  raw_df_release_name          = var.dataform_release_config_name != null ? trimspace(var.dataform_release_config_name) : ""
  raw_df_release_id            = var.dataform_release_config_id != null ? trimspace(var.dataform_release_config_id) : ""
  effective_df_release_config  = local.raw_df_release_id != "" ? local.raw_df_release_id : local.raw_df_release_name
  raw_df_sa                    = var.dataform_service_account_email != null ? trimspace(var.dataform_service_account_email) : ""
  raw_df_sa_alias              = var.dataform_sa_email != null ? trimspace(var.dataform_sa_email) : ""
  effective_df_sa              = local.raw_df_sa != "" ? local.raw_df_sa : local.raw_df_sa_alias
  raw_profile_scan             = var.dataplex_profile_scan_id != null ? trimspace(var.dataplex_profile_scan_id) : ""
  raw_quality_scan             = var.dataplex_quality_scan_id != null ? trimspace(var.dataplex_quality_scan_id) : ""
  effective_dataplex_key       = length(var.dataplex_scan_names) > 0 ? (contains(keys(var.dataplex_scan_names), "masked_customers_canary") ? "masked_customers_canary" : sort(keys(var.dataplex_scan_names))[0]) : ""
  map_quality_keys             = [for k in sort(keys(var.dataplex_scan_names)) : k if length(regexall("quality", lower(k))) > 0]
  effective_dataplex           = local.raw_profile_scan != "" ? local.raw_profile_scan : (local.effective_dataplex_key != "" ? var.dataplex_scan_names[local.effective_dataplex_key] : "")
  effective_dataplex_quality   = local.raw_quality_scan != "" ? local.raw_quality_scan : (length(local.map_quality_keys) > 0 ? var.dataplex_scan_names[local.map_quality_keys[0]] : "")
  effective_pii_restricted_tag = var.pii_restricted_policy_tag_id != null ? trimspace(var.pii_restricted_policy_tag_id) : ""
  effective_pii_masked_tag     = var.pii_masked_policy_tag_id != null ? trimspace(var.pii_masked_policy_tag_id) : ""
  effective_batch_image        = var.batch_container_image != null ? trimspace(var.batch_container_image) : ""
  effective_vpc_id             = var.vpc_id != null ? trimspace(var.vpc_id) : ""
  effective_subnet_id          = var.subnet_id != null ? trimspace(var.subnet_id) : ""
  landing_bucket_name          = "${var.project_id}-${var.prefix}-landing"

  required_apis = toset(concat(
    [
      "pubsub.googleapis.com",
      "bigquery.googleapis.com",
      "storage.googleapis.com",
      "workflows.googleapis.com",
      "workflowexecutions.googleapis.com",
      "iam.googleapis.com",
    ],
    var.enable_batch_job ? ["run.googleapis.com"] : [],
    var.enable_datastream_cdc ? ["datastream.googleapis.com"] : [],
    var.enable_schedule ? ["cloudscheduler.googleapis.com"] : [],
    var.enable_gcs_eventarc_trigger ? ["eventarc.googleapis.com"] : [],
    length(var.notification_channel_ids) > 0 ? ["monitoring.googleapis.com"] : [],
  ))
}

resource "terraform_data" "validate_sandbox_inputs" {
  lifecycle {
    precondition {
      condition     = !var.enable_batch_job || local.effective_batch_image != ""
      error_message = "batch_container_image is required when enable_batch_job is true."
    }
    precondition {
      condition     = !var.enable_datastream_cdc || (var.datastream_db_host != "" && var.datastream_db_username != "" && var.datastream_db_password_secret_version != "")
      error_message = "datastream_db_host, datastream_db_username, and datastream_db_password_secret_version are required when enable_datastream_cdc is true."
    }
  }
}

resource "google_project_service" "apis" {
  for_each = local.required_apis

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "time_sleep" "api_propagation" {
  create_duration = var.propagation_wait_seconds

  depends_on = [google_project_service.apis]
}

resource "google_project_service_identity" "pubsub_agent" {
  count    = var.enable_pubsub_stream ? 1 : 0
  provider = google-beta
  project  = var.project_id
  service  = "pubsub.googleapis.com"

  depends_on = [time_sleep.api_propagation]
}

resource "google_project_service_identity" "datastream_agent" {
  count    = var.enable_datastream_cdc ? 1 : 0
  provider = google-beta
  project  = var.project_id
  service  = "datastream.googleapis.com"

  depends_on = [time_sleep.api_propagation]
}

resource "google_project_service_identity" "workflows_agent" {
  count    = var.enable_pipeline_workflow ? 1 : 0
  provider = google-beta
  project  = var.project_id
  service  = "workflows.googleapis.com"

  depends_on = [time_sleep.api_propagation]
}

resource "google_project_service_identity" "run_agent" {
  count    = var.enable_batch_job ? 1 : 0
  provider = google-beta
  project  = var.project_id
  service  = "run.googleapis.com"

  depends_on = [time_sleep.api_propagation]
}

resource "time_sleep" "service_identity_propagation" {
  create_duration = var.propagation_wait_seconds

  depends_on = [
    google_project_service_identity.pubsub_agent,
    google_project_service_identity.datastream_agent,
    google_project_service_identity.workflows_agent,
    google_project_service_identity.run_agent,
  ]
}

resource "google_kms_crypto_key_iam_member" "pubsub_cmek" {
  count = local.use_cmek && var.enable_pubsub_stream ? 1 : 0

  crypto_key_id = local.effective_kms_key_id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = google_project_service_identity.pubsub_agent[0].member

  depends_on = [time_sleep.service_identity_propagation]
}

resource "google_kms_crypto_key_iam_member" "datastream_cmek" {
  count = local.use_cmek && var.enable_datastream_cdc ? 1 : 0

  crypto_key_id = local.effective_kms_key_id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = google_project_service_identity.datastream_agent[0].member

  depends_on = [time_sleep.service_identity_propagation]
}

resource "google_kms_crypto_key_iam_member" "workflows_cmek" {
  count = local.use_cmek && var.enable_pipeline_workflow ? 1 : 0

  crypto_key_id = local.effective_kms_key_id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = google_project_service_identity.workflows_agent[0].member

  depends_on = [time_sleep.service_identity_propagation]
}

resource "google_kms_crypto_key_iam_member" "run_cmek" {
  count = local.use_cmek && var.enable_batch_job ? 1 : 0

  crypto_key_id = local.effective_kms_key_id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = google_project_service_identity.run_agent[0].member

  depends_on = [time_sleep.service_identity_propagation]
}

resource "time_sleep" "cmek_propagation" {
  count = local.use_cmek ? 1 : 0

  create_duration = var.propagation_wait_seconds

  depends_on = [
    google_kms_crypto_key_iam_member.pubsub_cmek,
    google_kms_crypto_key_iam_member.datastream_cmek,
    google_kms_crypto_key_iam_member.workflows_cmek,
    google_kms_crypto_key_iam_member.run_cmek,
  ]
}

resource "google_storage_bucket" "landing" {
  project                     = var.project_id
  name                        = local.landing_bucket_name
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = var.delete_contents_on_destroy
  labels                      = var.labels

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age            = 30
      matches_prefix = ["incoming/"]
    }
    action {
      type = "Delete"
    }
  }

  dynamic "encryption" {
    for_each = local.use_cmek ? [local.effective_kms_key_id] : []
    content {
      default_kms_key_name = encryption.value
    }
  }

  depends_on = [
    time_sleep.api_propagation,
    time_sleep.cmek_propagation,
  ]
}

resource "google_bigquery_dataset" "bronze" {
  count = var.create_bronze_dataset ? 1 : 0

  project                    = var.project_id
  dataset_id                 = local.effective_bronze_ds
  friendly_name              = "${var.prefix} Bronze Raw"
  description                = "Sandbox Bronze landing dataset created when standalone mode is enabled."
  location                   = var.region
  delete_contents_on_destroy = var.delete_contents_on_destroy
  labels                     = var.labels

  dynamic "default_encryption_configuration" {
    for_each = local.use_cmek ? [local.effective_kms_key_id] : []
    content {
      kms_key_name = default_encryption_configuration.value
    }
  }

  depends_on = [
    time_sleep.api_propagation,
    time_sleep.cmek_propagation,
  ]
}

resource "google_bigquery_dataset" "ops_telemetry" {
  count = var.create_ops_telemetry_dataset && local.raw_ops_ds == "" ? 1 : 0

  project                    = var.project_id
  dataset_id                 = local.effective_ops_ds
  friendly_name              = "${var.prefix} Ops Telemetry"
  description                = "Operational dataset storing Cloud Workflows pipeline_runs telemetry."
  location                   = var.region
  delete_contents_on_destroy = var.delete_contents_on_destroy
  labels                     = var.labels

  dynamic "default_encryption_configuration" {
    for_each = local.use_cmek ? [local.effective_kms_key_id] : []
    content {
      kms_key_name = default_encryption_configuration.value
    }
  }

  depends_on = [
    time_sleep.api_propagation,
    time_sleep.cmek_propagation,
  ]
}

module "pubsub_bigquery" {
  count  = var.enable_pubsub_stream ? 1 : 0
  source = "../../modules/ingestion/pubsub-bigquery"

  project_id                   = var.project_id
  region                       = var.region
  prefix                       = var.prefix
  stream_name                  = "pos-orders"
  bronze_project_id            = var.project_id
  bronze_dataset_id            = local.effective_bronze_ds
  pubsub_project_number        = data.google_project.current.number
  target_table_id              = var.pubsub_target_table_id
  schema_type                  = var.pubsub_schema_type
  kms_key_id                   = local.effective_kms_key_id
  pii_restricted_policy_tag_id = local.effective_pii_restricted_tag
  pii_masked_policy_tag_id     = local.effective_pii_masked_tag
  delete_contents_on_destroy   = var.delete_contents_on_destroy
  labels                       = var.labels

  depends_on = [
    time_sleep.service_identity_propagation,
    time_sleep.cmek_propagation,
    google_bigquery_dataset.bronze,
  ]
}

module "batch_elt_job" {
  count  = var.enable_batch_job ? 1 : 0
  source = "../../modules/ingestion/batch-elt-job"

  compute_project_id           = var.project_id
  bronze_project_id            = var.project_id
  bronze_dataset_id            = local.effective_bronze_ds
  landing_bucket_name          = google_storage_bucket.landing.name
  region                       = var.region
  prefix                       = var.prefix
  container_image              = local.effective_batch_image
  source_prefix                = var.batch_source_prefix
  target_table                 = var.batch_target_table
  source_format                = var.batch_source_format
  kms_key_id                   = local.effective_kms_key_id
  pii_restricted_policy_tag_id = local.effective_pii_restricted_tag
  pii_masked_policy_tag_id     = local.effective_pii_masked_tag
  vpc_id                       = local.effective_vpc_id
  subnet_id                    = local.effective_subnet_id
  vpc_egress                   = var.batch_vpc_egress
  delete_contents_on_destroy   = var.delete_contents_on_destroy
  labels                       = var.labels

  depends_on = [
    terraform_data.validate_sandbox_inputs,
    time_sleep.service_identity_propagation,
    time_sleep.cmek_propagation,
    google_bigquery_dataset.bronze,
  ]
}

module "datastream_cdc" {
  count  = var.enable_datastream_cdc ? 1 : 0
  source = "../../modules/ingestion/datastream-cdc"

  project_id                 = var.project_id
  compute_project_id         = var.project_id
  region                     = var.region
  prefix                     = var.prefix
  stream_name                = "pos-cdc"
  source_engine              = var.datastream_source_engine
  db_host                    = var.datastream_db_host
  db_port                    = var.datastream_db_port
  db_username                = var.datastream_db_username
  db_database                = var.datastream_db_database
  db_password_secret_version = var.datastream_db_password_secret_version
  bronze_project_id          = var.project_id
  bronze_dataset_id          = local.effective_bronze_ds
  cdc_mode                   = var.datastream_cdc_mode
  kms_key_name               = local.effective_kms_key_id
  create_without_validation  = var.datastream_create_without_validation
  labels                     = var.labels

  depends_on = [
    terraform_data.validate_sandbox_inputs,
    time_sleep.service_identity_propagation,
    time_sleep.cmek_propagation,
    google_bigquery_dataset.bronze,
  ]
}

module "pipeline_workflows" {
  count  = var.enable_pipeline_workflow ? 1 : 0
  source = "../../modules/ingestion/pipeline-workflows"

  compute_project_id             = var.project_id
  bronze_project_id              = var.project_id
  bronze_dataset_id              = local.effective_bronze_ds
  silver_project_id              = var.project_id
  silver_dataset_id              = local.effective_silver_ds
  gold_project_id                = var.project_id
  gold_dataset_id                = local.effective_gold_ds
  assertions_dataset_id          = local.effective_assertions_ds
  region                         = var.region
  prefix                         = var.prefix
  ops_telemetry_dataset_id       = local.effective_ops_ds
  dataform_repository_name       = local.effective_df_repo
  dataform_release_config_name   = local.effective_df_release_config
  dataform_git_commitish         = var.dataform_git_commitish
  dataform_service_account_email = local.effective_df_sa
  batch_job_name                 = var.enable_batch_job ? module.batch_elt_job[0].job_resource_path : ""
  batch_source_prefix            = var.batch_source_prefix
  default_run_batch_job          = var.enable_batch_job
  dataplex_scan_name             = local.effective_dataplex
  dataplex_quality_scan_name     = local.effective_dataplex_quality
  default_run_dataplex_scan      = local.effective_dataplex != "" || local.effective_dataplex_quality != ""
  include_stream_orders          = var.enable_pubsub_stream
  include_batch_orders           = var.enable_batch_job
  pii_restricted_policy_tag_id   = local.effective_pii_restricted_tag
  pii_masked_policy_tag_id       = local.effective_pii_masked_tag
  enable_schedule                = var.enable_schedule
  schedule_cron                  = var.schedule_cron
  enable_gcs_eventarc_trigger    = var.enable_gcs_eventarc_trigger
  landing_bucket_name            = google_storage_bucket.landing.name
  landing_bucket_project_id      = var.project_id
  kms_key_id                     = local.effective_kms_key_id
  notification_channel_ids       = var.notification_channel_ids
  delete_contents_on_destroy     = var.delete_contents_on_destroy
  labels                         = var.labels

  depends_on = [
    time_sleep.service_identity_propagation,
    time_sleep.cmek_propagation,
    google_bigquery_dataset.ops_telemetry,
  ]
}
