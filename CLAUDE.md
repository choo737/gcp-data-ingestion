# CLAUDE.md

Read [AGENTS.md](AGENTS.md), [QUESTIONNAIRE.md](QUESTIONNAIRE.md), [docs/03-enterprise-adoption-guide.md](docs/03-enterprise-adoption-guide.md), and [.agents/skills/setup-data-ingestion/SKILL.md](.agents/skills/setup-data-ingestion/SKILL.md) before running Terraform or gcloud commands.

## Quick Rules

- Create a private repository (`gh repo create --private`) before storing any customer configuration.
- Pair with [gcp-launchpad](https://github.com/choo737/gcp-launchpad), [gcp-foundation](https://github.com/choo737/gcp-foundation), [gcp-data-medallion](https://github.com/choo737/gcp-data-medallion), and [gcp-data-science](https://github.com/choo737/gcp-data-science) for end-to-end platform delivery.
- Check optional `platform-context.json` from [gcp-launchpad](https://github.com/choo737/gcp-launchpad) or complete `QUESTIONNAIRE.md` first.
- Link Greenfield outputs via `scripts/link-stages.sh --env <env>` (`dev`, `uat`, `staging`, `prod`) or Brownfield `00_linked.auto.tfvars.json`.
- Map `QUESTIONNAIRE.md` Section 1 to `00_linked.auto.tfvars.json` and Sections 2 to 4 to `envs/<env>.tfvars`.
- Add Day-2 feeds via `pubsub_streams`, `batch_jobs`, `datastream_streams`, and `schemas/` without editing `main.tf`.
- Write custom overrides into gitignored `custom.auto.tfvars` and store DB passwords only in Secret Manager.
- Keep all four `modules/ingestion/` directories at exactly five files.
- Keep `stages/sandbox/` and `stages/enterprise/` synced with `versions.tf`, `backend "gcs" {}`, and `.terraform.lock.hcl`.
- Pin Terraform `>= 1.8.0` and `hashicorp/google` `>= 8.0.0, < 9.0.0`.
- Run `make fmt-check`, `make validate`, and `make test` after every edit.
