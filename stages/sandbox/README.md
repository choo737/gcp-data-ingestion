# Sandbox Ingestion Stage

This stage deploys ingestion tracks and Cloud Workflows into one existing sandbox project.

## Quickstart

```bash
../../scripts/link-stages.sh ../../../gcp-foundation/data/sandbox .
cp terraform.tfvars.example custom.auto.tfvars
terraform init -backend=false
terraform plan
terraform apply
```

- Supply `-backend-config` flags to `terraform init` when using a remote GCS state bucket.
- Lifecycle deletion on the landing bucket applies only to `incoming/`, keeping `quarantine/` forensics intact.
- Set `create_bronze_dataset = true` only when running without `gcp-foundation` upstream datasets.
- Set `delete_contents_on_destroy = true` only for temporary canary runs.
