# Repository Agent Instructions

This repository holds Terraform modules, runnable stages, batch loader code, and Cloud Workflows definitions.

## Repository Layout

- `modules/ingestion/`: Reusable modules (`datastream-cdc`, `pubsub-bigquery`, `batch-elt-job`, `pipeline-workflows`).
- `stages/sandbox/`: Single-project deployment stage compatible with `gcp-foundation/data/sandbox`.
- `stages/enterprise/`: Multi-project deployment stage linked from `gcp-foundation` enterprise outputs.
- `jobs/gcs_to_bronze/`: Production Python `3.13` Cloud Run batch loader container.
- `workflows/medallion_pipeline.workflows.yaml`: Parameterized Cloud Workflows pipeline definition.
- `composer_reference/medallion_composer3_dag.py`: Reference Airflow DAG for Cloud Composer 3 migrations.
- `scripts/link-stages.sh`: Links local or GCS-exported `gcp-foundation` outputs into `00_linked.auto.tfvars.json`.

## Interactive Setup Protocol

Always load `.agents/skills/setup-data-ingestion/SKILL.md` before deploying this repository for a customer.

1. **Create a private repo first**: Never fork publicly; run `gh repo create --private` and verify `isPrivate`.
2. **Ask the user first**: Never guess project IDs, dataset IDs, KMS keys, database hosts, or secrets.
3. **Verify GCP auth**: Check `gcloud config get-value account` or `GOOGLE_OAUTH_ACCESS_TOKEN`.
4. **Link upstream foundation outputs**: Run `scripts/link-stages.sh` to generate gitignored `00_linked.auto.tfvars.json`.
5. **Write inputs safely**: Save custom overrides in gitignored `custom.auto.tfvars` and passwords only in Secret Manager.
6. **Verify live ingestion**: Test Pub/Sub happy path, DLQ quarantine routing, and Cloud Workflows `pipeline_runs` telemetry.

## Hard Contracts

1. Every directory under `modules/ingestion/*` must contain only `README.md`, `main.tf`, `variables.tf`, `outputs.tf`, and `versions.tf`.
2. Every stage under `stages/*` must contain only those five files plus `terraform.tfvars.example`.
3. Every `versions.tf` must pin `required_version = ">= 1.8.0"` and `hashicorp/google` `version = ">= 8.0.0, < 9.0.0"`.
4. Never use `coalesce(..., "")` in Terraform.
5. Never commit real GCP project IDs, org IDs, secrets, `*.tfstate*`, `custom.auto.tfvars`, or `00_linked.auto.tfvars.json`.
6. Keep prose sentences within `20` words without emojis, section symbols, or banned filler words.

## Verification Commands

```bash
make fmt-check
make validate
make test
```

## Available Repository Skills

- `.agents/skills/setup-data-ingestion/SKILL.md`
- `.agents/skills/add-cdc-source/SKILL.md`
- `.agents/skills/add-streaming-topic/SKILL.md`
- `.agents/skills/split-domain-ingestion/SKILL.md`
