output "job_id" {
  value       = google_cloud_run_v2_job.this.id
  description = "Full Cloud Run v2 job resource ID."
}

output "job_name" {
  value       = google_cloud_run_v2_job.this.name
  description = "Short Cloud Run v2 job name."
}

output "job_resource_path" {
  value       = "projects/${var.compute_project_id}/locations/${var.region}/jobs/${google_cloud_run_v2_job.this.name}"
  description = "Relative Cloud Run v2 job resource path used by Cloud Workflows."
}

output "service_account_email" {
  value       = local.effective_sa_email
  description = "Service account email attached to the batch loader job."
}

output "target_table_id" {
  value = (
    var.create_target_table
    ? "${var.bronze_project_id}.${var.bronze_dataset_id}.${google_bigquery_table.target[0].table_id}"
    : "${var.bronze_project_id}.${var.bronze_dataset_id}.${var.target_table}"
  )
  description = "Qualified BigQuery Bronze batch target table ID."
}
