# Repository Scaling and Cloud Composer Guide

Start simple with one repository and serverless Cloud Workflows, then split or upgrade when scale demands it.

## Single Repository vs Domain Split (`1` to `15` Sources)

- Keep one `gcp-data-ingestion` repository while managing roughly `1` to `15` ingestion sources.
- Assign team review ownership per path inside `CODEOWNERS`.
- Split into domain repositories (`ingest-retail`, `ingest-finance`) when review queues or Terraform plans slow teams down.
- Link every split repository to shared `gcp-foundation` outputs using `scripts/link-stages.sh --from-gcs`.

## Cloud Workflows vs Cloud Composer 3 Cost (`asia-southeast1`)

| Engine | Idle Cost | Usage Metering (`asia-southeast1`) | Best Fit |
| --- | --- | --- | --- |
| Cloud Workflows | `$0` per hour | `5,000` free internal steps/month, then `$0.01` per `1,000` | Daily or event-driven Medallion chains |
| Cloud Composer 3 (Small) | `$0.43` env fee/hr (`24x7`) | Plus `$0.0738` per DCU-hour and `$0.2091` GiB-month SQL | Complex Python DAGs and custom sensors |

- Cloud Workflows incurs `$0` when idle because execution charges apply only per step executed.
- In `asia-southeast1`, a Small Cloud Composer environment carries a `$0.43` hourly fee plus compute and storage.
- Migrate to [medallion_composer3_dag.py](../composer_reference/medallion_composer3_dag.py) when you need hundreds of cross-system DAGs or Airflow operators.
- Keep `pipeline-workflows` as the default runner until custom Airflow plugins justify always-on cluster spend.
