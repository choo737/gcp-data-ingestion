# Batch ELT Job Module

This module provisions a Cloud Run v2 batch loader, service account, and partitioned Bronze target table.

## Security Boundaries

- Grants `roles/storage.objectUser` only on `var.landing_bucket_name`.
- Grants `roles/bigquery.dataEditor` only on `var.bronze_dataset_id`, never Silver or Gold.
- Grants `roles/bigquery.jobUser` on `var.compute_project_id`.
- Derives unique service account IDs per `job_suffix`, or reuses `service_account_email` when supplied.
- Pre-creates `target_table` partitioned by `partition_field`, or uses ingestion-time `DAY` partitioning when empty.
- Sets `parallelism = 1` and optional Direct VPC egress (`vpc_id`, `subnet_id`, `vpc_egress`).
