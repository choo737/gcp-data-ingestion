data "google_project" "pubsub" {
  count = var.pubsub_project_number == "" ? 1 : 0

  project_id = var.project_id
}

locals {
  resource_prefix = trimsuffix(substr(lower(replace("${var.prefix}-${var.stream_name}", "_", "-")), 0, 64), "-")

  effective_pubsub_project_number = (
    var.pubsub_project_number != ""
    ? var.pubsub_project_number
    : data.google_project.pubsub[0].number
  )
  pubsub_service_agent_member  = "serviceAccount:service-${local.effective_pubsub_project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
  effective_pii_restricted_tag = var.pii_restricted_policy_tag_id != null ? trimspace(var.pii_restricted_policy_tag_id) : ""
  effective_pii_masked_tag     = var.pii_masked_policy_tag_id != null ? trimspace(var.pii_masked_policy_tag_id) : ""
  effective_writer_sa          = var.writer_service_account_email != null ? trimspace(var.writer_service_account_email) : ""

  default_proto_schema = <<-PROTO
    syntax = "proto3";
    message PosOrderEvent {
      string order_id = 1;
      string order_date = 2;
      string store_id = 3;
      string customer_id = 4;
      string customer_ic_number = 5;
      string country_code = 6;
      string currency_code = 7;
      string gross_amount = 8;
      string discount_amount = 9;
      string net_amount = 10;
      string order_status = 11;
      string updated_at = 12;
      bool _metadata_deleted = 13;
      string customer_email = 14;
      string tax_amount = 15;
    }
  PROTO

  default_avro_schema = jsonencode({
    type = "record"
    name = "PosOrderEvent"
    fields = [
      { name = "order_id", type = "string" },
      { name = "order_date", type = "string" },
      { name = "store_id", type = "string" },
      { name = "customer_id", type = "string" },
      { name = "customer_ic_number", type = "string" },
      { name = "customer_email", type = "string" },
      { name = "country_code", type = "string" },
      { name = "currency_code", type = "string" },
      { name = "gross_amount", type = "string" },
      { name = "discount_amount", type = "string" },
      { name = "tax_amount", type = "string" },
      { name = "net_amount", type = "string" },
      { name = "order_status", type = "string" },
      { name = "updated_at", type = "string" },
      { name = "_metadata_deleted", type = "boolean" },
    ]
  })

  effective_schema_definition = (
    var.schema_definition != ""
    ? var.schema_definition
    : (var.schema_type == "PROTOCOL_BUFFER" ? local.default_proto_schema : local.default_avro_schema)
  )

  default_target_schema_json = jsonencode([
    { name = "order_id", type = "STRING", mode = "NULLABLE", description = "Unique POS order identifier." },
    { name = "order_date", type = "DATE", mode = "NULLABLE", description = "Order calendar date." },
    { name = "store_id", type = "STRING", mode = "NULLABLE", description = "Retail store identifier." },
    { name = "customer_id", type = "STRING", mode = "NULLABLE", description = "Customer identifier." },
    merge(
      { name = "customer_ic_number", type = "STRING", mode = "NULLABLE", description = "Customer identity number." },
      local.effective_pii_restricted_tag != "" ? { policyTags = { names = [local.effective_pii_restricted_tag] } } : {}
    ),
    merge(
      { name = "customer_email", type = "STRING", mode = "NULLABLE", description = "Customer email address." },
      local.effective_pii_masked_tag != "" ? { policyTags = { names = [local.effective_pii_masked_tag] } } : {}
    ),
    { name = "country_code", type = "STRING", mode = "NULLABLE", description = "ISO country code." },
    { name = "currency_code", type = "STRING", mode = "NULLABLE", description = "ISO currency code." },
    { name = "gross_amount", type = "NUMERIC", mode = "NULLABLE", description = "Gross order amount." },
    { name = "discount_amount", type = "NUMERIC", mode = "NULLABLE", description = "Discount amount applied." },
    { name = "tax_amount", type = "NUMERIC", mode = "NULLABLE", description = "Tax amount applied." },
    { name = "net_amount", type = "NUMERIC", mode = "NULLABLE", description = "Net order amount." },
    { name = "order_status", type = "STRING", mode = "NULLABLE", description = "Order lifecycle status." },
    { name = "updated_at", type = "TIMESTAMP", mode = "NULLABLE", description = "Source event timestamp." },
    { name = "_metadata_deleted", type = "BOOL", mode = "NULLABLE", description = "Logical delete marker." },
    { name = "subscription_name", type = "STRING", mode = "NULLABLE", description = "Pub/Sub subscription metadata." },
    { name = "message_id", type = "STRING", mode = "NULLABLE", description = "Pub/Sub message ID." },
    { name = "publish_time", type = "TIMESTAMP", mode = "NULLABLE", description = "Pub/Sub publish timestamp." },
    { name = "attributes", type = "STRING", mode = "NULLABLE", description = "JSON-encoded Pub/Sub message attributes." },
  ])

  effective_target_schema_json = (
    var.target_table_schema_json != ""
    ? var.target_table_schema_json
    : local.default_target_schema_json
  )

  quarantine_schema_json = jsonencode([
    { name = "data", type = "STRING", mode = "NULLABLE", description = "Raw failed Pub/Sub payload." },
    { name = "subscription_name", type = "STRING", mode = "NULLABLE", description = "DLQ subscription name." },
    { name = "message_id", type = "STRING", mode = "NULLABLE", description = "Pub/Sub message ID." },
    { name = "publish_time", type = "TIMESTAMP", mode = "NULLABLE", description = "Pub/Sub publish timestamp." },
    { name = "attributes", type = "STRING", mode = "NULLABLE", description = "JSON-encoded dead-letter attributes." },
  ])
}

resource "google_pubsub_schema" "this" {
  project    = var.project_id
  name       = "${local.resource_prefix}-schema"
  type       = var.schema_type
  definition = local.effective_schema_definition
}

resource "google_pubsub_topic" "dlq" {
  project                    = var.project_id
  name                       = "${local.resource_prefix}-dlq"
  kms_key_name               = var.kms_key_id != "" ? var.kms_key_id : null
  message_retention_duration = var.message_retention_duration
  labels                     = var.labels

  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
}

resource "google_pubsub_topic" "primary" {
  project                    = var.project_id
  name                       = local.resource_prefix
  kms_key_name               = var.kms_key_id != "" ? var.kms_key_id : null
  message_retention_duration = var.message_retention_duration
  labels                     = var.labels

  schema_settings {
    schema   = google_pubsub_schema.this.id
    encoding = "JSON"
  }

  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
}

resource "google_pubsub_topic_iam_member" "writer_publisher" {
  count = local.effective_writer_sa != "" ? 1 : 0

  project = var.project_id
  topic   = google_pubsub_topic.primary.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${local.effective_writer_sa}"
}

resource "google_bigquery_table" "target" {
  project             = var.bronze_project_id
  dataset_id          = var.bronze_dataset_id
  table_id            = var.target_table_id
  description         = "Bronze streaming landing table populated by Pub/Sub BigQuery subscription."
  deletion_protection = !var.delete_contents_on_destroy
  clustering          = length(var.target_clustering) > 0 ? var.target_clustering : null
  schema              = local.effective_target_schema_json
  labels              = var.labels

  time_partitioning {
    type  = "DAY"
    field = "publish_time"
  }

  dynamic "encryption_configuration" {
    for_each = var.kms_key_id != "" ? [var.kms_key_id] : []
    content {
      kms_key_name = encryption_configuration.value
    }
  }
}

resource "google_bigquery_table" "quarantine" {
  project             = var.bronze_project_id
  dataset_id          = var.bronze_dataset_id
  table_id            = "${var.target_table_id}_quarantine"
  description         = "Quarantine table storing Pub/Sub dead-letter messages for SQL triage."
  deletion_protection = !var.delete_contents_on_destroy
  schema              = local.quarantine_schema_json
  labels              = var.labels

  time_partitioning {
    type  = "DAY"
    field = "publish_time"
  }

  dynamic "encryption_configuration" {
    for_each = var.kms_key_id != "" ? [var.kms_key_id] : []
    content {
      kms_key_name = encryption_configuration.value
    }
  }
}

resource "google_bigquery_table_iam_member" "pubsub_target_editor" {
  project    = var.bronze_project_id
  dataset_id = var.bronze_dataset_id
  table_id   = google_bigquery_table.target.table_id
  role       = "roles/bigquery.dataEditor"
  member     = local.pubsub_service_agent_member
}

resource "google_bigquery_table_iam_member" "pubsub_target_metadata" {
  project    = var.bronze_project_id
  dataset_id = var.bronze_dataset_id
  table_id   = google_bigquery_table.target.table_id
  role       = "roles/bigquery.metadataViewer"
  member     = local.pubsub_service_agent_member
}

resource "google_bigquery_table_iam_member" "pubsub_quarantine_editor" {
  project    = var.bronze_project_id
  dataset_id = var.bronze_dataset_id
  table_id   = google_bigquery_table.quarantine.table_id
  role       = "roles/bigquery.dataEditor"
  member     = local.pubsub_service_agent_member
}

resource "google_bigquery_table_iam_member" "pubsub_quarantine_metadata" {
  project    = var.bronze_project_id
  dataset_id = var.bronze_dataset_id
  table_id   = google_bigquery_table.quarantine.table_id
  role       = "roles/bigquery.metadataViewer"
  member     = local.pubsub_service_agent_member
}

resource "google_pubsub_topic_iam_member" "dlq_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.dlq.name
  role    = "roles/pubsub.publisher"
  member  = local.pubsub_service_agent_member
}

resource "google_pubsub_subscription" "primary" {
  project                    = var.project_id
  name                       = "${local.resource_prefix}-bq-sub"
  topic                      = google_pubsub_topic.primary.id
  ack_deadline_seconds       = 20
  message_retention_duration = var.message_retention_duration
  labels                     = var.labels

  bigquery_config {
    table               = "${var.bronze_project_id}.${var.bronze_dataset_id}.${google_bigquery_table.target.table_id}"
    use_table_schema    = true
    write_metadata      = true
    drop_unknown_fields = var.drop_unknown_fields
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dlq.id
    max_delivery_attempts = var.max_delivery_attempts
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "60s"
  }

  depends_on = [
    google_bigquery_table_iam_member.pubsub_target_editor,
    google_bigquery_table_iam_member.pubsub_target_metadata,
    google_pubsub_topic_iam_member.dlq_publisher,
  ]
}

resource "google_pubsub_subscription_iam_member" "primary_dlq_subscriber" {
  project      = var.project_id
  subscription = google_pubsub_subscription.primary.name
  role         = "roles/pubsub.subscriber"
  member       = local.pubsub_service_agent_member
}

resource "google_pubsub_subscription" "dlq_quarantine" {
  project                    = var.project_id
  name                       = "${local.resource_prefix}-dlq-bq-sub"
  topic                      = google_pubsub_topic.dlq.id
  ack_deadline_seconds       = 20
  message_retention_duration = var.message_retention_duration
  labels                     = var.labels

  bigquery_config {
    table            = "${var.bronze_project_id}.${var.bronze_dataset_id}.${google_bigquery_table.quarantine.table_id}"
    use_table_schema = false
    write_metadata   = true
  }

  depends_on = [
    google_bigquery_table_iam_member.pubsub_quarantine_editor,
    google_bigquery_table_iam_member.pubsub_quarantine_metadata,
  ]
}
