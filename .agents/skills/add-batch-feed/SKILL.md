---
name: add-batch-feed
description: Add a declarative GCS-to-Bronze Cloud Run batch feed using batch_jobs and schemas/bigquery/ without editing main.tf.
---

# Add Batch Feed

Use this workflow to onboard a new GCS batch drop into BigQuery Bronze.

## 1. Add Table Schema Under `schemas/bigquery/`

1. Create `schemas/bigquery/<feed_name>_bronze.json` with `NULLABLE` BigQuery columns and optional `_ingested_at` metadata.
2. Pick a `DATE` or `TIMESTAMP` column for `partition_field`, or set `""` for ingestion-time `DAY` partitioning.
3. Choose up to four clustering columns in `target_clustering`, or leave `[]` when unneeded.

## 2. Declare Entry in `batch_jobs`

Add an entry inside `stages/enterprise/envs/<env>.tfvars` (never duplicate `module` blocks in `main.tf`):

```hcl
batch_jobs = {
  erp-invoices = {
    source_prefix            = "incoming/erp_invoices/"
    target_table             = "erp_invoices_bronze"
    source_format            = "NEWLINE_DELIMITED_JSON"
    partition_field          = "invoice_date"
    target_clustering        = ["entity_code", "invoice_status"]
    target_table_schema_file = "schemas/bigquery/erp_invoices_bronze.json"
  }
}
```

- Use a unique `source_prefix` per feed inside `landing_bucket_name`.
- Each key under `batch_jobs` derives an isolated service account ID, or accepts `service_account_email` for reuse.
- `container_image` defaults to the stage `batch_container_image` when omitted.

## 3. Register Declaration and Validate

1. Add a matching `type: "declaration"` SQLX file under `definitions/01_bronze/` in `gcp-data-medallion`.
2. Run local verification before opening a pull request:

```bash
make fmt-check
make validate
make test
```
