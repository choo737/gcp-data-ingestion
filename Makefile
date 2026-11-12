ENV ?= dev
STAGE ?= enterprise
TF_STATE_BUCKET ?=

ROOTS := \
	stages/sandbox \
	stages/enterprise

STAGE_DIR := stages/$(STAGE)
BACKEND_PREFIX := ingestion/$(STAGE)/$(ENV)
VAR_FILE := $(STAGE_DIR)/envs/$(ENV).tfvars

.PHONY: fmt fmt-check validate init plan apply test clean

fmt:
	terraform fmt -recursive

fmt-check:
	terraform fmt -check -recursive

validate:
	@for dir in $(ROOTS); do \
		echo "==> Validating $$dir"; \
		terraform -chdir="$$dir" init -backend=false -input=false >/dev/null; \
		terraform -chdir="$$dir" validate; \
	done

init:
	@if [ -z "$(TF_STATE_BUCKET)" ]; then \
		echo "Set TF_STATE_BUCKET=<gcs-bucket> before running make init" >&2; \
		exit 1; \
	fi
	terraform -chdir="$(STAGE_DIR)" init -reconfigure \
		-backend-config="bucket=$(TF_STATE_BUCKET)" \
		-backend-config="prefix=$(BACKEND_PREFIX)"

plan:
	@if [ -f "$(VAR_FILE)" ]; then \
		terraform -chdir="$(STAGE_DIR)" plan -var-file="envs/$(ENV).tfvars"; \
	else \
		terraform -chdir="$(STAGE_DIR)" plan; \
	fi

apply:
	@if [ -f "$(VAR_FILE)" ]; then \
		terraform -chdir="$(STAGE_DIR)" apply -var-file="envs/$(ENV).tfvars"; \
	else \
		terraform -chdir="$(STAGE_DIR)" apply; \
	fi

test:
	python3 -m unittest discover -s tests -v

clean:
	find . \( -name ".terraform" -o -name "__pycache__" -o -name ".pytest_cache" \) -type d -prune -exec rm -rf {} +
	find . \( -name "00_linked.auto.tfvars.json" -o -name "linked.auto.tfvars.json" \) -type f -delete
