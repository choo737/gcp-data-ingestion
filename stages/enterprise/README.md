# Enterprise Ingestion Stage

This stage links upstream `gcp-foundation` enterprise outputs into multi-project ingestion tracks.

## Quickstart

```bash
../../scripts/link-stages.sh \
  ../../../gcp-foundation/foundation/02-security-network \
  ../../../gcp-foundation/data/enterprise/01-platform \
  ../../../gcp-foundation/data/enterprise/02-governance-ops \
  .
cp terraform.tfvars.example custom.auto.tfvars
terraform init
terraform plan
terraform apply
```

- Pull exported outputs across engineers with `./scripts/link-stages.sh --from-gcs gs://<bucket>/foundation-outputs.json stages/enterprise`.
- Keep `delete_contents_on_destroy = false` in production environments.
