variable "project_id" {
  type        = string
  description = "GCP project ID hosting the Pub/Sub schema, topics, and subscriptions."
}

variable "region" {
  type        = string
  default     = "asia-southeast1"
  description = "GCP region pinned in Pub/Sub message storage policy."
}

variable "prefix" {
  type        = string
  description = "Short lowercase prefix applied to Pub/Sub resources."
}

variable "stream_name" {
  type        = string
  default     = "pos-orders"
  description = "Stream suffix used to name the primary topic, DLQ topic, and subscriptions."
}

variable "bronze_project_id" {
  type        = string
  description = "Target BigQuery project ID hosting the Bronze dataset."
}

variable "bronze_dataset_id" {
  type        = string
  description = "Target BigQuery Bronze dataset ID."
}

variable "pubsub_project_number" {
  type        = string
  default     = ""
  description = "Optional numeric project number for the Pub/Sub service agent."
}

variable "target_table_id" {
  type        = string
  default     = "pos_orders_stream_cdc"
  description = "BigQuery target table ID receiving streamed events."
}

variable "schema_type" {
  type        = string
  default     = "PROTOCOL_BUFFER"
  description = "Pub/Sub schema definition type: PROTOCOL_BUFFER or AVRO."

  validation {
    condition     = contains(["PROTOCOL_BUFFER", "AVRO"], var.schema_type)
    error_message = "schema_type must be PROTOCOL_BUFFER or AVRO."
  }
}

variable "schema_definition" {
  type        = string
  default     = ""
  description = "Optional custom Pub/Sub schema definition string."
}

variable "target_table_schema_json" {
  type        = string
  default     = ""
  description = "Optional custom BigQuery table JSON schema matching the target event payload."
}

variable "target_clustering" {
  type        = list(string)
  default     = ["store_id", "customer_id"]
  description = "Clustering columns applied to the partitioned target BigQuery table."
}

variable "drop_unknown_fields" {
  type        = bool
  default     = false
  description = "Whether Pub/Sub drops unknown JSON fields instead of sending failed messages to DLQ."
}

variable "max_delivery_attempts" {
  type        = number
  default     = 5
  description = "Maximum delivery attempts before Pub/Sub routes failed messages to the DLQ."

  validation {
    condition     = var.max_delivery_attempts >= 5 && var.max_delivery_attempts <= 100
    error_message = "max_delivery_attempts must be between 5 and 100."
  }
}

variable "message_retention_duration" {
  type        = string
  default     = "604800s"
  description = "Message retention duration on Pub/Sub topics and subscriptions."
}

variable "kms_key_id" {
  type        = string
  default     = ""
  description = "Optional regional Cloud KMS crypto key ID for Pub/Sub topics and BigQuery tables."
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

variable "writer_service_account_email" {
  type        = string
  default     = ""
  description = "Optional publisher service account email granted roles/pubsub.publisher on the primary topic."
}

variable "delete_contents_on_destroy" {
  type        = bool
  default     = false
  description = "Whether Terraform destroy may delete the Bronze target and quarantine BigQuery tables."
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Resource labels applied to Pub/Sub and BigQuery resources."
}
