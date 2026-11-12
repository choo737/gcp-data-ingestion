# Batch ELT Job Module

This module provisions a Cloud Run v2 batch loader, service account, and partitioned Bronze target table.

## Security Boundaries

- Grants `roles/storage.objectUser` only on `var.landing_bucket_name`.
- Grants `roles/bigquery.dataEditor` only on `var.bronze_dataset_id`, never Silver or Gold.
- Grants `roles/bigquery.jobUser` on `var.compute_project_id`.
- Pre-creates `pos_orders_batch_cdc` partitioned by `order_date` with optional PII policy tags.
- Sets `parallelism = 1` and optional Direct VPC egress (`vpc_id`, `subnet_id`, `vpc_egress`).
