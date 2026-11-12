variable "project_id" {
  type        = string
  description = "Existing sandbox GCP project ID hosting ingestion, BigQuery, and Workflows."
}

variable "region" {
  type        = string
  default     = "asia-southeast1"
  description = "GCP region for Pub/Sub, Cloud Run, Datastream, and Cloud Workflows."
}

variable "prefix" {
  type        = string
  default     = "bqfnd"
  description = "Naming prefix matching gcp-foundation sandbox resources."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}[a-z0-9]$", var.prefix))
    error_message = "prefix must be 3-16 lowercase letters/digits/hyphens and start/end with alphanumeric."
  }
}

variable "dataset_ids" {
  type        = map(string)
  default     = {}
  description = "Optional linked map of Medallion dataset IDs from gcp-foundation data/sandbox."
}

variable "bronze_dataset_id" {
  type        = string
  default     = ""
  description = "Target BigQuery Bronze dataset ID (auto-resolved from dataset_ids when empty)."
}

variable "silver_dataset_id" {
  type        = string
  default     = ""
  description = "Optional Silver BigQuery dataset ID (auto-resolved from dataset_ids when empty)."
}

variable "gold_dataset_id" {
  type        = string
  default     = ""
  description = "Optional Gold BigQuery dataset ID (auto-resolved from dataset_ids when empty)."
}

variable "assertions_dataset_id" {
  type        = string
  default     = ""
  description = "Optional Dataform assertions dataset ID (auto-resolved from dataset_ids when empty)."
}

variable "create_bronze_dataset" {
  type        = bool
  default     = false
  description = "Set true only when deploying sandbox without upstream gcp-foundation datasets."
}

variable "ops_telemetry_dataset_id" {
  type        = string
  default     = ""
  description = "BigQuery dataset ID storing pipeline_runs telemetry (auto-created when empty)."
}

variable "create_ops_telemetry_dataset" {
  type        = bool
  default     = true
  description = "Whether sandbox provisions the ops_telemetry dataset when ops_telemetry_dataset_id is empty."
}

variable "dataform_repository_name" {
  type        = string
  default     = ""
  description = "Dataform repository short name linked from gcp-foundation."
}

variable "dataform_release_config_name" {
  type        = string
  default     = ""
  description = "Dataform release config name linked from gcp-foundation (empty uses gitCommitish main)."
}

variable "dataform_release_config_id" {
  type        = string
  default     = ""
  description = "Alias for dataform_release_config_name linked from gcp-foundation."
}

variable "dataform_git_commitish" {
  type        = string
  default     = "main"
  description = "Git branch or commit used when compiling without releaseConfig."
}

variable "dataform_service_account_email" {
  type        = string
  default     = ""
  description = "Dataform ETL service account email linked from gcp-foundation."
}

variable "dataform_sa_email" {
  type        = string
  default     = ""
  description = "Alias for dataform_service_account_email linked from gcp-foundation."
}

variable "dataplex_scan_names" {
  type        = map(string)
  default     = {}
  description = "Map of Dataplex scan resource names linked from gcp-foundation."
}

variable "dataplex_profile_scan_id" {
  type        = string
  default     = ""
  description = "Optional Dataplex profile scan resource ID linked from gcp-foundation."
}

variable "dataplex_quality_scan_id" {
  type        = string
  default     = ""
  description = "Optional Dataplex auto data quality scan resource ID linked from gcp-foundation."
}

variable "kms_key_id" {
  type        = string
  default     = ""
  description = "Optional regional Cloud KMS key ID for CMEK encryption."
}

variable "kms_key_name" {
  type        = string
  default     = ""
  description = "Alias for kms_key_id linked from gcp-foundation."
}

variable "pii_restricted_policy_tag_id" {
  type        = string
  default     = ""
  description = "Optional Data Catalog restricted PII policy tag ID for customer_ic_number."
}

variable "pii_masked_policy_tag_id" {
  type        = string
  default     = ""
  description = "Optional Data Catalog masked PII policy tag ID for customer_email."
}

variable "vpc_id" {
  type        = string
  default     = ""
  description = "Optional VPC network resource ID for Direct VPC egress."
}

variable "subnet_id" {
  type        = string
  default     = ""
  description = "Optional subnetwork resource ID for Cloud Run Direct VPC egress."
}

variable "batch_vpc_egress" {
  type        = string
  default     = "PRIVATE_RANGES_ONLY"
  description = "Direct VPC egress mode for the batch loader: PRIVATE_RANGES_ONLY or ALL_TRAFFIC."

  validation {
    condition     = contains(["PRIVATE_RANGES_ONLY", "ALL_TRAFFIC"], var.batch_vpc_egress)
    error_message = "batch_vpc_egress must be PRIVATE_RANGES_ONLY or ALL_TRAFFIC."
  }
}

variable "notification_channel_ids" {
  type        = list(string)
  default     = []
  description = "Optional Cloud Monitoring notification channel IDs for workflow failure alerts."
}

variable "delete_contents_on_destroy" {
  type        = bool
  default     = false
  description = "Whether destroy drops sandbox tables, bucket objects, and deletion protection."
}

variable "enable_pubsub_stream" {
  type        = bool
  default     = true
  description = "Whether to provision schema-validated Pub/Sub BigQuery streaming and DLQ."
}

variable "pubsub_schema_type" {
  type        = string
  default     = "PROTOCOL_BUFFER"
  description = "Pub/Sub topic schema type: PROTOCOL_BUFFER or AVRO."
}

variable "pubsub_target_table_id" {
  type        = string
  default     = "pos_orders_stream_cdc"
  description = "BigQuery Bronze table ID receiving streamed Pub/Sub events."
}

variable "enable_batch_job" {
  type        = bool
  default     = false
  description = "Whether to provision the Cloud Run v2 GCS-to-Bronze batch loader job."
}

variable "batch_container_image" {
  type        = string
  default     = ""
  description = "Container image URI built from jobs/gcs_to_bronze when enable_batch_job is true."
}

variable "batch_source_prefix" {
  type        = string
  default     = "incoming/"
  description = "Landing bucket object prefix scanned by the batch loader."
}

variable "batch_target_table" {
  type        = string
  default     = "pos_orders_batch_cdc"
  description = "Destination Bronze table name for batch loads."
}

variable "batch_source_format" {
  type        = string
  default     = "NEWLINE_DELIMITED_JSON"
  description = "Batch source file format: CSV, NEWLINE_DELIMITED_JSON, or PARQUET."
}

variable "enable_datastream_cdc" {
  type        = bool
  default     = false
  description = "Whether to provision Datastream CDC resources when a database source is reachable."
}

variable "datastream_source_engine" {
  type        = string
  default     = "POSTGRESQL"
  description = "Datastream source engine: POSTGRESQL or MYSQL."
}

variable "datastream_db_host" {
  type        = string
  default     = ""
  description = "Source database IP or hostname when enable_datastream_cdc is true."
}

variable "datastream_db_port" {
  type        = number
  default     = 0
  description = "Source database port (0 selects engine default)."
}

variable "datastream_db_username" {
  type        = string
  default     = ""
  description = "Database replication user name."
}

variable "datastream_db_database" {
  type        = string
  default     = "appdb"
  description = "PostgreSQL source database name."
}

variable "datastream_db_password_secret_version" {
  type        = string
  default     = ""
  description = "Secret Manager version holding the source database password."
}

variable "datastream_cdc_mode" {
  type        = string
  default     = "APPEND_ONLY"
  description = "BigQuery CDC write mode: APPEND_ONLY or MERGE."
}

variable "datastream_create_without_validation" {
  type        = bool
  default     = true
  description = "Skip live source connectivity validation during sandbox Terraform apply."
}

variable "enable_pipeline_workflow" {
  type        = bool
  default     = true
  description = "Whether to provision Cloud Workflows pipeline runner and telemetry table."
}

variable "enable_schedule" {
  type        = bool
  default     = false
  description = "Whether to schedule the Cloud Workflow via Cloud Scheduler."
}

variable "schedule_cron" {
  type        = string
  default     = "0 2 * * *"
  description = "Cron schedule for Cloud Scheduler."
}

variable "enable_gcs_eventarc_trigger" {
  type        = bool
  default     = false
  description = "Whether to trigger the Cloud Workflow on GCS object finalization."
}

variable "propagation_wait_seconds" {
  type        = string
  default     = "30s"
  description = "Wait duration after API activation and service identity creation."
}

variable "labels" {
  type = map(string)
  default = {
    environment = "sandbox"
    managed_by  = "terraform"
  }
  description = "Labels applied to sandbox ingestion resources."
}
