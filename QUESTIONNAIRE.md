# Data Ingestion Intake Questionnaire

Use this intake questionnaire to configure Tier-2 data ingestion for Greenfield, Brownfield, or Sandbox deployments.

You can complete this intake standalone or consume `platform-context.json` from [gcp-launchpad](https://github.com/choo737/gcp-launchpad).

Never commit real project IDs, KMS keys, dataset names, or database secrets to tracked files.

Record answers in `stages/enterprise/envs/<env>.tfvars`, `stages/sandbox/terraform.tfvars`, or gitignored `00_linked.auto.tfvars.json`.

---

## Section 1: Upstream Landing Zone Mode

Select one deployment mode before linking projects or editing stage variable files.

| Mode | Stage Directory | Upstream Source | Output File |
| --- | --- | --- | --- |
| Greenfield Enterprise | `stages/enterprise/` | `gcp-foundation` local state or GCS export | `stages/enterprise/00_linked.auto.tfvars.json` |
| Brownfield Enterprise | `stages/enterprise/` | Existing customer VPC, KMS, and BigQuery projects | `stages/enterprise/00_linked.auto.tfvars.json` |
| Single-Project Sandbox | `stages/sandbox/` | Existing project or `gcp-foundation/data/sandbox` | `stages/sandbox/terraform.tfvars` |

### Greenfield Enterprise Intake

Run `scripts/link-stages.sh` to export and import non-sensitive outputs from `gcp-foundation`.

```bash
./scripts/link-stages.sh --env dev \
  ../gcp-foundation/foundation/02-security-network \
  ../gcp-foundation/data/enterprise/01-platform \
  ../gcp-foundation/data/enterprise/02-governance-ops \
  stages/enterprise

# Or import outputs exported earlier to GCS:
./scripts/link-stages.sh --env dev --from-gcs gs://<outputs-bucket>/foundation-outputs.json stages/enterprise
```

### Brownfield Enterprise Intake (Without `gcp-foundation`)

Populate `stages/enterprise/00_linked.auto.tfvars.json` directly or run `gcp-launchpad/scripts/generate-brownfield-link.py` from `platform-context.json`.

| Variable Name | Requirement | Description | Stage Alias |
| --- | --- | --- | --- |
| `core_project_id` | Required | Project ID hosting Bronze and Silver storage | `core_storage_project_id` |
| `compute_project_id` | Required | Project ID hosting Workflows, Pub/Sub, Run, and Datastream | `etl_compute_project_id` |
| `analytics_project_id` | Optional | Gold analytics project ID (defaults to `compute_project_id`) | `primary_gold_project_id` |
| `bronze_dataset_id` | Required | Existing BigQuery Bronze landing dataset ID | — |
| `silver_dataset_id` | Optional | Existing BigQuery Silver dataset ID for Dataform | — |
| `gold_dataset_id` | Optional | Existing BigQuery Gold mart dataset ID | `primary_gold_dataset_id` |
| `quarantine_dataset_id` | Optional | Existing BigQuery quarantine dataset ID | — |
| `landing_bucket_name` | Required | Existing GCS raw landing bucket name | — |
| `dataform_repository_name` | Required | Dataform repository short name or path | — |
| `kms_key_id` | Optional | Regional Cloud KMS key ID for CMEK | `kms_key_name` |
| `vpc_id` | Optional | Existing VPC network resource ID | `network_id` |
| `subnet_id` | Optional | Existing subnetwork ID for Cloud Run egress | — |
| `pii_restricted_policy_tag_id` | Optional | Policy tag ID for `customer_ic_number` | — |
| `pii_masked_policy_tag_id` | Optional | Policy tag ID for `customer_email` | — |

Optional brownfield links also supported in `00_linked.auto.tfvars.json`:

- `assertions_dataset_id` and `ops_telemetry_dataset_id` for Dataform assertions and workflow run logs.
- `dataform_release_config_name` (or `dataform_release_config_id`) and `dataform_service_account_email` (or `dataform_sa_email`).
- `artifact_registry_repository_uri`, `dataplex_profile_scan_id`, `dataplex_quality_scan_id`, and `dataplex_scan_names`.
- `datastream_network_attachment_id`, `pubsub_writer_sa_email`, and `batch_loader_sa_email`.

### Single-Project Sandbox Intake

Set these variables in `stages/sandbox/terraform.tfvars` or gitignored `stages/sandbox/custom.auto.tfvars`:

| Variable Name | Default | Description |
| --- | --- | --- |
| `project_id` | Required | Existing single sandbox GCP project ID |
| `region` | `asia-southeast1` | GCP region for ingestion and BigQuery resources |
| `prefix` | `bqfnd` | Resource prefix (`3-16` lowercase chars or hyphens) |
| `create_bronze_dataset` | `false` | Set `true` only without upstream foundation datasets |
| `create_ops_telemetry_dataset` | `true` | Auto-creates `ops_telemetry` dataset when ID is empty |

---

## Section 2: Active Ingestion Patterns

Enable or disable each ingestion path independently inside `stages/enterprise/envs/<env>.tfvars` or `stages/sandbox/terraform.tfvars`.

| Pattern | Toggle Variable | Key Configuration Variables | Notes |
| --- | --- | --- | --- |
| Datastream CDC | `enable_datastream_cdc` | `datastream_source_engine`, `datastream_db_host`, `datastream_db_port`, `datastream_db_username`, `datastream_db_database`, `datastream_cdc_mode` | Engine `POSTGRESQL` or `MYSQL`; mode `APPEND_ONLY` or `MERGE` |
| Pub/Sub Streaming | `enable_pubsub_stream` | `pubsub_schema_type`, `pubsub_target_table_id`, `pubsub_writer_sa_email` | Schema `PROTOCOL_BUFFER` or `AVRO`; auto-creates `*_quarantine` |
| GCS Batch Loader | `enable_batch_job` | `batch_container_image`, `batch_image_tag`, `batch_source_prefix`, `batch_target_table`, `batch_source_format` | Formats: `NEWLINE_DELIMITED_JSON`, `CSV`, `PARQUET` |

Confirm these pattern-specific choices with the customer:

- **Multi-Pipeline Enterprise Catalogs**: Add extra feeds via `pubsub_streams`, `batch_jobs`, and `datastream_streams` with `schemas/`.
- **Shared Datastream Private Connection**: Set `enable_shared_datastream_private_connection = true` so multiple CDC streams share one PSC attachment.
- **Datastream CDC**: Choose `POSTGRESQL` (`postgresql_publication`, `postgresql_replication_slot`) or `MYSQL` (GTID binlog), plus `backfill_mode` (`ALL` or `NONE`).
- **Datastream Validation**: Set `datastream_create_without_validation = false` in production and `true` only for offline sandboxes.
- **Pub/Sub DLQ Retention**: Module defaults `message_retention_duration` to `604800s` (seven days) and `max_delivery_attempts` to `5`.
- **Batch Container Image**: Provide immutable `@sha256` `batch_container_image`, or combine `artifact_registry_repository_uri` with `batch_image_tag`.
- **Batch Quarantine**: Failing files move to `quarantine/` in `landing_bucket_name` alongside `.error.json` metadata.

---

## Section 3: Network Connectivity, CMEK & Secret Security

Verify private connectivity, encryption keys, and secret paths before running `terraform plan`.

| Control Area | Variables | Recommended Setting |
| --- | --- | --- |
| Datastream Private Connectivity | `datastream_create_private_connection`, `datastream_network_attachment_id`, `datastream_peering_cidr` | Prefer PSC `datastream_network_attachment_id`; use `/29` CIDR for peering |
| Cloud Run Direct VPC Egress | `vpc_id`, `subnet_id`, `batch_vpc_egress` | Use `PRIVATE_RANGES_ONLY` in dev; `ALL_TRAFFIC` for strict egress control |
| Regional Cloud KMS CMEK | `kms_key_id` (or `kms_key_name`) | Regional KMS key matching `var.region` (`asia-southeast1`) |
| Database Password Secret | `datastream_db_password_secret_version` | Format `projects/<project>/secrets/<secret>/versions/<version>` |

Security rules enforced by Terraform and tests:

- Store database passwords only in regional Secret Manager, never inside `.tfvars` or JSON files.
- Use `batch_vpc_egress = "ALL_TRAFFIC"` when FSI or RMiT rules require full egress firewall inspection.

---

## Section 4: Orchestration, Schedule & Alerting

Choose serverless Cloud Workflows triggers or optional Cloud Composer 3 migration settings.

| Setting | Variable Name | Default / Example | Guidance |
| --- | --- | --- | --- |
| Pipeline Workflow | `enable_pipeline_workflow` | `true` | Provisions Cloud Workflows GA `v1` and `ops_telemetry` table |
| Scheduler Toggle | `enable_schedule` | `false` (`dev`), `true` (`prod`) | Provisions Cloud Scheduler trigger for the workflow |
| Schedule Cron | `schedule_cron` | `"0 2 * * *"` | Standard cron expression for batch and Dataform runs |
| Schedule Time Zone | `schedule_time_zone` (module) | `"Asia/Kuala_Lumpur"` | Module `pipeline-workflows` default; override in module call if needed |
| GCS Eventarc Trigger | `enable_gcs_eventarc_trigger` | `false` (`dev`), `true` (`prod`) | Triggers workflow when files land under `incoming/` |
| Composer 3 DAG | `composer_reference/medallion_composer3_dag.py` | Manual DAG deployment | Deploy to Composer 3; set `enable_pipeline_workflow = false` if replacing |
| Deletion Protection | `delete_contents_on_destroy` | `false` | Keep `false` in `staging` and `prod` |
| Alert Emails | `alert_email_addresses` | `["ops@example.com"]` | Creates same-project Cloud Monitoring email channels |
| Existing Channels | `notification_channel_ids` | `[]` | Reuses existing Cloud Monitoring notification channel IDs |
