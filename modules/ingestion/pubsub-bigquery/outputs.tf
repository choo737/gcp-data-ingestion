output "schema_id" {
  value       = google_pubsub_schema.this.id
  description = "Full resource ID of the Pub/Sub schema."
}

output "topic_name" {
  value       = google_pubsub_topic.primary.name
  description = "Short name of the primary Pub/Sub topic."
}

output "topic_id" {
  value       = google_pubsub_topic.primary.id
  description = "Full resource ID of the primary Pub/Sub topic."
}

output "dlq_topic_id" {
  value       = google_pubsub_topic.dlq.id
  description = "Full resource ID of the dead-letter Pub/Sub topic."
}

output "subscription_id" {
  value       = google_pubsub_subscription.primary.id
  description = "Full resource ID of the primary BigQuery subscription."
}

output "quarantine_subscription_id" {
  value       = google_pubsub_subscription.dlq_quarantine.id
  description = "Full resource ID of the DLQ quarantine BigQuery subscription."
}

output "target_table_id" {
  value       = "${var.bronze_project_id}.${var.bronze_dataset_id}.${google_bigquery_table.target.table_id}"
  description = "Qualified BigQuery target table ID."
}

output "quarantine_table_id" {
  value       = "${var.bronze_project_id}.${var.bronze_dataset_id}.${google_bigquery_table.quarantine.table_id}"
  description = "Qualified BigQuery quarantine table ID."
}
