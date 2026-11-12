variable "compute_project_id" {
  type        = string
  description = "GCP compute project ID hosting Cloud Workflows, Dataform, and ops telemetry."
}

variable "gold_project_id" {
  type        = string
  default     = ""
  description = "GCP project ID hosting Dataplex data scans (defaults to compute_project_id)."
}

variable "region" {
  type        = string
  default     = "asia-southeast1"
  description = "GCP region for Cloud Workflows, Scheduler, and Eventarc triggers."
}

variable "prefix" {
  type        = string
  description = "Short lowercase prefix applied to workflow, topic, and trigger names."
}

variable "ops_telemetry_dataset_id" {
  type        = string
  description = "BigQuery dataset ID in compute_project_id storing pipeline_runs telemetry."
}

variable "dataform_repository_name" {
  type        = string
  description = "Dataform repository short name in compute_project_id."
}

variable "dataform_release_config_name" {
  type        = string
  default     = "prod-main"
  description = "Dataform release configuration name (empty falls back to gitCommitish main)."
}

variable "dataform_service_account_email" {
  type        = string
  default     = ""
  description = "Dataform execution service account email for iam.serviceAccountUser binding."
}

variable "batch_job_name" {
  type        = string
  default     = ""
  description = "Optional Cloud Run v2 batch job name or resource path triggered before Dataform."
}

variable "default_run_batch_job" {
  type        = bool
  default     = false
  description = "Default value for run_batch_job when workflow input omits it."
}

variable "dataplex_scan_name" {
  type        = string
  default     = ""
  description = "Optional Dataplex data scan resource name triggered after Dataform succeeds."
}

variable "default_run_dataplex_scan" {
  type        = bool
  default     = true
  description = "Default value for run_dataplex_scan when workflow input omits it."
}

variable "enable_schedule" {
  type        = bool
  default     = false
  description = "Whether to provision a Cloud Scheduler job triggering the workflow."
}

variable "schedule_cron" {
  type        = string
  default     = "0 2 * * *"
  description = "Cron schedule for Cloud Scheduler triggers."
}

variable "schedule_time_zone" {
  type        = string
  default     = "Asia/Kuala_Lumpur"
  description = "IANA time zone applied to the Cloud Scheduler job."
}

variable "schedule_payload" {
  type        = map(any)
  default     = {}
  description = "JSON payload passed as workflow runtime argument by Cloud Scheduler."
}

variable "enable_gcs_eventarc_trigger" {
  type        = bool
  default     = false
  description = "Whether to create an Eventarc trigger on GCS object.v1.finalized events."
}

variable "landing_bucket_name" {
  type        = string
  default     = ""
  description = "Cloud Storage bucket watched by Eventarc when enable_gcs_eventarc_trigger is true."
}

variable "landing_bucket_project_id" {
  type        = string
  default     = ""
  description = "GCP project ID owning landing_bucket_name (defaults to compute_project_id)."
}

variable "kms_key_id" {
  type        = string
  default     = ""
  description = "Optional regional Cloud KMS key ID for Workflow, Pub/Sub alerts, and telemetry table."
}

variable "delete_contents_on_destroy" {
  type        = bool
  default     = false
  description = "Whether Terraform destroy disables deletion protection on Workflow and BigQuery tables."
}

variable "workflow_source_contents" {
  type        = string
  default     = ""
  description = "Optional override YAML string; defaults to workflows/medallion_pipeline.workflows.yaml."
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Resource labels applied to Workflow, Pub/Sub, BigQuery, and Eventarc resources."
}
