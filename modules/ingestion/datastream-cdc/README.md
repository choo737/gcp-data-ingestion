# Datastream CDC Module

This module provisions a private connection, source profile, BigQuery profile, and Datastream CDC stream.

## Features

- Supports `POSTGRESQL` and `MYSQL` relational sources.
- Reads database passwords strictly from Secret Manager (`secret_manager_stored_password`).
- Supports `psc_interface_config` or `vpc_peering_config` private connectivity.
- Supports BigQuery `APPEND_ONLY` or `MERGE` delivery with optional CMEK encryption.
- Scopes Datastream IAM strictly to the target Bronze dataset and secret version.
