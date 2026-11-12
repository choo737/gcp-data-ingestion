variable "compute_project_id" {
  type        = string
  description = "GCP compute project ID hosting the Cloud Run batch job and service account."
}

variable "bronze_project_id" {
  type        = string
  description = "GCP project ID hosting the Bronze BigQuery dataset."
}

variable "bronze_dataset_id" {
  type        = string
  description = "BigQuery Bronze dataset ID receiving loaded files."
}

variable "landing_bucket_name" {
  type        = string
  description = "Cloud Storage landing bucket name holding incoming files and quarantine."
}

variable "region" {
  type        = string
  default     = "asia-southeast1"
  description = "GCP region where the Cloud Run batch job executes."
}

variable "prefix" {
  type        = string
  description = "Short lowercase prefix applied to the batch job and service account."
}

variable "job_suffix" {
  type        = string
  default     = "gcs-to-bronze"
  description = "Suffix appended to the Cloud Run job name."
}

variable "container_image" {
  type        = string
  description = "Artifact Registry container image URI built from jobs/gcs_to_bronze."
}

variable "source_prefix" {
  type        = string
  default     = "incoming/"
  description = "Cloud Storage object prefix scanned for new batch drops."
}

variable "target_table" {
  type        = string
  default     = "pos_orders_batch_cdc"
  description = "Destination BigQuery table name inside bronze_dataset_id."
}

variable "source_format" {
  type        = string
  default     = "NEWLINE_DELIMITED_JSON"
  description = "BigQuery load format: CSV, NEWLINE_DELIMITED_JSON, or PARQUET."

  validation {
    condition     = contains(["CSV", "NEWLINE_DELIMITED_JSON", "PARQUET"], var.source_format)
    error_message = "source_format must be CSV, NEWLINE_DELIMITED_JSON, or PARQUET."
  }
}

variable "quarantine_prefix" {
  type        = string
  default     = "quarantine/"
  description = "Object prefix in landing_bucket_name where failing files move."
}

variable "fail_on_quarantine" {
  type        = bool
  default     = true
  description = "Whether the loader exits non-zero if any object is quarantined."
}

variable "max_retries" {
  type        = number
  default     = 1
  description = "Maximum Cloud Run task retry attempts."
}

variable "timeout" {
  type        = string
  default     = "600s"
  description = "Maximum execution timeout per batch job task."
}

variable "kms_key_id" {
  type        = string
  default     = ""
  description = "Optional regional Cloud KMS key ID for BigQuery loads and Cloud Run."
}

variable "delete_contents_on_destroy" {
  type        = bool
  default     = false
  description = "Whether Terraform destroy disables deletion protection on the Cloud Run job."
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Resource labels applied to the Cloud Run batch job."
}

variable "create_target_table" {
  type        = bool
  default     = true
  description = "Pre-create the partitioned BigQuery Bronze target table with PII policy tags."
}

variable "target_table_schema_json" {
  type        = string
  default     = ""
  description = "Optional custom BigQuery JSON schema for the pre-created target table."
}

variable "target_clustering" {
  type        = list(string)
  default     = ["order_status", "store_id"]
  description = "Clustering columns applied to the partitioned Bronze batch table."
}

variable "pii_restricted_policy_tag_id" {
  type        = string
  default     = ""
  description = "Optional Data Catalog policy tag ID applied to customer_ic_number."
}

variable "pii_masked_policy_tag_id" {
  type        = string
  default     = ""
  description = "Optional Data Catalog policy tag ID applied to customer_email."
}

variable "vpc_id" {
  type        = string
  default     = ""
  description = "Optional VPC network resource ID or name for Direct VPC egress."
}

variable "subnet_id" {
  type        = string
  default     = ""
  description = "Optional subnetwork resource ID or name for Direct VPC egress."
}

variable "vpc_egress" {
  type        = string
  default     = "PRIVATE_RANGES_ONLY"
  description = "Cloud Run Direct VPC egress mode: PRIVATE_RANGES_ONLY or ALL_TRAFFIC."

  validation {
    condition     = contains(["PRIVATE_RANGES_ONLY", "ALL_TRAFFIC"], var.vpc_egress)
    error_message = "vpc_egress must be PRIVATE_RANGES_ONLY or ALL_TRAFFIC."
  }
}
