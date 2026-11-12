# Ingestion Decision Guide

Choose the ingestion track that matches your source system, latency SLA, and network topology.

## Track Selection Matrix

| Track | Source System | Typical Latency | Best Fit |
| --- | --- | --- | --- |
| `datastream-cdc` | PostgreSQL or MySQL | Seconds to minutes | Operational database replication without managing Debezium |
| `pubsub-bigquery` | Microservices, POS, IoT | Sub-second to seconds | Schema-checked JSON events with automated DLQ quarantine |
| `batch-elt-job` | Cloud Storage files | Minutes to hourly | CSV, NDJSON, or Parquet drops needing watermark tracking |

## Datastream CDC Modes (`APPEND_ONLY` vs `MERGE`)

- Use `APPEND_ONLY` when downstream Silver Dataform models compute SCD Type 2 history or deduplicate events.
- Use `MERGE` when Bronze tables must mirror current source primary keys directly.
- Set `data_freshness` (default `300s`) to balance merge compute cost against query freshness.
- Store replication passwords in Secret Manager and pass `db_password_secret_version` (`secret_manager_stored_password`).
- Prefer PSC `network_attachment` or `vpc_peering_config` over public IP allowlists.

## Pub/Sub Schema Types (`PROTOCOL_BUFFER` vs `AVRO`)

- Use `PROTOCOL_BUFFER` (`proto3`) with `JSON` encoding when publishers send flat JSON objects.
- `proto3` avoids Avro union wrapper syntax (`{"string": "value"}`) on nullable fields.
- Choose `AVRO` only when upstream event producers already serialize standard Avro JSON records.
- Invalid JSON fails at topic publish time, while BigQuery type errors route to `*_quarantine`.

## Batch ELT Job (`jobs/gcs_to_bronze/`)

- Use `batch-elt-job` when files land in GCS and Dataform runs right after loading.
- The Python `3.13` loader records `(gcs_uri, generation)` in `_ingestion_watermarks` to prevent duplicate loads.
- Failing files move to `quarantine/` alongside a `.error.json` diagnostic object.
