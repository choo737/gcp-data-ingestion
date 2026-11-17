ENV ?= dev
STAGE ?= enterprise
TFSTATE_BUCKET ?=
TF_STATE_BUCKET ?=
VAR_FILE ?=

EFFECTIVE_STATE_BUCKET := $(if $(strip $(TFSTATE_BUCKET)),$(strip $(TFSTATE_BUCKET)),$(strip $(TF_STATE_BUCKET)))

ROOTS := \
	stages/sandbox \
	stages/enterprise

NORMALIZED_STAGE := $(patsubst stages/%,%,$(STAGE))
STAGE_DIR := stages/$(NORMALIZED_STAGE)
BACKEND_PREFIX := ingestion/$(NORMALIZED_STAGE)/$(ENV)

export ENV TFSTATE_BUCKET TF_STATE_BUCKET STAGE VAR_FILE

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
	@case "$(STAGE_DIR)" in \
		stages/sandbox|stages/enterprise) ;; \
		*) echo "Invalid STAGE: $(STAGE)" >&2; exit 1 ;; \
	esac; \
	case "$(ENV)" in \
		dev|staging|prod) ;; \
		*) echo "Invalid ENV: $(ENV)" >&2; exit 1 ;; \
	esac; \
	if [ -z "$(EFFECTIVE_STATE_BUCKET)" ]; then \
		echo "Set TFSTATE_BUCKET or TF_STATE_BUCKET=<gcs-bucket> before running make init" >&2; \
		exit 1; \
	fi; \
	terraform -chdir="$(STAGE_DIR)" init -reconfigure -input=false \
		-backend-config="bucket=$(EFFECTIVE_STATE_BUCKET)" \
		-backend-config="prefix=$(BACKEND_PREFIX)"

plan: init
	@if [ -n "$(VAR_FILE)" ]; then \
		terraform -chdir="$(STAGE_DIR)" plan -input=false -var-file="$(VAR_FILE)"; \
	elif [ -f "$(STAGE_DIR)/envs/$(ENV).tfvars" ]; then \
		terraform -chdir="$(STAGE_DIR)" plan -input=false -var-file="envs/$(ENV).tfvars"; \
	else \
		terraform -chdir="$(STAGE_DIR)" plan -input=false; \
	fi

apply: init
	@if [ -n "$(VAR_FILE)" ]; then \
		terraform -chdir="$(STAGE_DIR)" apply -input=false -var-file="$(VAR_FILE)"; \
	elif [ -f "$(STAGE_DIR)/envs/$(ENV).tfvars" ]; then \
		terraform -chdir="$(STAGE_DIR)" apply -input=false -var-file="envs/$(ENV).tfvars"; \
	else \
		terraform -chdir="$(STAGE_DIR)" apply -input=false; \
	fi

test:
	python3 -m unittest discover -s tests -v

clean:
	find . \( -name ".terraform" -o -name "__pycache__" -o -name ".pytest_cache" \) -type d -prune -exec rm -rf {} +
	find . \( -name "00_linked.auto.tfvars.json" -o -name "linked.auto.tfvars.json" \) -type f -delete
