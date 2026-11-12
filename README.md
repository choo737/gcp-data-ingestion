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

1. **Datastream CDC (`modules/ingestion/datastream-cdc`)**: Streams PostgreSQL or MySQL changes using Secret Manager passwords and PSC or peering.
2. **Pub/Sub to BigQuery (`modules/ingestion/pubsub-bigquery`)**: Validates JSON events, applies PII policy tags, and routes errors to quarantine.
3. **Batch ELT Job (`modules/ingestion/batch-elt-job` + `jobs/gcs_to_bronze/`)**: Runs atomic Cloud Run loads with Direct VPC egress and policy-tagged tables.
4. **Pipeline Workflows (`modules/ingestion/pipeline-workflows` + `workflows/`)**: Triggers batch loads, Dataform GA `v1` runs, Dataplex scans, telemetry, and alerts.

## Multi-Environment Deployment and Handoff

Alice exports non-sensitive foundation outputs per environment to GCS on Day 1.

```bash
# Day 1 (Alice in gcp-foundation): export dev, staging, or prod outputs.
./scripts/link-stages.sh --env prod --export-gcs gs://example-platform-state/foundation-outputs.json \
  foundation/02-security-network \
  data/enterprise/01-platform \
  data/enterprise/02-governance-ops
```

Bob links outputs into `stages/enterprise` and initializes remote GCS state on Day 10.

```bash
# Day 10 (Bob in gcp-data-ingestion): pull environment outputs and apply.
./scripts/link-stages.sh --env prod --from-gcs \
  gs://example-platform-state/foundation-outputs.json \
  stages/enterprise

cp stages/enterprise/envs/prod.tfvars.example stages/enterprise/envs/prod.tfvars
make init STAGE=enterprise ENV=prod TF_STATE_BUCKET=example-tf-state-bucket
make plan STAGE=enterprise ENV=prod
make apply STAGE=enterprise ENV=prod
```

- Pass local stage directories to `scripts/link-stages.sh` when running all repositories on one machine.
- `scripts/link-stages.sh` filters declared variables and writes `00_linked.auto.tfvars.json` (`0600`).
- Commit `.terraform.lock.hcl` for `linux_amd64` and `darwin_arm64` in both stages.

## CI/CD Workflows

- `.github/workflows/ci.yml`: Runs formatting, `terraform validate`, and Python unit tests on every push and PR.
- `.github/workflows/build-batch-loader.yml`: Builds `jobs/gcs_to_bronze` with locked hashes and pushes immutable digests when WIF is set.
- `.github/workflows/terraform-deploy.yml`: Plans pull requests and promotes `dev`, `staging`, and `prod` via GitHub Environments.

## Repository Layout

- `modules/ingestion/`: Reusable five-file Terraform modules (`datastream-cdc`, `pubsub-bigquery`, `batch-elt-job`, `pipeline-workflows`).
- `stages/sandbox/`: Single-project stage with GCS remote backend and committed `.terraform.lock.hcl`.
- `stages/enterprise/`: Multi-project stage with `envs/{dev,staging,prod}.tfvars.example` and committed `.terraform.lock.hcl`.
- `jobs/gcs_to_bronze/`: Python `3.13` Cloud Run batch loader with pinned digest base image and `requirements.lock`.
- `workflows/`: Cloud Workflows GA `v1` pipeline definition (`medallion_pipeline.workflows.yaml`).
- `composer_reference/`: Reference Airflow DAG (`medallion_composer3_dag.py`) for Cloud Composer 3 scaling.
- `scripts/link-stages.sh`: Local and GCS stage output linker supporting `--env`.

## Quick Verification

```bash
make fmt-check
make validate
make test
```

## Documentation Index

- [Ingestion Decision Guide](docs/01-ingestion-decision-guide.md)
- [Repository Scaling and Composer Guide](docs/02-repo-scaling-and-composer.md)
