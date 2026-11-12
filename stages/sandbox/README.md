# Sandbox Ingestion Stage

This stage deploys ingestion tracks and Cloud Workflows into one existing sandbox project.

## Quickstart

```bash
../../scripts/link-stages.sh ../../../gcp-foundation/data/sandbox .
cp terraform.tfvars.example custom.auto.tfvars
terraform init
terraform plan
terraform apply
```

- Set `create_bronze_dataset = true` only when running without `gcp-foundation` upstream datasets.
- Set `delete_contents_on_destroy = true` only for temporary canary runs.
