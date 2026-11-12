# CLAUDE.md

Read [AGENTS.md](AGENTS.md) and [.agents/skills/setup-data-ingestion/SKILL.md](.agents/skills/setup-data-ingestion/SKILL.md) before running Terraform or gcloud commands.

## Quick Rules

- Create a private repository (`gh repo create --private`) before storing any customer configuration.
- Link `gcp-foundation` outputs via `scripts/link-stages.sh` into gitignored `00_linked.auto.tfvars.json`.
- Write custom overrides into gitignored `custom.auto.tfvars` and store DB passwords only in Secret Manager.
- Keep all four `modules/ingestion/` directories at exactly five files.
- Keep `stages/sandbox/` and `stages/enterprise/` at exactly six files.
- Pin Terraform `>= 1.8.0` and `hashicorp/google` `>= 8.0.0, < 9.0.0`.
- Run `make fmt-check`, `make validate`, and `make test` after every edit.
