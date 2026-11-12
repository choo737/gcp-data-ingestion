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
  value       = google_service_account.batch_loader.email
  description = "Dedicated service account email attached to the batch loader job."
}
