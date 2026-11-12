ROOTS := \
	stages/sandbox \
	stages/enterprise

.PHONY: fmt fmt-check validate test clean

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

test:
	python3 -m unittest discover -s tests -v

clean:
	find . \( -name ".terraform" -o -name "__pycache__" -o -name ".pytest_cache" \) -type d -prune -exec rm -rf {} +
	find . \( -name ".terraform.lock.hcl" -o -name "00_linked.auto.tfvars.json" -o -name "linked.auto.tfvars.json" \) -type f -delete
