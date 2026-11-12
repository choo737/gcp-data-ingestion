---
name: add-cdc-source
description: Add a PostgreSQL or MySQL Datastream CDC stream using Secret Manager credentials and private connectivity.
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

## 2. Configure the Datastream Module

1. Instantiate `modules/ingestion/datastream-cdc` inside `stages/enterprise/main.tf` or `stages/sandbox/main.tf`.
2. Set `source_engine` to `"POSTGRESQL"` or `"MYSQL"`.
3. Pass `db_password_secret_version` with the Secret Manager version path.
4. Set `create_private_connection = true` and supply `network_attachment` or `vpc_id` plus `peering_cidr`.
5. Choose `cdc_mode = "APPEND_ONLY"` for Silver SCD Type 2 or `"MERGE"` for direct Bronze keys.

## 3. Validate and Deploy

```bash
make fmt-check
make validate
make test
```

Run `terraform plan` and `terraform apply` inside the target stage directory.
