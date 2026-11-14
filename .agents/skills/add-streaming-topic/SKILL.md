---
name: add-streaming-topic
description: Add a schema-validated Pub/Sub BigQuery subscription and quarantine table declaratively via pubsub_streams and schemas/.
---

# Add Streaming Topic

Use this workflow to add a new Pub/Sub topic streaming JSON events straight into BigQuery Bronze.

## 1. Define Schema and Table Columns Under `schemas/`

1. Save a `PROTOCOL_BUFFER` (`proto3`) or `AVRO` schema under `schemas/pubsub/<stream_name>.proto`.
2. Save the matching BigQuery JSON schema under `schemas/bigquery/<stream_name>_bronze.json` with `NULLABLE` columns.
3. Include metadata columns `subscription_name`, `message_id`, `publish_time`, and `attributes` in the BigQuery JSON schema.
4. Confirm `target_table_id` stays unique within `bronze_dataset_id`.

## 2. Declare Stream in `pubsub_streams`

Add an entry to `pubsub_streams` inside `stages/enterprise/envs/<env>.tfvars` without editing `main.tf`:

```hcl
pubsub_streams = {
  crm-events = {
    target_table_id          = "crm_events_stream"
    schema_type              = "PROTOCOL_BUFFER"
    schema_file              = "schemas/pubsub/crm_events.proto"
    target_table_schema_file = "schemas/bigquery/crm_events_bronze.json"
    target_clustering        = ["segment", "event_type"]
  }
}
```

- Keep `drop_unknown_fields = false` so invalid payloads route cleanly into `${target_table_id}_quarantine`.
- Only wire `modules/ingestion/pubsub-bigquery` directly inside `stages/sandbox/main.tf` for standalone sandbox tests.

## 3. Register Declaration in `gcp-data-medallion`

1. Add a matching `type: "declaration"` SQLX file under `definitions/01_bronze/` in `gcp-data-medallion`.
2. Verify both repositories pass local validation:

```bash
make fmt-check
make validate
make test
```
