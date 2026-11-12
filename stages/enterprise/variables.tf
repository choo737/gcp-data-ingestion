variable "core_storage_project_id" {
  type        = string
  default     = ""
  description = "Core Bronze and Silver storage project ID linked from gcp-foundation."
}

variable "core_project_id" {
  type        = string
  default     = ""
  description = "Alias for core_storage_project_id linked from gcp-foundation."
}

variable "etl_compute_project_id" {
  type        = string
  default     = ""
  description = "ETL compute project ID hosting Dataform, Workflows, Pub/Sub, and Cloud Run."
}

variable "compute_project_id" {
  type        = string
  default     = ""
  description = "Alias for etl_compute_project_id linked from gcp-foundation."
}

variable "primary_gold_project_id" {
  type        = string
  default     = ""
  description = "Primary Gold mart project ID hosting Dataplex scans."
}

variable "analytics_project_id" {
  type        = string
  default     = ""
  description = "Alias for primary_gold_project_id linked from gcp-foundation."
}

variable "bi_project_id" {
  type        = string
  default     = ""
  description = "Optional linked BI presentation project ID from gcp-foundation."
}

variable "governance_project_id" {
  type        = string
  default     = ""
  description = "Optional linked governance project ID from gcp-foundation."
}

variable "bronze_dataset_id" {
  type        = string
  description = "Core Bronze BigQuery dataset ID linked from gcp-foundation."
}

variable "silver_dataset_id" {
  type        = string
  default     = ""
  description = "Optional linked Silver dataset ID from gcp-foundation."
}

variable "primary_gold_dataset_id" {
  type        = string
  default     = ""
  description = "Primary Gold mart dataset ID linked from gcp-foundation."
}

variable "gold_dataset_id" {
  type        = string
  default     = ""
  description = "Alias for primary_gold_dataset_id linked from gcp-foundation."
}

variable "quarantine_dataset_id" {
  type        = string
  default     = ""
  description = "Optional linked quarantine dataset ID from gcp-foundation."
}

variable "assertions_dataset_id" {
  type        = string
  default     = ""
  description = "Optional BigQuery assertions dataset ID passed to Dataform assertionSchema."
}

variable "landing_bucket_name" {
  type        = string
  description = "Raw GCS landing bucket name linked from gcp-foundation."
}

variable "ops_telemetry_dataset_id" {
  type        = string
  default     = ""
  description = "Operational telemetry BigQuery dataset ID in compute project."
}

variable "dataform_repository_name" {
  type        = string
  description = "Dataform repository short name or path in compute project."
}

variable "dataform_release_config_name" {
  type        = string
  default     = ""
  description = "Dataform release configuration name linked from gcp-foundation."
}

variable "dataform_release_config_id" {
  type        = string
  default     = ""
  description = "Dataform release configuration ID or path linked from gcp-foundation."
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

variable "batch_loader_sa_email" {
  type        = string
  default     = ""
  description = "Optional pre-created batch loader service account email from gcp-foundation."
}

variable "pubsub_writer_sa_email" {
  type        = string
  default     = ""
  description = "Optional Pub/Sub writer service account email granted topic publisher."
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
  description = "Optional regional Cloud KMS key ID linked from gcp-foundation."
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
  description = "Optional VPC network resource ID for Direct VPC egress and Datastream."
}

variable "network_id" {
  type        = string
  default     = ""
  description = "Optional linked VPC network_id output from gcp-foundation security-network."
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

variable "artifact_registry_repository_uri" {
  type        = string
  default     = ""
  description = "Optional Artifact Registry repository URI linked from gcp-foundation."
}

variable "batch_image_tag" {
  type        = string
  default     = ""
  description = "Optional tag or @sha256 digest appended to artifact_registry_repository_uri."
}

variable "notification_channel_ids" {
  type        = list(string)
  default     = []
  description = "Optional Cloud Monitoring notification channel IDs for workflow failure alerts."
}

variable "alert_email_addresses" {
  type        = list(string)
  default     = []
  description = "Optional email addresses for same-project workflow failure alert channels."
}

variable "region" {
  type        = string
  default     = "asia-southeast1"
  description = "GCP region matching the upstream gcp-foundation deployment."
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Target environment name (for example dev, staging, prod)."
}

variable "prefix" {
  type        = string
  default     = "ent"
  description = "Naming prefix matching the upstream gcp-foundation deployment."
}

variable "delete_contents_on_destroy" {
  type        = bool
  default     = false
  description = "Whether destroy disables deletion protection on tables, jobs, and workflows."
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
  description = "Whether to provision Datastream CDC private connectivity and stream."
}

variable "datastream_source_engine" {
  type        = string
  default     = "POSTGRESQL"
  description = "Datastream source engine: POSTGRESQL or MYSQL."
}

variable "datastream_db_host" {
  type        = string
  default     = ""
  description = "Private IP address or hostname of the source database."
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

variable "datastream_create_private_connection" {
  type        = bool
  default     = false
  description = "Whether to create a Datastream private connectivity resource."
}

variable "datastream_network_attachment" {
  type        = string
  default     = ""
  description = "PSC network attachment resource ID for Datastream private connectivity."
}

variable "datastream_network_attachment_id" {
  type        = string
  default     = ""
  description = "Alias for datastream_network_attachment linked from gcp-foundation."
}

variable "datastream_peering_cidr" {
  type        = string
  default     = ""
  description = "Dedicated /29 CIDR range when using Datastream VPC peering."
}

variable "datastream_create_without_validation" {
  type        = bool
  default     = false
  description = "Whether to skip source connectivity validation during apply."
}

variable "enable_pipeline_workflow" {
  type        = bool
  default     = true
  description = "Whether to provision Cloud Workflows pipeline runner and telemetry table."
}

variable "enable_schedule" {
  type        = bool
  default     = true
  description = "Whether to provision a Cloud Scheduler job for the Cloud Workflow."
}

variable "schedule_cron" {
  type        = string
  default     = "0 2 * * *"
  description = "Cron schedule for Cloud Scheduler."
}

variable "enable_gcs_eventarc_trigger" {
  type        = bool
  default     = false
  description = "Whether to trigger the Cloud Workflow on GCS landing object finalization."
}

variable "propagation_wait_seconds" {
  type        = string
  default     = "30s"
  description = "Wait duration after API activation and CMEK IAM grants."
}

variable "labels" {
  type = map(string)
  default = {
    managed_by = "terraform"
  }
  description = "Labels applied to enterprise ingestion resources."
}
