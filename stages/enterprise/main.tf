provider "google" {
  region = var.region
}

provider "google-beta" {
  region = var.region
}

data "google_project" "etl" {
  project_id = var.etl_compute_project_id
}

locals {
  effective_kms_key_id   = trimspace(var.kms_key_id)
  use_cmek               = local.effective_kms_key_id != ""
  effective_vpc_id       = var.vpc_id != "" ? var.vpc_id : var.network_id
  effective_dataplex_key = length(var.dataplex_scan_names) > 0 ? (contains(keys(var.dataplex_scan_names), "masked_customers_canary") ? "masked_customers_canary" : sort(keys(var.dataplex_scan_names))[0]) : ""
  effective_dataplex     = local.effective_dataplex_key != "" ? var.dataplex_scan_names[local.effective_dataplex_key] : ""

  etl_required_apis = toset(concat(
    [
      "pubsub.googleapis.com",
      "workflows.googleapis.com",
      "workflowexecutions.googleapis.com",
      "iam.googleapis.com",
    ],
    var.enable_batch_job ? ["run.googleapis.com"] : [],
    var.enable_datastream_cdc ? ["datastream.googleapis.com"] : [],
    var.enable_schedule ? ["cloudscheduler.googleapis.com"] : [],
    var.enable_gcs_eventarc_trigger ? ["eventarc.googleapis.com"] : [],
  ))
}

resource "terraform_data" "validate_enterprise_inputs" {
  lifecycle {
    precondition {
      condition     = !var.enable_batch_job || trimspace(var.batch_container_image) != ""
      error_message = "batch_container_image is required when enable_batch_job is true."
    }
    precondition {
      condition     = !var.enable_datastream_cdc || (var.datastream_db_host != "" && var.datastream_db_username != "" && var.datastream_db_password_secret_version != "")
      error_message = "datastream_db_host, datastream_db_username, and datastream_db_password_secret_version are required when enable_datastream_cdc is true."
    }
  }
}

resource "google_project_service" "etl_apis" {
  for_each = local.etl_required_apis

  project            = var.etl_compute_project_id
  service            = each.value
  disable_on_destroy = false
}

resource "time_sleep" "api_propagation" {
  create_duration = var.propagation_wait_seconds

  depends_on = [google_project_service.etl_apis]
}

resource "google_project_service_identity" "pubsub_agent" {
  count    = var.enable_pubsub_stream ? 1 : 0
  provider = google-beta
  project  = var.etl_compute_project_id
  service  = "pubsub.googleapis.com"

  depends_on = [time_sleep.api_propagation]
}

resource "google_project_service_identity" "datastream_agent" {
  count    = var.enable_datastream_cdc ? 1 : 0
  provider = google-beta
  project  = var.etl_compute_project_id
  service  = "datastream.googleapis.com"

  depends_on = [time_sleep.api_propagation]
}

resource "google_project_service_identity" "workflows_agent" {
  count    = var.enable_pipeline_workflow ? 1 : 0
  provider = google-beta
  project  = var.etl_compute_project_id
  service  = "workflows.googleapis.com"

  depends_on = [time_sleep.api_propagation]
}

resource "google_project_service_identity" "run_agent" {
  count    = var.enable_batch_job ? 1 : 0
  provider = google-beta
  project  = var.etl_compute_project_id
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

module "pubsub_bigquery" {
  count  = var.enable_pubsub_stream ? 1 : 0
  source = "../../modules/ingestion/pubsub-bigquery"

  project_id                 = var.etl_compute_project_id
  region                     = var.region
  prefix                     = var.prefix
  stream_name                = "pos-orders"
  bronze_project_id          = var.core_storage_project_id
  bronze_dataset_id          = var.bronze_dataset_id
  pubsub_project_number      = data.google_project.etl.number
  target_table_id            = var.pubsub_target_table_id
  schema_type                = var.pubsub_schema_type
  kms_key_id                 = local.effective_kms_key_id
  delete_contents_on_destroy = var.delete_contents_on_destroy
  labels                     = var.labels

  depends_on = [
    time_sleep.service_identity_propagation,
    time_sleep.cmek_propagation,
  ]
}

module "batch_elt_job" {
  count  = var.enable_batch_job ? 1 : 0
  source = "../../modules/ingestion/batch-elt-job"

  compute_project_id         = var.etl_compute_project_id
  bronze_project_id          = var.core_storage_project_id
  bronze_dataset_id          = var.bronze_dataset_id
  landing_bucket_name        = var.landing_bucket_name
  region                     = var.region
  prefix                     = var.prefix
  container_image            = var.batch_container_image
  source_prefix              = var.batch_source_prefix
  target_table               = var.batch_target_table
  source_format              = var.batch_source_format
  kms_key_id                 = local.effective_kms_key_id
  delete_contents_on_destroy = var.delete_contents_on_destroy
  labels                     = var.labels

  depends_on = [
    terraform_data.validate_enterprise_inputs,
    time_sleep.service_identity_propagation,
    time_sleep.cmek_propagation,
  ]
}

module "datastream_cdc" {
  count  = var.enable_datastream_cdc ? 1 : 0
  source = "../../modules/ingestion/datastream-cdc"

  project_id                 = var.etl_compute_project_id
  region                     = var.region
  prefix                     = var.prefix
  stream_name                = "pos-cdc"
  source_engine              = var.datastream_source_engine
  db_host                    = var.datastream_db_host
  db_port                    = var.datastream_db_port
  db_username                = var.datastream_db_username
  db_database                = var.datastream_db_database
  db_password_secret_version = var.datastream_db_password_secret_version
  bronze_project_id          = var.core_storage_project_id
  bronze_dataset_id          = var.bronze_dataset_id
  cdc_mode                   = var.datastream_cdc_mode
  create_private_connection  = var.datastream_create_private_connection
  network_attachment         = var.datastream_network_attachment
  vpc_id                     = local.effective_vpc_id
  peering_cidr               = var.datastream_peering_cidr
  kms_key_name               = local.effective_kms_key_id
  create_without_validation  = var.datastream_create_without_validation
  labels                     = var.labels

  depends_on = [
    terraform_data.validate_enterprise_inputs,
    time_sleep.service_identity_propagation,
    time_sleep.cmek_propagation,
  ]
}

module "pipeline_workflows" {
  count  = var.enable_pipeline_workflow ? 1 : 0
  source = "../../modules/ingestion/pipeline-workflows"

  compute_project_id             = var.etl_compute_project_id
  gold_project_id                = var.primary_gold_project_id
  region                         = var.region
  prefix                         = var.prefix
  ops_telemetry_dataset_id       = var.ops_telemetry_dataset_id
  dataform_repository_name       = var.dataform_repository_name
  dataform_release_config_name   = var.dataform_release_config_name
  dataform_service_account_email = var.dataform_service_account_email
  batch_job_name                 = var.enable_batch_job ? module.batch_elt_job[0].job_resource_path : ""
  default_run_batch_job          = var.enable_batch_job
  dataplex_scan_name             = local.effective_dataplex
  default_run_dataplex_scan      = local.effective_dataplex != ""
  enable_schedule                = var.enable_schedule
  schedule_cron                  = var.schedule_cron
  enable_gcs_eventarc_trigger    = var.enable_gcs_eventarc_trigger
  landing_bucket_name            = var.landing_bucket_name
  landing_bucket_project_id      = var.core_storage_project_id
  kms_key_id                     = local.effective_kms_key_id
  delete_contents_on_destroy     = var.delete_contents_on_destroy
  labels                         = var.labels

  depends_on = [
    time_sleep.service_identity_propagation,
    time_sleep.cmek_propagation,
  ]
}
