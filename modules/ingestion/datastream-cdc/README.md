# Datastream CDC Module

This module provisions a private connection, source profile, BigQuery profile, and Datastream CDC stream.

## Features

- Supports `POSTGRESQL` and `MYSQL` relational sources.
- Reads database passwords strictly from Secret Manager (`secret_manager_stored_password`).
- Supports `psc_interface_config` (`network_attachment`) or `vpc_peering_config` private connectivity.
- Supports BigQuery `APPEND_ONLY` or `MERGE` delivery with optional CMEK encryption.
- Grants `roles/bigquery.jobUser` on `compute_project_id` and `roles/bigquery.dataEditor` only on `bronze_dataset_id`.
