# Repository Agent Instructions

This repository holds Terraform modules, runnable stages, batch loader code, and Cloud Workflows definitions.

## Repository Layout

- `modules/ingestion/`: Reusable modules (`datastream-cdc`, `pubsub-bigquery`, `batch-elt-job`, `pipeline-workflows`).
- `schemas/`: Reusable Proto3/Avro definitions (`schemas/pubsub/`) and BigQuery JSON schemas (`schemas/bigquery/`).
- `stages/sandbox/`: Single-project stage with GCS backend and `.terraform.lock.hcl`.
- `stages/enterprise/`: Multi-project stage with `envs/{dev,staging,prod}.tfvars.example` and `.terraform.lock.hcl`.
- `jobs/gcs_to_bronze/`: Production Python `3.13` Cloud Run batch loader container with `requirements.lock`.
- `workflows/medallion_pipeline.workflows.yaml`: Parameterized Cloud Workflows GA `v1` pipeline definition.
- `composer_reference/medallion_composer3_dag.py`: Reference Airflow DAG for Cloud Composer 3 migrations.
- `scripts/link-stages.sh`: Links local or GCS `gcp-foundation` outputs (`--env`) into `00_linked.auto.tfvars.json`.
- `QUESTIONNAIRE.md`: Greenfield, Brownfield, and Sandbox intake questionnaire (standalone or via `platform-context.json`).
- `docs/03-enterprise-adoption-guide.md`: Step-by-step Day-0 to Day-2 enterprise multi-pipeline adoption guide.

## Interactive Setup Protocol

Always load `.agents/skills/setup-data-ingestion/SKILL.md` before deploying this repository for a customer.

1. **Create a private repo first**: Never fork publicly; run `gh repo create --private` and verify `isPrivate`.
2. **Collect intake inputs**: Check `platform-context.json` from [gcp-launchpad](https://github.com/choo737/gcp-launchpad) or walk through `QUESTIONNAIRE.md`.
3. **Verify GCP auth**: Check `gcloud config get-value account` or `GOOGLE_OAUTH_ACCESS_TOKEN`.
4. **Link Greenfield or Brownfield outputs**: Run `scripts/link-stages.sh --env <env>` or generate `00_linked.auto.tfvars.json` for Brownfield.
5. **Write inputs safely**: Save custom overrides in gitignored `custom.auto.tfvars` and passwords only in Secret Manager.
6. **Verify live ingestion**: Test Pub/Sub happy path, DLQ quarantine routing, and Cloud Workflows `pipeline_runs` telemetry.

## Hard Contracts

1. Every directory under `modules/ingestion/*` must contain only `README.md`, `main.tf`, `variables.tf`, `outputs.tf`, and `versions.tf`.
2. Every stage under `stages/*` must contain only those five files plus `terraform.tfvars.example` and `.terraform.lock.hcl`.
3. `stages/enterprise` also maintains `envs/{dev,staging,prod}.tfvars.example` for multi-environment configuration.
4. Every `versions.tf` must pin `required_version = ">= 1.8.0"` and `hashicorp/google` `version = ">= 8.0.0, < 9.0.0"`.
5. Never write `coalesce(..., "")` or `var.x != null && trimspace(var.x) != ""` in Terraform.
6. Never commit real GCP project IDs, org IDs, secrets, `*.tfstate*`, `custom.auto.tfvars`, or `00_linked.auto.tfvars.json`.
7. Keep prose sentences within `20` words without emojis, section symbols, or banned filler words.

## Verification Commands

```bash
make fmt-check
make validate
make test
```

## Available Repository Skills

- `.agents/skills/setup-data-ingestion/SKILL.md`
- `.agents/skills/add-batch-feed/SKILL.md`
- `.agents/skills/add-cdc-source/SKILL.md`
- `.agents/skills/add-streaming-topic/SKILL.md`
- `.agents/skills/split-domain-ingestion/SKILL.md`
