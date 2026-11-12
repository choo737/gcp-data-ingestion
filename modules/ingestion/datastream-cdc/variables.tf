variable "project_id" {
  type        = string
  description = "GCP project ID hosting Datastream profiles, private connectivity, and streams."
}

variable "compute_project_id" {
  type        = string
  default     = ""
  description = "Reservation-backed ETL compute project ID for BigQuery jobUser (defaults to project_id)."
}

variable "region" {
  type        = string
  default     = "asia-southeast1"
  description = "GCP region for Datastream resources."
}

variable "prefix" {
  type        = string
  description = "Short lowercase prefix applied to Datastream resource names."
}

variable "stream_name" {
  type        = string
  default     = "pos-cdc"
  description = "Logical CDC stream identifier."
}

variable "source_engine" {
  type        = string
  default     = "POSTGRESQL"
  description = "Source relational database engine: POSTGRESQL or MYSQL."

  validation {
    condition     = contains(["POSTGRESQL", "MYSQL"], var.source_engine)
    error_message = "source_engine must be POSTGRESQL or MYSQL."
  }
}

variable "db_host" {
  type        = string
  description = "Private IP address or hostname of the source database."
}

variable "db_port" {
  type        = number
  default     = 0
  description = "Source database port (0 selects 5432 for PostgreSQL or 3306 for MySQL)."
}

variable "db_username" {
  type        = string
  description = "Replication user name on the source database."
}

variable "db_database" {
  type        = string
  default     = "appdb"
  description = "PostgreSQL database name for CDC connections."
}

variable "db_password_secret_version" {
  type        = string
  description = "Secret Manager resource version holding the database password."

  validation {
    condition     = can(regex("^projects/[^/]+/secrets/[^/]+/versions/[^/]+$", var.db_password_secret_version))
    error_message = "db_password_secret_version must match projects/<project>/secrets/<secret>/versions/<version>."
  }
}

variable "postgresql_publication" {
  type        = string
  default     = "datastream_pub"
  description = "PostgreSQL logical replication publication name."
}

variable "postgresql_replication_slot" {
  type        = string
  default     = "datastream_slot"
  description = "PostgreSQL logical replication slot name."
}

variable "included_objects" {
  type        = map(list(string))
  default     = {}
  description = "Map of source schema or database names to included table name lists."
}

variable "bronze_project_id" {
  type        = string
  description = "Target BigQuery project ID holding the Bronze dataset."
}

variable "bronze_dataset_id" {
  type        = string
  description = "Target BigQuery Bronze dataset ID."
}

variable "cdc_mode" {
  type        = string
  default     = "APPEND_ONLY"
  description = "BigQuery write mode: APPEND_ONLY or MERGE."

  validation {
    condition     = contains(["APPEND_ONLY", "MERGE"], var.cdc_mode)
    error_message = "cdc_mode must be APPEND_ONLY or MERGE."
  }
}

variable "data_freshness" {
  type        = string
  default     = "300s"
  description = "Merge target data freshness SLA duration when cdc_mode is MERGE."
}

variable "backfill_mode" {
  type        = string
  default     = "ALL"
  description = "Initial historical backfill mode: ALL or NONE."

  validation {
    condition     = contains(["ALL", "NONE"], var.backfill_mode)
    error_message = "backfill_mode must be ALL or NONE."
  }
}

variable "max_concurrent_backfill_tasks" {
  type        = number
  default     = 4
  description = "Maximum concurrent backfill tasks for the Datastream source."
}

variable "max_concurrent_cdc_tasks" {
  type        = number
  default     = 4
  description = "Maximum concurrent CDC tasks for MySQL sources."
}

variable "create_private_connection" {
  type        = bool
  default     = false
  description = "Whether to provision a Datastream private connectivity resource."
}

variable "private_connection_id" {
  type        = string
  default     = ""
  description = "Existing Datastream private connection resource ID when create_private_connection is false."
}

variable "network_attachment" {
  type        = string
  default     = ""
  description = "PSC network attachment resource ID for private Datastream connectivity."
}

variable "vpc_id" {
  type        = string
  default     = ""
  description = "VPC network self-link or resource ID for VPC peering connectivity."
}

variable "peering_cidr" {
  type        = string
  default     = ""
  description = "Dedicated /29 CIDR range reserved for Datastream VPC peering."
}

variable "kms_key_name" {
  type        = string
  default     = ""
  description = "Optional regional Cloud KMS crypto key ID for Datastream encryption."
}

variable "start_stream" {
  type        = bool
  default     = false
  description = "Whether the Datastream stream should immediately target RUNNING state."
}

variable "create_without_validation" {
  type        = bool
  default     = false
  description = "Whether to skip source reachability validation at Terraform apply time."
}

variable "deletion_policy" {
  type        = string
  default     = ""
  description = "Optional Datastream deletion policy."
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Resource labels applied to Datastream resources."
}
