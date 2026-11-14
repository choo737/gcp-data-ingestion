provider "google" {
  region = var.region
}

provider "google-beta" {
  region = var.region
}

locals {
  raw_core_storage_proj     = var.core_storage_project_id != null ? trimspace(var.core_storage_project_id) : ""
  raw_core_proj             = var.core_project_id != null ? trimspace(var.core_project_id) : ""
  effective_core_project_id = local.raw_core_storage_proj != "" ? local.raw_core_storage_proj : local.raw_core_proj

  raw_etl_compute_proj         = var.etl_compute_project_id != null ? trimspace(var.etl_compute_project_id) : ""
  raw_compute_proj             = var.compute_project_id != null ? trimspace(var.compute_project_id) : ""
  effective_compute_project_id = local.raw_etl_compute_proj != "" ? local.raw_etl_compute_proj : local.raw_compute_proj

  raw_primary_gold_proj     = var.primary_gold_project_id != null ? trimspace(var.primary_gold_project_id) : ""
  raw_analytics_proj        = var.analytics_project_id != null ? trimspace(var.analytics_project_id) : ""
  effective_gold_project_id = local.raw_primary_gold_proj != "" ? local.raw_primary_gold_proj : (local.raw_analytics_proj != "" ? local.raw_analytics_proj : local.effective_compute_project_id)

  dataset_prefix              = replace(var.prefix, "-", "_")
  raw_ops_ds                  = var.ops_telemetry_dataset_id != null ? trimspace(var.ops_telemetry_dataset_id) : ""
  effective_ops_telemetry_ds  = local.raw_ops_ds != "" ? local.raw_ops_ds : "${local.dataset_prefix}_ops_telemetry"
  effective_silver_dataset_id = var.silver_dataset_id != null ? trimspace(var.silver_dataset_id) : ""
  raw_primary_gold_ds         = var.primary_gold_dataset_id != null ? trimspace(var.primary_gold_dataset_id) : ""
  raw_gold_ds                 = var.gold_dataset_id != null ? trimspace(var.gold_dataset_id) : ""
  effective_gold_dataset_id   = local.raw_primary_gold_ds != "" ? local.raw_primary_gold_ds : local.raw_gold_ds
  effective_assertions_ds     = var.assertions_dataset_id != null ? trimspace(var.assertions_dataset_id) : ""

  raw_kms_id           = var.kms_key_id != null ? trimspace(var.kms_key_id) : ""
  raw_kms_name         = var.kms_key_name != null ? trimspace(var.kms_key_name) : ""
  effective_kms_key_id = local.raw_kms_id != "" ? local.raw_kms_id : local.raw_kms_name
  use_cmek             = local.effective_kms_key_id != ""

  raw_vpc_id          = var.vpc_id != null ? trimspace(var.vpc_id) : ""
  raw_network_id      = var.network_id != null ? trimspace(var.network_id) : ""
  effective_vpc_id    = local.raw_vpc_id != "" ? local.raw_vpc_id : local.raw_network_id
  effective_subnet_id = var.subnet_id != null ? trimspace(var.subnet_id) : ""

  raw_ds_net_att              = var.datastream_network_attachment != null ? trimspace(var.datastream_network_attachment) : ""
  raw_ds_net_att_id           = var.datastream_network_attachment_id != null ? trimspace(var.datastream_network_attachment_id) : ""
  effective_ds_net_attachment = local.raw_ds_net_att != "" ? local.raw_ds_net_att : local.raw_ds_net_att_id

  raw_df_release_name         = var.dataform_release_config_name != null ? trimspace(var.dataform_release_config_name) : ""
  raw_df_release_id           = var.dataform_release_config_id != null ? trimspace(var.dataform_release_config_id) : ""
  effective_df_release_config = local.raw_df_release_id != "" ? local.raw_df_release_id : local.raw_df_release_name

  raw_df_sa                   = var.dataform_service_account_email != null ? trimspace(var.dataform_service_account_email) : ""
  raw_df_sa_alias             = var.dataform_sa_email != null ? trimspace(var.dataform_sa_email) : ""
  effective_dataform_sa_email = local.raw_df_sa != "" ? local.raw_df_sa : local.raw_df_sa_alias

  raw_pubsub_writer_sa         = var.pubsub_writer_sa_email != null ? trimspace(var.pubsub_writer_sa_email) : ""
  raw_batch_loader_sa          = var.batch_loader_sa_email != null ? trimspace(var.batch_loader_sa_email) : ""
  raw_shared_ds_priv_conn      = var.shared_datastream_private_connection_id != null ? trimspace(var.shared_datastream_private_connection_id) : ""
  effective_pii_restricted_tag = var.pii_restricted_policy_tag_id != null ? trimspace(var.pii_restricted_policy_tag_id) : ""
  effective_pii_masked_tag     = var.pii_masked_policy_tag_id != null ? trimspace(var.pii_masked_policy_tag_id) : ""

  raw_batch_image = var.batch_container_image != null ? trimspace(var.batch_container_image) : ""
  raw_ar_uri      = var.artifact_registry_repository_uri != null ? trimsuffix(trimspace(var.artifact_registry_repository_uri), "/") : ""
  raw_image_tag   = var.batch_image_tag != null ? trimspace(var.batch_image_tag) : ""
  effective_batch_image = (
    local.raw_batch_image != ""
    ? local.raw_batch_image
    : (local.raw_ar_uri != "" && local.raw_image_tag != ""
      ? "${local.raw_ar_uri}/gcs-to-bronze${startswith(local.raw_image_tag, "@") ? local.raw_image_tag : ":${local.raw_image_tag}"}"
    : "")
  )

  raw_profile_scan       = var.dataplex_profile_scan_id != null ? trimspace(var.dataplex_profile_scan_id) : ""
  raw_quality_scan       = var.dataplex_quality_scan_id != null ? trimspace(var.dataplex_quality_scan_id) : ""
  map_profile_key        = length(var.dataplex_scan_names) > 0 ? (contains(keys(var.dataplex_scan_names), "masked_customers_canary") ? "masked_customers_canary" : sort(keys(var.dataplex_scan_names))[0]) : ""
  map_quality_keys       = [for k in sort(keys(var.dataplex_scan_names)) : k if length(regexall("quality", lower(k))) > 0]
  effective_profile_scan = local.raw_profile_scan != "" ? local.raw_profile_scan : (local.map_profile_key != "" ? var.dataplex_scan_names[local.map_profile_key] : "")
  effective_quality_scan = local.raw_quality_scan != "" ? local.raw_quality_scan : (length(local.map_quality_keys) > 0 ? var.dataplex_scan_names[local.map_quality_keys[0]] : "")

  effective_labels = merge({ environment = var.environment, managed_by = "terraform" }, var.labels)

  any_pubsub_enabled     = var.enable_pubsub_stream || length(var.pubsub_streams) > 0
  any_batch_enabled      = var.enable_batch_job || length(var.batch_jobs) > 0
  any_datastream_enabled = var.enable_datastream_cdc || var.enable_shared_datastream_private_connection || length(var.datastream_streams) > 0

  shared_ds_priv_conn_id = (
    var.enable_shared_datastream_private_connection
    ? google_datastream_private_connection.shared[0].id
    : local.raw_shared_ds_priv_conn
  )

  etl_required_apis = toset(concat(
    [
      "pubsub.googleapis.com",
      "workflows.googleapis.com",
      "workflowexecutions.googleapis.com",
      "iam.googleapis.com",
    ],
    local.any_batch_enabled ? ["run.googleapis.com"] : [],
    local.any_datastream_enabled ? ["datastream.googleapis.com"] : [],
    var.enable_schedule ? ["cloudscheduler.googleapis.com"] : [],
    var.enable_gcs_eventarc_trigger ? ["eventarc.googleapis.com"] : [],
    (length(var.notification_channel_ids) > 0 || length(var.alert_email_addresses) > 0) ? ["monitoring.googleapis.com"] : [],
  ))
}

data "google_project" "etl" {
  project_id = local.effective_compute_project_id
}

resource "terraform_data" "validate_enterprise_inputs" {
  lifecycle {
    precondition {
      condition     = local.effective_core_project_id != ""
      error_message = "Either core_storage_project_id or core_project_id must be set."
    }
    precondition {
      condition     = local.effective_compute_project_id != ""
      error_message = "Either etl_compute_project_id or compute_project_id must be set."
    }
    precondition {
      condition     = !var.enable_batch_job || local.effective_batch_image != ""
      error_message = "batch_container_image (or artifact_registry_repository_uri with batch_image_tag) is required when enable_batch_job is true."
    }
    precondition {
      condition     = !var.enable_datastream_cdc || (var.datastream_db_host != "" && var.datastream_db_username != "" && var.datastream_db_password_secret_version != "")
      error_message = "datastream_db_host, datastream_db_username, and datastream_db_password_secret_version are required when enable_datastream_cdc is true."
    }
    precondition {
      condition     = !var.enable_shared_datastream_private_connection || local.effective_ds_net_attachment != "" || (local.effective_vpc_id != "" && var.datastream_peering_cidr != "")
      error_message = "enable_shared_datastream_private_connection requires datastream_network_attachment_id or both vpc_id and datastream_peering_cidr."
    }
    precondition {
      condition     = alltrue([for k, v in var.batch_jobs : trimspace(v.container_image) != "" || local.effective_batch_image != ""])
      error_message = "Each batch_jobs entry requires container_image or a stage-level batch_container_image."
    }
  }
}

resource "google_project_service" "etl_apis" {
  for_each = local.etl_required_apis

  project            = local.effective_compute_project_id
  service            = each.value
  disable_on_destroy = false
}

resource "time_sleep" "api_propagation" {
  create_duration = var.propagation_wait_seconds

  depends_on = [google_project_service.etl_apis]
}

resource "google_project_service_identity" "pubsub_agent" {
  count    = local.any_pubsub_enabled ? 1 : 0
  provider = google-beta
  project  = local.effective_compute_project_id
  service  = "pubsub.googleapis.com"

  depends_on = [time_sleep.api_propagation]
}

resource "google_project_service_identity" "datastream_agent" {
  count    = local.any_datastream_enabled ? 1 : 0
  provider = google-beta
  project  = local.effective_compute_project_id
  service  = "datastream.googleapis.com"

  depends_on = [time_sleep.api_propagation]
}

resource "google_project_service_identity" "workflows_agent" {
  count    = var.enable_pipeline_workflow ? 1 : 0
  provider = google-beta
  project  = local.effective_compute_project_id
  service  = "workflows.googleapis.com"

  depends_on = [time_sleep.api_propagation]
}

resource "google_project_service_identity" "run_agent" {
  count    = local.any_batch_enabled ? 1 : 0
  provider = google-beta
  project  = local.effective_compute_project_id
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
  count = local.use_cmek && local.any_pubsub_enabled ? 1 : 0

  crypto_key_id = local.effective_kms_key_id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = google_project_service_identity.pubsub_agent[0].member

  depends_on = [time_sleep.service_identity_propagation]
}

resource "google_kms_crypto_key_iam_member" "datastream_cmek" {
  count = local.use_cmek && local.any_datastream_enabled ? 1 : 0

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
  count = local.use_cmek && local.any_batch_enabled ? 1 : 0

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

resource "google_datastream_private_connection" "shared" {
  count = var.enable_shared_datastream_private_connection ? 1 : 0

  project                   = local.effective_compute_project_id
  location                  = var.region
  private_connection_id     = trimsuffix(substr(lower(replace("${var.prefix}-shared-ds-priv", "_", "-")), 0, 60), "-")
  display_name              = "${var.prefix} shared datastream private"
  create_without_validation = var.datastream_create_without_validation
  labels                    = local.effective_labels

  dynamic "psc_interface_config" {
    for_each = local.effective_ds_net_attachment != "" ? [local.effective_ds_net_attachment] : []
    content {
      network_attachment = psc_interface_config.value
    }
  }

  dynamic "vpc_peering_config" {
    for_each = local.effective_ds_net_attachment == "" && local.effective_vpc_id != "" ? [1] : []
    content {
      vpc    = local.effective_vpc_id
      subnet = var.datastream_peering_cidr
    }
  }

  depends_on = [
    terraform_data.validate_enterprise_inputs,
    time_sleep.service_identity_propagation,
    time_sleep.cmek_propagation,
  ]
}

module "pubsub_bigquery" {
  count  = var.enable_pubsub_stream ? 1 : 0
  source = "../../modules/ingestion/pubsub-bigquery"

  project_id                   = local.effective_compute_project_id
  region                       = var.region
  prefix                       = var.prefix
  stream_name                  = "pos-orders"
  bronze_project_id            = local.effective_core_project_id
  bronze_dataset_id            = var.bronze_dataset_id
  pubsub_project_number        = data.google_project.etl.number
  target_table_id              = var.pubsub_target_table_id
  schema_type                  = var.pubsub_schema_type
  kms_key_id                   = local.effective_kms_key_id
  pii_restricted_policy_tag_id = local.effective_pii_restricted_tag
  pii_masked_policy_tag_id     = local.effective_pii_masked_tag
  writer_service_account_email = local.raw_pubsub_writer_sa
  delete_contents_on_destroy   = var.delete_contents_on_destroy
  labels                       = local.effective_labels

  depends_on = [
    terraform_data.validate_enterprise_inputs,
    time_sleep.service_identity_propagation,
    time_sleep.cmek_propagation,
  ]
}

module "batch_elt_job" {
  count  = var.enable_batch_job ? 1 : 0
  source = "../../modules/ingestion/batch-elt-job"

  compute_project_id           = local.effective_compute_project_id
  bronze_project_id            = local.effective_core_project_id
  bronze_dataset_id            = var.bronze_dataset_id
  landing_bucket_name          = var.landing_bucket_name
  region                       = var.region
  prefix                       = var.prefix
  container_image              = local.effective_batch_image
  source_prefix                = var.batch_source_prefix
  target_table                 = var.batch_target_table
  source_format                = var.batch_source_format
  service_account_email        = local.raw_batch_loader_sa
  kms_key_id                   = local.effective_kms_key_id
  pii_restricted_policy_tag_id = local.effective_pii_restricted_tag
  pii_masked_policy_tag_id     = local.effective_pii_masked_tag
  vpc_id                       = local.effective_vpc_id
  subnet_id                    = local.effective_subnet_id
  vpc_egress                   = var.batch_vpc_egress
  delete_contents_on_destroy   = var.delete_contents_on_destroy
  labels                       = local.effective_labels

  depends_on = [
    terraform_data.validate_enterprise_inputs,
    time_sleep.service_identity_propagation,
    time_sleep.cmek_propagation,
  ]
}

module "pubsub_streams" {
  for_each = var.pubsub_streams
  source   = "../../modules/ingestion/pubsub-bigquery"

  project_id                   = local.effective_compute_project_id
  region                       = var.region
  prefix                       = var.prefix
  stream_name                  = each.key
  bronze_project_id            = local.effective_core_project_id
  bronze_dataset_id            = var.bronze_dataset_id
  pubsub_project_number        = data.google_project.etl.number
  target_table_id              = each.value.target_table_id
  schema_type                  = each.value.schema_type
  schema_definition            = trimspace(each.value.schema_file) != "" ? file("${path.module}/../../${trimspace(each.value.schema_file)}") : each.value.schema_definition
  target_table_schema_json     = trimspace(each.value.target_table_schema_file) != "" ? file("${path.module}/../../${trimspace(each.value.target_table_schema_file)}") : each.value.target_table_schema_json
  target_clustering            = each.value.target_clustering
  drop_unknown_fields          = each.value.drop_unknown_fields
  kms_key_id                   = local.effective_kms_key_id
  pii_restricted_policy_tag_id = local.effective_pii_restricted_tag
  pii_masked_policy_tag_id     = local.effective_pii_masked_tag
  writer_service_account_email = trimspace(each.value.writer_service_account_email) != "" ? trimspace(each.value.writer_service_account_email) : local.raw_pubsub_writer_sa
  delete_contents_on_destroy   = var.delete_contents_on_destroy
  labels                       = local.effective_labels

  depends_on = [
    terraform_data.validate_enterprise_inputs,
    time_sleep.service_identity_propagation,
    time_sleep.cmek_propagation,
  ]
}

module "batch_jobs" {
  for_each = var.batch_jobs
  source   = "../../modules/ingestion/batch-elt-job"

  compute_project_id           = local.effective_compute_project_id
  bronze_project_id            = local.effective_core_project_id
  bronze_dataset_id            = var.bronze_dataset_id
  landing_bucket_name          = var.landing_bucket_name
  region                       = var.region
  prefix                       = var.prefix
  job_suffix                   = each.key
  container_image              = trimspace(each.value.container_image) != "" ? trimspace(each.value.container_image) : local.effective_batch_image
  source_prefix                = each.value.source_prefix
  target_table                 = each.value.target_table
  source_format                = each.value.source_format
  partition_field              = each.value.partition_field
  target_clustering            = each.value.target_clustering
  create_target_table          = each.value.create_target_table
  target_table_schema_json     = trimspace(each.value.target_table_schema_file) != "" ? file("${path.module}/../../${trimspace(each.value.target_table_schema_file)}") : each.value.target_table_schema_json
  service_account_email        = trimspace(each.value.service_account_email)
  quarantine_prefix            = each.value.quarantine_prefix
  fail_on_quarantine           = each.value.fail_on_quarantine
  max_retries                  = each.value.max_retries
  timeout                      = each.value.timeout
  kms_key_id                   = local.effective_kms_key_id
  pii_restricted_policy_tag_id = local.effective_pii_restricted_tag
  pii_masked_policy_tag_id     = local.effective_pii_masked_tag
  vpc_id                       = local.effective_vpc_id
  subnet_id                    = local.effective_subnet_id
  vpc_egress                   = var.batch_vpc_egress
  delete_contents_on_destroy   = var.delete_contents_on_destroy
  labels                       = local.effective_labels

  depends_on = [
    terraform_data.validate_enterprise_inputs,
    time_sleep.service_identity_propagation,
    time_sleep.cmek_propagation,
  ]
}

module "datastream_cdc" {
  count  = var.enable_datastream_cdc ? 1 : 0
  source = "../../modules/ingestion/datastream-cdc"

  project_id                 = local.effective_compute_project_id
  compute_project_id         = local.effective_compute_project_id
  region                     = var.region
  prefix                     = var.prefix
  stream_name                = "pos-cdc"
  source_engine              = var.datastream_source_engine
  db_host                    = var.datastream_db_host
  db_port                    = var.datastream_db_port
  db_username                = var.datastream_db_username
  db_database                = var.datastream_db_database
  db_password_secret_version = var.datastream_db_password_secret_version
  bronze_project_id          = local.effective_core_project_id
  bronze_dataset_id          = var.bronze_dataset_id
  cdc_mode                   = var.datastream_cdc_mode
  create_private_connection  = var.datastream_create_private_connection
  private_connection_id      = var.datastream_create_private_connection ? "" : local.shared_ds_priv_conn_id
  network_attachment         = local.effective_ds_net_attachment
  vpc_id                     = local.effective_vpc_id
  peering_cidr               = var.datastream_peering_cidr
  kms_key_name               = local.effective_kms_key_id
  create_without_validation  = var.datastream_create_without_validation
  labels                     = local.effective_labels

  depends_on = [
    terraform_data.validate_enterprise_inputs,
    time_sleep.service_identity_propagation,
    time_sleep.cmek_propagation,
  ]
}

module "datastream_streams" {
  for_each = var.datastream_streams
  source   = "../../modules/ingestion/datastream-cdc"

  project_id                  = local.effective_compute_project_id
  compute_project_id          = local.effective_compute_project_id
  region                      = var.region
  prefix                      = var.prefix
  stream_name                 = each.key
  source_engine               = each.value.source_engine
  db_host                     = each.value.db_host
  db_port                     = each.value.db_port
  db_username                 = each.value.db_username
  db_database                 = each.value.db_database
  db_password_secret_version  = each.value.db_password_secret_version
  postgresql_publication      = each.value.postgresql_publication
  postgresql_replication_slot = each.value.postgresql_replication_slot
  included_objects            = each.value.included_objects
  bronze_project_id           = local.effective_core_project_id
  bronze_dataset_id           = var.bronze_dataset_id
  cdc_mode                    = each.value.cdc_mode
  data_freshness              = each.value.data_freshness
  backfill_mode               = each.value.backfill_mode
  start_stream                = each.value.start_stream
  create_private_connection   = each.value.create_private_connection
  private_connection_id = each.value.create_private_connection ? "" : (
    trimspace(each.value.private_connection_id) != ""
    ? trimspace(each.value.private_connection_id)
    : local.shared_ds_priv_conn_id
  )
  network_attachment        = local.effective_ds_net_attachment
  vpc_id                    = local.effective_vpc_id
  peering_cidr              = var.datastream_peering_cidr
  kms_key_name              = local.effective_kms_key_id
  create_without_validation = var.datastream_create_without_validation
  labels                    = local.effective_labels

  depends_on = [
    terraform_data.validate_enterprise_inputs,
    time_sleep.service_identity_propagation,
    time_sleep.cmek_propagation,
  ]
}

module "pipeline_workflows" {
  count  = var.enable_pipeline_workflow ? 1 : 0
  source = "../../modules/ingestion/pipeline-workflows"

  compute_project_id             = local.effective_compute_project_id
  bronze_project_id              = local.effective_core_project_id
  bronze_dataset_id              = var.bronze_dataset_id
  silver_project_id              = local.effective_core_project_id
  silver_dataset_id              = local.effective_silver_dataset_id
  gold_project_id                = local.effective_gold_project_id
  gold_dataset_id                = local.effective_gold_dataset_id
  assertions_dataset_id          = local.effective_assertions_ds
  region                         = var.region
  prefix                         = var.prefix
  ops_telemetry_dataset_id       = local.effective_ops_telemetry_ds
  dataform_repository_name       = var.dataform_repository_name
  dataform_release_config_name   = local.effective_df_release_config
  dataform_git_commitish         = var.dataform_git_commitish
  dataform_service_account_email = local.effective_dataform_sa_email
  batch_job_name                 = var.enable_batch_job ? module.batch_elt_job[0].job_resource_path : ""
  batch_source_prefix            = var.batch_source_prefix
  default_run_batch_job          = var.enable_batch_job
  dataplex_scan_name             = local.effective_profile_scan
  dataplex_quality_scan_name     = local.effective_quality_scan
  default_run_dataplex_scan      = local.effective_profile_scan != "" || local.effective_quality_scan != ""
  include_stream_orders          = var.enable_pubsub_stream
  include_batch_orders           = var.enable_batch_job
  pii_restricted_policy_tag_id   = local.effective_pii_restricted_tag
  pii_masked_policy_tag_id       = local.effective_pii_masked_tag
  enable_schedule                = var.enable_schedule
  schedule_cron                  = var.schedule_cron
  enable_gcs_eventarc_trigger    = var.enable_gcs_eventarc_trigger
  landing_bucket_name            = var.landing_bucket_name
  landing_bucket_project_id      = local.effective_core_project_id
  kms_key_id                     = local.effective_kms_key_id
  notification_channel_ids       = var.notification_channel_ids
  alert_email_addresses          = var.alert_email_addresses
  delete_contents_on_destroy     = var.delete_contents_on_destroy
  labels                         = local.effective_labels

  depends_on = [
    terraform_data.validate_enterprise_inputs,
    time_sleep.service_identity_propagation,
    time_sleep.cmek_propagation,
  ]
}
