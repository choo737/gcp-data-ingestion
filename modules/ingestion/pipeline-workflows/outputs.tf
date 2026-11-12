output "workflow_id" {
  value       = google_workflows_workflow.this.id
  description = "Full Cloud Workflows resource ID."
}

output "workflow_name" {
  value       = google_workflows_workflow.this.name
  description = "Short Cloud Workflows name."
}

output "workflow_service_account_email" {
  value       = google_service_account.workflow.email
  description = "Dedicated runtime service account email attached to the Cloud Workflow."
}

output "trigger_service_account_email" {
  value       = try(google_service_account.trigger_invoker[0].email, "")
  description = "Minimal invoker service account email used by Cloud Scheduler and Eventarc."
}

output "alert_policy_id" {
  value       = try(google_monitoring_alert_policy.workflow_failure[0].id, "")
  description = "Cloud Monitoring alert policy ID when notification channels are set."
}

output "alert_topic_id" {
  value       = google_pubsub_topic.alerts.id
  description = "Full resource ID of the pipeline alert Pub/Sub topic."
}

output "telemetry_table_id" {
  value       = "${var.compute_project_id}.${var.ops_telemetry_dataset_id}.${google_bigquery_table.pipeline_runs.table_id}"
  description = "Qualified BigQuery table ID storing pipeline_runs telemetry."
}

output "scheduler_job_id" {
  value       = try(google_cloud_scheduler_job.this[0].id, "")
  description = "Cloud Scheduler job ID when enabled, or empty string."
}

output "eventarc_trigger_id" {
  value       = try(google_eventarc_trigger.gcs[0].id, try(google_eventarc_trigger.gcs_cross_project[0].id, ""))
  description = "Eventarc GCS trigger ID when enabled, or empty string."
}
