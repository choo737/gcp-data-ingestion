---
name: setup-data-ingestion
description: Interactive onboarding workflow covering private repo creation, foundation stage linking, Terraform deployment, live canary verification, and teardown.
---

# Setup Data Ingestion

Run these steps in order whenever deploying this repository for a customer or test run.

## Step 0: Create a Private Customer Repository

GitHub keeps standard `gh repo fork` clones public.

Never store customer configuration inside a public fork.

```bash
gh repo create <owner>/<customer-repo> --private --template choo737/gcp-data-ingestion --clone
cd <customer-repo>
gh repo view --json isPrivate --jq '.isPrivate'
```

Confirm the final command prints `true`.

## Step 1: Collect Customer Inputs First

Never guess project IDs, dataset names, KMS keys, or database credentials.

Ask the customer to select one stage and environment:

1. **Sandbox (`stages/sandbox/`)**: Single GCP project matching `gcp-foundation/data/sandbox`.
2. **Enterprise (`stages/enterprise/`)**: Multi-project layout with `envs/{dev,staging,prod}.tfvars.example`.

Confirm these inputs before editing `envs/<env>.tfvars` or `custom.auto.tfvars`:

- `environment`, `region` (default `asia-southeast1`), `prefix`, and `delete_contents_on_destroy`.
- Active tracks: `enable_pubsub_stream`, `enable_batch_job`, `enable_datastream_cdc`, `enable_pipeline_workflow`.
- Batch image digest URI (`batch_container_image`) and `batch_vpc_egress` when `enable_batch_job = true`.
- Secret Manager version (`datastream_db_password_secret_version`) and PSC or peering inputs when `enable_datastream_cdc = true`.

## Step 2: Link Upstream Foundation Outputs and Check Auth

Verify active `gcloud` credentials before running Terraform:

```bash
gcloud config get-value account
```

For named `gcloud` configurations without ADC, export a short-lived access token:

```bash
export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token --configuration=<config_name>)
```

Link outputs from local `gcp-foundation` stages or from GCS into `00_linked.auto.tfvars.json`:

```bash
# Local single-project sandbox linking:
./scripts/link-stages.sh ../gcp-foundation/data/sandbox stages/sandbox

# Local multi-environment enterprise linking:
./scripts/link-stages.sh --env dev \
  ../gcp-foundation/foundation/02-security-network \
  ../gcp-foundation/data/enterprise/01-platform \
  ../gcp-foundation/data/enterprise/02-governance-ops \
  stages/enterprise

# Or pull environment outputs exported earlier to GCS:
./scripts/link-stages.sh --env dev --from-gcs gs://<outputs-bucket>/foundation-outputs.json stages/enterprise
```

Write customer overrides only into gitignored `custom.auto.tfvars` or untracked `envs/<env>.tfvars`.

## Step 3: Deploy with Terraform

Initialize the GCS remote backend and run `plan` and `apply`:

```bash
make init STAGE=enterprise ENV=dev TF_STATE_BUCKET=<tf-state-bucket>
make plan STAGE=enterprise ENV=dev
make apply STAGE=enterprise ENV=dev
```

## Step 4: Verify Live Pub/Sub, DLQ Quarantine, and Cloud Workflows

Publish one valid JSON order event and confirm it lands in BigQuery:

```bash
gcloud pubsub topics publish "${TOPIC_NAME}" --project="${ETL_PROJECT}" \
  --message='{"order_id":"ord-canary-1","order_date":"2026-11-12","store_id":"st-01","customer_id":"cust-01","customer_ic_number":"900101145566","customer_email":"canary@example.com","country_code":"MY","currency_code":"MYR","gross_amount":"120.00","discount_amount":"10.00","tax_amount":"6.60","net_amount":"110.00","order_status":"COMPLETED","updated_at":"2026-11-12T01:00:00Z","_metadata_deleted":false}'

bq query --use_legacy_sql=false --project_id="${ETL_PROJECT}" \
  "SELECT order_id, order_date, net_amount, message_id FROM \`${BRONZE_PROJECT}.${BRONZE_DATASET}.pos_orders_stream_cdc\` ORDER BY publish_time DESC LIMIT 5"
```

Publish one type-invalid message to verify dead-letter quarantine routing:

```bash
gcloud pubsub topics publish "${TOPIC_NAME}" --project="${ETL_PROJECT}" \
  --message='{"order_id":"ord-bad-1","order_date":"INVALID_DATE","store_id":"st-01"}'

bq query --use_legacy_sql=false --project_id="${ETL_PROJECT}" \
  "SELECT data, message_id, publish_time FROM \`${BRONZE_PROJECT}.${BRONZE_DATASET}.pos_orders_stream_cdc_quarantine\` ORDER BY publish_time DESC LIMIT 5"
```

Execute the Cloud Workflow and verify telemetry in `ops_telemetry.pipeline_runs`:

```bash
gcloud workflows run "${WORKFLOW_NAME}" --project="${ETL_PROJECT}" --location="${REGION}" \
  --data='{"run_batch_job": false, "run_dataplex_scan": true}'

bq query --use_legacy_sql=false --project_id="${ETL_PROJECT}" \
  "SELECT execution_id, status, invocation_name, recorded_at FROM \`${ETL_PROJECT}.${OPS_TELEMETRY_DATASET}.pipeline_runs\` ORDER BY recorded_at DESC LIMIT 5"
```

## Step 5: Safe Two-Step Teardown

1. Set `delete_contents_on_destroy = true` in overrides and run `terraform apply`.
2. Run `terraform destroy` inside `stages/enterprise` or `stages/sandbox` before destroying `gcp-foundation`.
