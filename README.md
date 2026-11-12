# GCP Data Ingestion

This repository deploys Google Cloud ingestion pipelines and Cloud Workflows runners for Bronze landing zones.

It pairs with [gcp-foundation](https://github.com/choo737/gcp-foundation) and [gcp-data-medallion](https://github.com/choo737/gcp-data-medallion).

## Create Your Private Repository (Do Not Fork Publicly)

- GitHub forces normal forks of public repositories to stay public.
- Click **Use this template** on GitHub or run this command:

```bash
gh repo create acme-corp/gcp-data-ingestion --private --template choo737/gcp-data-ingestion --clone
```

## Three-Repository Suite

| Repository | Layer | Responsibility |
| --- | --- | --- |
| [gcp-foundation](https://github.com/choo737/gcp-foundation) | Platform & Governance | Org guardrails, projects, KMS, datasets, Dataform repo, and Dataplex scans |
| [gcp-data-ingestion](https://github.com/choo737/gcp-data-ingestion) | Ingestion & Workflow Runner | Datastream CDC, Pub/Sub streaming, GCS batch loader, and Cloud Workflows |
| [gcp-data-medallion](https://github.com/choo737/gcp-data-medallion) | Warehouse & Quality | Bronze declarations, Silver SCD Type 2, Gold marts, and quality specs |

## Ingestion Tracks and Pipeline Runner

1. **Datastream CDC (`modules/ingestion/datastream-cdc`)**: Streams PostgreSQL or MySQL changes into Bronze using Secret Manager passwords.
2. **Pub/Sub to BigQuery (`modules/ingestion/pubsub-bigquery`)**: Validates JSON payloads via topic schemas and routes failures to quarantine tables.
3. **Batch ELT Job (`modules/ingestion/batch-elt-job` + `jobs/gcs_to_bronze/`)**: Runs idempotent Cloud Run loads with BigQuery watermark deduplication.
4. **Pipeline Workflows (`modules/ingestion/pipeline-workflows` + `workflows/`)**: Triggers batch loads, Dataform runs, Dataplex scans, telemetry, and alerts.

## Day 1 Alice to Day 10 Bob Handoff Walkthrough

Alice deploys `gcp-foundation` on Day 1 and exports non-sensitive outputs to a secure GCS bucket.

```bash
# Day 1 (Alice in gcp-foundation): export non-sensitive stage outputs to GCS.
./scripts/link-stages.sh --export-gcs gs://example-platform-state/foundation-outputs.json \
  foundation/02-security-network \
  data/enterprise/01-platform \
  data/enterprise/02-governance-ops
```

Bob joins on Day 10 with no local state files from Alice's laptop.

```bash
# Day 10 (Bob in gcp-data-ingestion): pull exported outputs into 00_linked.auto.tfvars.json.
./scripts/link-stages.sh --from-gcs \
  gs://example-platform-state/foundation-outputs.json \
  stages/enterprise

cp stages/enterprise/terraform.tfvars.example stages/enterprise/custom.auto.tfvars
terraform -chdir=stages/enterprise init
terraform -chdir=stages/enterprise apply
```

- When running both repositories on one workstation, pass local stage paths instead of GCS URIs.
- `scripts/link-stages.sh` filters outputs to declared variables in `variables.tf` and writes `00_linked.auto.tfvars.json` (`0600`).

## Repository Layout

- `modules/ingestion/`: Reusable five-file Terraform modules (`datastream-cdc`, `pubsub-bigquery`, `batch-elt-job`, `pipeline-workflows`).
- `stages/sandbox/`: Single-project stage compatible with `gcp-foundation/data/sandbox` outputs.
- `stages/enterprise/`: Multi-project stage consuming `00_linked.auto.tfvars.json` from `gcp-foundation`.
- `jobs/gcs_to_bronze/`: Python `3.13` Cloud Run batch loader container and dependencies.
- `workflows/`: Cloud Workflows YAML definition (`medallion_pipeline.workflows.yaml`).
- `composer_reference/`: Reference Airflow DAG (`medallion_composer3_dag.py`) for Cloud Composer 3 scaling.
- `scripts/link-stages.sh`: Local and GCS stage output linker.

## Quick Verification

```bash
make fmt-check
make validate
make test
```

## Documentation Index

- [Ingestion Decision Guide](docs/01-ingestion-decision-guide.md)
- [Repository Scaling and Composer Guide](docs/02-repo-scaling-and-composer.md)
