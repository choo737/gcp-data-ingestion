---
name: add-streaming-topic
description: Add a schema-validated Pub/Sub BigQuery subscription and quarantine table for a new Bronze event stream.
---

# Add Streaming Topic

Use this workflow to add a new Pub/Sub topic streaming JSON events straight into BigQuery Bronze.

## 1. Define Schema and Table Columns

1. Prefer `schema_type = "PROTOCOL_BUFFER"` with `proto3` scalar fields and `NULLABLE` BigQuery columns.
2. Include metadata columns `subscription_name`, `message_id`, `publish_time`, and `attributes` in `target_table_schema_json`.
3. Confirm `target_table_id` stays unique within `bronze_dataset_id`.

## 2. Wire `modules/ingestion/pubsub-bigquery`

1. Add a new `module` block referencing `../../modules/ingestion/pubsub-bigquery` in `stages/enterprise` or `stages/sandbox`.
2. Set `stream_name`, `target_table_id`, `schema_definition`, `target_table_schema_json`, and `target_clustering`.
3. Keep `drop_unknown_fields = false` so invalid payloads fail cleanly into `${target_table_id}_quarantine`.

## 3. Register Declaration in `gcp-data-medallion`

1. Add a matching `type: "declaration"` SQLX file under `definitions/01_bronze/` in `gcp-data-medallion`.
2. Verify both repositories pass local validation:

```bash
make fmt-check
make validate
make test
```
