---
name: add-cdc-source
description: Add a PostgreSQL or MySQL Datastream CDC stream using Secret Manager credentials and shared private connectivity.
---

# Add CDC Source

Use this workflow to connect a new operational PostgreSQL or MySQL database into Bronze via Datastream.

## 1. Store Replication Password in Secret Manager

Never write database passwords in `.tfvars` files or Terraform state.

```bash
printf '%s' "${DB_PASSWORD}" | gcloud secrets create "${PREFIX}-${STREAM_NAME}-db-pwd" \
  --project="${ETL_PROJECT}" \
  --replication-policy="user-managed" \
  --locations="${REGION}" \
  --data-file=-
```

Record the version path `projects/${ETL_PROJECT}/secrets/${PREFIX}-${STREAM_NAME}-db-pwd/versions/1`.

## 2. Declare CDC Stream in `stages/enterprise`

Add an entry to `datastream_streams` inside `stages/enterprise/envs/<env>.tfvars` instead of duplicating `module` blocks in `main.tf`.

```hcl
enable_shared_datastream_private_connection = true

datastream_streams = {
  erp-db = {
    source_engine              = "POSTGRESQL"
    db_host                    = "10.20.2.15"
    db_username                = "datastream_rep"
    db_database                = "erp_prod"
    db_password_secret_version = "projects/<etl-project>/secrets/ent-erp-db-pwd/versions/1"
    included_objects           = { public = ["invoices", "vendors"] }
    cdc_mode                   = "APPEND_ONLY"
  }
}
```

1. Enable `enable_shared_datastream_private_connection = true` so all CDC streams reuse one PSC or VPC private connection.
2. Set `source_engine` to `"POSTGRESQL"` or `"MYSQL"`, and pass `db_password_secret_version`.
3. Choose `cdc_mode = "APPEND_ONLY"` for Silver SCD Type 2 or `"MERGE"` for direct Bronze keys.
4. Only wire `modules/ingestion/datastream-cdc` directly in `stages/sandbox/main.tf` for single-project sandbox tests.

## 3. Validate and Deploy

```bash
make fmt-check
make validate
make test
```

Run `terraform plan` and `terraform apply` inside `stages/enterprise` or open a pull request.
