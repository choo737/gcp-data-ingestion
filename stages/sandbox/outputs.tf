output "landing_bucket_name" {
  value       = google_storage_bucket.landing.name
  description = "Sandbox GCS landing bucket name."
}

output "pubsub_topic_name" {
  value       = try(module.pubsub_bigquery[0].topic_name, "")
  description = "Primary Pub/Sub topic short name when streaming is enabled."
}

output "pubsub_topic_id" {
  value       = try(module.pubsub_bigquery[0].topic_id, "")
  description = "Primary Pub/Sub topic resource ID when streaming is enabled."
}

output "pubsub_target_table_id" {
  value       = try(module.pubsub_bigquery[0].target_table_id, "")
  description = "Qualified BigQuery target table receiving Pub/Sub events."
}

output "pubsub_quarantine_table_id" {
  value       = try(module.pubsub_bigquery[0].quarantine_table_id, "")
  description = "Qualified BigQuery quarantine table receiving DLQ events."
}

output "batch_job_name" {
  value       = try(module.batch_elt_job[0].job_name, "")
  description = "Cloud Run v2 batch loader job name when enabled."
}

output "datastream_stream_id" {
  value       = try(module.datastream_cdc[0].stream_id, "")
  description = "Datastream CDC stream resource ID when enabled."
}

output "workflow_id" {
  value       = try(module.pipeline_workflows[0].workflow_id, "")
  description = "Cloud Workflows resource ID when enabled."
}

output "workflow_name" {
  value       = try(module.pipeline_workflows[0].workflow_name, "")
  description = "Cloud Workflows short name when enabled."
}

output "alert_topic_id" {
  value       = try(module.pipeline_workflows[0].alert_topic_id, "")
  description = "Pub/Sub topic ID receiving pipeline failure alerts."
}

output "telemetry_table_id" {
  value       = try(module.pipeline_workflows[0].telemetry_table_id, "")
  description = "Qualified BigQuery pipeline_runs telemetry table ID."
}
