# CLAUDE.md

Read [AGENTS.md](AGENTS.md), [QUESTIONNAIRE.md](QUESTIONNAIRE.md), and [.agents/skills/setup-data-ingestion/SKILL.md](.agents/skills/setup-data-ingestion/SKILL.md) before running Terraform or gcloud commands.

## Quick Rules

- Create a private repository (`gh repo create --private`) before storing any customer configuration.
- Check optional `platform-context.json` from [gcp-launchpad](https://github.com/choo737/gcp-launchpad) or complete `QUESTIONNAIRE.md` first.
- Link Greenfield outputs via `scripts/link-stages.sh --env <env>` or populate Brownfield `00_linked.auto.tfvars.json`.
- Write custom overrides into gitignored `custom.auto.tfvars` and store DB passwords only in Secret Manager.
- Keep all four `modules/ingestion/` directories at exactly five files.
- Keep `stages/sandbox/` and `stages/enterprise/` synced with `versions.tf`, `backend "gcs" {}`, and `.terraform.lock.hcl`.
- Pin Terraform `>= 1.8.0` and `hashicorp/google` `>= 8.0.0, < 9.0.0`.
- Run `make fmt-check`, `make validate`, and `make test` after every edit.
