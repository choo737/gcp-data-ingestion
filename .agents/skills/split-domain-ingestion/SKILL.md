---
name: split-domain-ingestion
description: Split a single gcp-data-ingestion repository into independent domain repositories such as ingest-retail at enterprise scale.
---

# Split Domain Ingestion Repositories

Split `gcp-data-ingestion` into per-domain repositories when sources exceed roughly `15` feeds or teams need separate releases.

## 1. Create a Private Domain Ingestion Repository

```bash
gh repo create <owner>/ingest-<domain> --private --template choo737/gcp-data-ingestion --clone
cd ingest-<domain>
```

Keep shared `modules/ingestion/`, `workflows/`, and `scripts/link-stages.sh` intact.

## 2. Export Shared Foundation Outputs Once

On the platform team side inside `gcp-foundation`, export shared outputs to a restricted GCS state bucket:

```bash
./scripts/link-stages.sh --export-gcs gs://<platform-state-bucket>/foundation-outputs.json \
  foundation/02-security-network \
  data/enterprise/01-platform \
  data/enterprise/02-governance-ops
```

## 3. Link Domain Repositories via GCS

In each `ingest-<domain>` repository, pull only declared variables into `00_linked.auto.tfvars.json`:

```bash
./scripts/link-stages.sh --from-gcs gs://<platform-state-bucket>/foundation-outputs.json stages/enterprise
```

Set a domain-unique `prefix` (for example `ret` or `fin`) in `custom.auto.tfvars` to avoid name collisions.

## 4. Retire Migrated Feeds and Validate

1. Remove migrated source blocks from the original repository after cutover.
2. Run `make fmt-check`, `make validate`, and `make test` in each repository.
