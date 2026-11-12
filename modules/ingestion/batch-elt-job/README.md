# Batch ELT Job Module

This module provisions a Cloud Run v2 batch loader job and its dedicated service account.

## Security Boundaries

- Grants `roles/storage.objectUser` only on `var.landing_bucket_name`.
- Grants `roles/bigquery.dataEditor` only on `var.bronze_dataset_id`, never Silver or Gold.
- Grants `roles/bigquery.jobUser` on `var.compute_project_id`.
- Passes target dataset, bucket, format, and CMEK parameters via environment variables.
