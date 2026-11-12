# Pub/Sub BigQuery Module

This module provisions schema-validated Pub/Sub streaming directly into partitioned BigQuery Bronze tables.

## Features

- Creates a `PROTOCOL_BUFFER` or `AVRO` schema with `JSON` topic encoding and `customer_email`.
- Injects Data Catalog `policyTags` on `customer_ic_number` and `customer_email` when configured.
- Streams valid events into a partitioned Bronze table using `use_table_schema` and `write_metadata`.
- Routes failed deliveries after five attempts into a dead-letter topic and quarantine table.
- Grants table-level BigQuery IAM to the Pub/Sub service agent (`google_bigquery_table_iam_member`).
