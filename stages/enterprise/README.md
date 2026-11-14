# Enterprise Ingestion Stage

This stage links upstream `gcp-foundation` outputs into multi-project ingestion tracks across `dev`, `staging`, and `prod`.

## Quickstart

```bash
../../scripts/link-stages.sh --env dev \
  ../../../gcp-foundation/foundation/02-security-network \
  ../../../gcp-foundation/data/enterprise/01-platform \
  ../../../gcp-foundation/data/enterprise/02-governance-ops \
  .
cp envs/dev.tfvars.example envs/dev.tfvars
terraform init -backend-config="bucket=<tf-state-bucket>" -backend-config="prefix=ingestion/enterprise/dev"
terraform plan -var-file=envs/dev.tfvars
terraform apply -var-file=envs/dev.tfvars
```

- Pull exported outputs per environment using `--env <env> --from-gcs gs://<bucket>/foundation-outputs.json`.
- Add extra pipelines declaratively using `pubsub_streams`, `batch_jobs`, and `datastream_streams` inside `envs/<env>.tfvars`.
- Enable `enable_shared_datastream_private_connection = true` so multiple CDC streams reuse one PSC connection.
- Pass `pii_restricted_policy_tag_id` and `pii_masked_policy_tag_id` so Bronze tables enforce column tags.
- Keep `delete_contents_on_destroy = false` in `staging` and `prod` environments.
