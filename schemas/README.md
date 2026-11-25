# Pipeline Schemas

Store Pub/Sub message definitions and BigQuery Bronze table schemas in this directory.

## Layout

- `schemas/pubsub/`: Proto3 (`.proto`) or Avro (`.avsc`) definitions referenced by `pubsub_streams[*].schema_file`.
- `schemas/bigquery/`: BigQuery JSON table schemas referenced by `target_table_schema_file` on streams and batch jobs.

## Conventions

- Keep schema paths relative to the repository root, starting with `schemas/`.
- Match every field in your `.proto` message to a `NULLABLE` BigQuery column.
- Include `subscription_name`, `message_id`, `publish_time`, and `attributes` in BigQuery schemas for `pubsub_streams`.
