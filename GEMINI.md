# GEMINI.md

Follow [AGENTS.md](AGENTS.md) and [.agents/skills/setup-data-ingestion/SKILL.md](.agents/skills/setup-data-ingestion/SKILL.md) for deployment and validation.

## Quick Rules

- Create a private repository (`gh repo create --private`) before entering customer parameters.
- Never guess project IDs, dataset names, network attachments, or database credentials.
- Link `gcp-foundation` outputs with `scripts/link-stages.sh` into `00_linked.auto.tfvars.json`.
- Store overrides in gitignored `custom.auto.tfvars` and DB credentials in Secret Manager.
- Keep five-file module symmetry in `modules/ingestion/` and six-file stage symmetry in `stages/`.
- Pin Terraform `>= 1.8.0` and `hashicorp/google` `>= 8.0.0, < 9.0.0`.
- Validate all edits using `make fmt-check`, `make validate`, and `make test`.
