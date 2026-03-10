# OpenClaw on GCP — Makefile
# ===========================
# Run `make help` for a list of available commands.

SHELL := /bin/bash
.DEFAULT_GOAL := help

TF_DIR  := terraform
TF_PLAN := $(TF_DIR)/tfplan.out

# Parse tfvars once — used by bootstrap, init, and remote-ssh helpers.
_tfvar = $(shell grep -s '$(1)' $(TF_DIR)/terraform.tfvars 2>/dev/null | head -1 | sed 's/.*=\s*"\(.*\)"/\1/')
PROJECT_ID     := $(call _tfvar,project_id)
REGION         := $(or $(call _tfvar,region),us-central1)
TF_STATE_BUCKET := $(if $(PROJECT_ID),$(PROJECT_ID)-tf-state)

VM_NAME = $$(cd $(TF_DIR) && terraform output -raw instance_name)
VM_ZONE = $$(cd $(TF_DIR) && terraform output -raw instance_zone)

define require_bucket
	@if [ -z "$(TF_STATE_BUCKET)" ]; then \
		echo "Error: project_id not found in $(TF_DIR)/terraform.tfvars"; exit 1; \
	fi
endef

define vm_ssh
	gcloud compute ssh $(VM_NAME) --zone=$(VM_ZONE) --project=$(PROJECT_ID) --tunnel-through-iap -- $(1)
endef

define vm_scp
	gcloud compute scp $(1) $(VM_NAME):$(2) --zone=$(VM_ZONE) --project=$(PROJECT_ID) --tunnel-through-iap
endef

define vm_upload
	$(call vm_scp,$(1),/tmp/_openclaw_upload)
	$(call vm_ssh,"sudo mkdir -p $(dir $(2)) && sudo mv /tmp/_openclaw_upload $(2) && sudo chown openclaw:openclaw $(2) && sudo chmod 600 $(2)")
endef

# ---------------------------------------------------------------
# Help
# ---------------------------------------------------------------
.PHONY: help
help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------
# Setup (run once / rarely)
# ---------------------------------------------------------------
.PHONY: check auth bootstrap
check: ## Check that all prerequisites are installed
	@bash scripts/check-prerequisites.sh

auth: ## Authenticate gcloud CLI + ADC (run after container rebuild)
	gcloud auth login
	gcloud auth application-default login
	@if [ -n "$(PROJECT_ID)" ]; then gcloud config set project $(PROJECT_ID); fi
	@echo "Authenticated."

bootstrap: ## Create GCS bucket for Terraform remote state (one-time)
	$(require_bucket)
	@echo "Creating GCS bucket: gs://$(TF_STATE_BUCKET)"
	@gcloud storage buckets create gs://$(TF_STATE_BUCKET) \
		--location=$(REGION) \
		--uniform-bucket-level-access \
		--public-access-prevention 2>/dev/null \
		|| echo "Bucket already exists (or creation failed — check above)."
	@gcloud storage buckets update gs://$(TF_STATE_BUCKET) --versioning 2>/dev/null \
		|| echo "Warning: could not enable versioning."
	@echo ""
	@echo "Bucket ready. Now run: make tf-init"

# ---------------------------------------------------------------
# Terraform (tf-)
# ---------------------------------------------------------------
.PHONY: tf-init tf-plan tf-apply tf-destroy tf-output
tf-init: ## Initialise Terraform (uses GCS remote state)
	$(require_bucket)
	cd $(TF_DIR) && terraform init -backend-config="bucket=$(TF_STATE_BUCKET)"

tf-plan: ## Preview infrastructure changes and save plan
	cd $(TF_DIR) && terraform plan -out=$(abspath $(TF_PLAN))

tf-apply: ## Apply saved plan (or prompt if no plan exists)
	@if [ -f "$(TF_PLAN)" ]; then \
		cd $(TF_DIR) && terraform apply $(abspath $(TF_PLAN)) && rm -f $(abspath $(TF_PLAN)); \
	else \
		echo "No saved plan found. Run 'make tf-plan' first, or press enter to plan interactively."; \
		cd $(TF_DIR) && terraform apply; \
	fi

tf-destroy: ## Tear down all GCP resources
	cd $(TF_DIR) && terraform destroy

tf-output: ## Show Terraform outputs (name, zone)
	cd $(TF_DIR) && terraform output

# ---------------------------------------------------------------
# VM lifecycle (vm-)
# ---------------------------------------------------------------
.PHONY: vm-start vm-stop vm-ssh vm-tunnel vm-provision
vm-provision: ## Install / update agent tooling on the VM (Python, venv, packages) — idempotent, no VM recreation needed
	@echo "Uploading provision script..."
	$(call vm_scp,scripts/provision.sh,/tmp/provision.sh)
	$(call vm_ssh,"sudo chmod +x /tmp/provision.sh && sudo /tmp/provision.sh && rm -f /tmp/provision.sh")
	@echo "Provisioning complete."

vm-start: ## Start the VM (if stopped)
	gcloud compute instances start $(VM_NAME) --zone=$(VM_ZONE) --project=$(PROJECT_ID)
	@echo "VM started. Wait ~30s for Docker/OpenClaw to come up, then: make vm-tunnel"

vm-stop: ## Stop the VM (saves cost; data persists on disk)
	gcloud compute instances stop $(VM_NAME) --zone=$(VM_ZONE) --project=$(PROJECT_ID)
	@echo "VM stopped. No compute charges while stopped (disk charges still apply)."

vm-ssh: ## SSH into the OpenClaw instance
	$(call vm_ssh,)

vm-tunnel: ## Open SSH tunnel for OpenClaw UI (localhost:18789)
	@echo "Opening tunnel — access OpenClaw at http://localhost:18789"
	gcloud compute ssh $(VM_NAME) --zone=$(VM_ZONE) --project=$(PROJECT_ID) --tunnel-through-iap -- -N -L 18789:localhost:18789

# ---------------------------------------------------------------
# OpenClaw (oc-)
# ---------------------------------------------------------------
.PHONY: oc-cli oc-status oc-logs oc-restart oc-update oc-upload-env oc-setup
oc-cli: ## Open the OpenClaw interactive TUI (terminal chat)
	gcloud compute ssh $(VM_NAME) --zone=$(VM_ZONE) --project=$(PROJECT_ID) --tunnel-through-iap \
		-- -t "sudo docker exec -it openclaw node dist/index.js tui"

oc-status: ## Show OpenClaw container status on the VM
	$(call vm_ssh,"sudo docker ps --filter name=openclaw")

oc-logs: ## Tail OpenClaw container logs
	$(call vm_ssh,"sudo docker logs -f --tail=100 openclaw")

oc-restart: ## Restart the OpenClaw container on the VM
	$(call vm_ssh,"cd /home/openclaw && sudo docker compose restart")

oc-update: ## Update OpenClaw to latest image, run doctor --fix, redeploy agents
	@echo "Pulling latest OpenClaw image..."
	$(call vm_ssh,"sudo docker pull ghcr.io/openclaw/openclaw:latest")
	@echo "Restarting with new image..."
	$(call vm_ssh,"cd /home/openclaw && sudo docker compose up -d && sleep 10")
	@echo "Running doctor --fix to apply config migrations..."
	$(call vm_ssh,"sudo docker exec openclaw node dist/index.js doctor --fix")
	@echo "Redeploying agents..."
	@bash scripts/deploy-agents.sh

oc-upload-env: ## Upload gateway .env to the VM (provide ENV_FILE=path)
	@if [ -z "$(ENV_FILE)" ]; then echo "Usage: make oc-upload-env ENV_FILE=config/.env"; exit 1; fi
	$(call vm_upload,$(ENV_FILE),/home/openclaw/.env)
	@echo "Restart OpenClaw to apply: make oc-restart"

oc-setup: ## Configure LLM providers on the VM (reads config/.env)
	$(eval ENV_SRC := $(or $(ENV_FILE),config/.env))
	@if [ ! -f "$(ENV_SRC)" ]; then echo "Error: $(ENV_SRC) not found. Copy config/env.template -> config/.env and fill in values."; exit 1; fi
	$(eval MOONSHOT_KEY := $(shell grep -s '^MOONSHOT_API_KEY=' $(ENV_SRC) 2>/dev/null | head -1 | cut -d= -f2-))
	@echo "Uploading setup script to VM..."
	$(call vm_scp,scripts/setup-providers.sh,/tmp/setup-providers.sh)
	$(call vm_ssh,"sudo chmod +x /tmp/setup-providers.sh && sudo MOONSHOT_API_KEY='$(MOONSHOT_KEY)' /tmp/setup-providers.sh && rm -f /tmp/setup-providers.sh")

# ---------------------------------------------------------------
# Agents
# ---------------------------------------------------------------
.PHONY: agents-validate agents-plan agents-apply agents-deploy agents-list agent-whatsapp-link

agents-validate: ## Validate agent definitions locally (no VM required)
	@bash scripts/validate-agents.sh

agents-plan: ## Show what agents-apply will add, update, and remove on the VM
	$(eval LOCAL  := $(shell for d in agents/*/; do [ -f "$$d/agent.json" ] && basename "$$d"; done))
	$(eval REMOTE := $(shell $(call vm_ssh,"jq -r '.agents.list[]?.id // empty' /home/openclaw/.openclaw/openclaw.json 2>/dev/null || true") 2>/dev/null))
	@echo ""
	@echo "  agents-plan"
	@echo "  ─────────────────────────────────"
	@for id in $(LOCAL); do \
	  if echo " $(REMOTE) " | grep -q " $$id "; then \
	    echo "  \033[33m~ $$id\033[0m  (will be updated)"; \
	  else \
	    echo "  \033[32m+ $$id\033[0m  (will be added)"; \
	  fi; \
	done
	@for id in $(REMOTE); do \
	  if ! echo " $(LOCAL) " | grep -q " $$id "; then \
	    echo "  \033[31m- $$id\033[0m  (will be removed)"; \
	  fi; \
	done
	@echo "  ─────────────────────────────────"
	@echo "  Run 'make agents-apply' to execute."
	@echo ""

agents-apply: agents-validate ## Apply: deploy all agents + remove orphaned workspaces from VM
	@bash scripts/deploy-agents.sh
	$(eval KNOWN := $(shell for d in agents/*/; do [ -f "$$d/agent.json" ] && echo "workspace-$$(basename $$d)"; done | tr '\n' ' '))
	$(call vm_ssh,"for d in /home/openclaw/.openclaw/workspace-*/; do name=\$$(basename \"\$$d\"); \
	  if ! echo ' $(KNOWN) ' | grep -q \" \$$name \"; then \
	    echo \"  Removing orphaned workspace: \$$d\"; sudo rm -rf \"\$$d\"; \
	  fi; done")

agents-deploy: agents-apply ## Alias for agents-apply (backwards compatibility)

agents-list: ## List discovered agent directories
	@for d in agents/*/; do \
		[ -f "$$d/agent.json" ] && echo "  $$(jq -r '"\(.id)\t\(.identity.name)\t\(.identity.emoji // "")\t\(.whatsapp.account // "-")"' "$$d/agent.json")" || true; \
	done | column -t -s$$'\t'

agent-whatsapp-link: ## Link WhatsApp for an agent (provide AGENT=<id>)
	@if [ -z "$(AGENT)" ]; then echo "Usage: make agent-whatsapp-link AGENT=johndoe"; exit 1; fi
	@if [ ! -f "agents/$(AGENT)/agent.json" ]; then echo "Error: agents/$(AGENT)/agent.json not found"; exit 1; fi
	$(eval WA_ACCOUNT := $(shell jq -r '.whatsapp.account // empty' agents/$(AGENT)/agent.json))
	@if [ -z "$(WA_ACCOUNT)" ]; then echo "Error: agents/$(AGENT)/agent.json has no whatsapp.account"; exit 1; fi
	@echo "Linking WhatsApp account '$(WA_ACCOUNT)' for agent $(AGENT)..."
	@echo "Clearing any stale session..."
	-$(call vm_ssh,"sudo docker exec openclaw node dist/index.js channels logout --channel whatsapp --account $(WA_ACCOUNT) 2>/dev/null")
	@echo "Scan the QR code with the phone for agent $(AGENT)..."
	$(call vm_ssh,-t "sudo docker exec -it openclaw node dist/index.js channels login --channel whatsapp --account $(WA_ACCOUNT)")
	@echo "Restarting gateway to pick up new credentials..."
	$(call vm_ssh,"cd /home/openclaw && sudo docker compose restart")

# ---------------------------------------------------------------
# Devkit sync  (infrastructure shared with public openclaw-gcp-devkit repo)
# agents/ is always excluded — it never leaves this private repo.
# ---------------------------------------------------------------
DEVKIT_REMOTE  := devkit
DEVKIT_BRANCH  := sync/devkit
DEVKIT_URL     := git@github.com:Herz-Cloud-AI-GmbH/openclaw-gcp-devkit.git
DEVKIT_PATHS   := terraform/ scripts/ config/ docs/ .devcontainer/ tests/ \
                  Makefile README.md AGENTS.md LICENSE .gitignore .gitattributes

.PHONY: devkit-setup devkit-push devkit-pull

devkit-setup: ## One-time: add devkit remote and create sync/devkit branch
	@if git remote get-url $(DEVKIT_REMOTE) > /dev/null 2>&1; then \
	  echo "Remote '$(DEVKIT_REMOTE)' already exists — skipping add."; \
	else \
	  git remote add $(DEVKIT_REMOTE) $(DEVKIT_URL); \
	  echo "Added remote '$(DEVKIT_REMOTE)'."; \
	fi
	@git fetch $(DEVKIT_REMOTE)
	@if git show-ref --quiet refs/heads/$(DEVKIT_BRANCH); then \
	  echo "Branch '$(DEVKIT_BRANCH)' already exists — skipping create."; \
	else \
	  git checkout -b $(DEVKIT_BRANCH) $(DEVKIT_REMOTE)/main; \
	  git checkout -; \
	  echo "Created branch '$(DEVKIT_BRANCH)' tracking $(DEVKIT_REMOTE)/main."; \
	fi
	@echo "Devkit setup complete. Run 'make devkit-push' or 'make devkit-pull'."

devkit-push: ## Push infrastructure changes to public devkit repo (agents/ always excluded)
	@SOURCE=$$(git branch --show-current); \
	echo "Pushing infra from '$$SOURCE' → $(DEVKIT_REMOTE)/main (agents/ excluded)..."; \
	git checkout $(DEVKIT_BRANCH); \
	git checkout $$SOURCE -- $(DEVKIT_PATHS); \
	if git diff --staged --quiet; then \
	  echo "Nothing new to push to devkit."; \
	else \
	  git commit -m "chore: sync infrastructure from private repo"; \
	  git push $(DEVKIT_REMOTE) $(DEVKIT_BRANCH):main; \
	  echo "Pushed to $(DEVKIT_REMOTE)/main."; \
	fi; \
	git checkout $$SOURCE

devkit-pull: ## Pull infrastructure updates from public devkit repo (agents/ protected)
	@TARGET=$$(git branch --show-current); \
	echo "Pulling infra from $(DEVKIT_REMOTE)/main → '$$TARGET' (agents/ protected)..."; \
	git fetch $(DEVKIT_REMOTE); \
	git checkout $(DEVKIT_BRANCH); \
	git merge $(DEVKIT_REMOTE)/main; \
	git checkout $$TARGET; \
	git checkout $(DEVKIT_BRANCH) -- $(DEVKIT_PATHS); \
	if git diff --staged --quiet; then \
	  echo "Already up to date with devkit."; \
	else \
	  git commit -m "chore: sync infrastructure from devkit"; \
	  echo "Merged devkit infra into '$$TARGET'. agents/ untouched."; \
	fi

# ---------------------------------------------------------------
# Dev
# ---------------------------------------------------------------
.PHONY: test lint
test: ## Run validation tests
	@bash tests/test_terraform_validate.sh
	@bash tests/test_scripts.sh
	@bash tests/test_agents.sh
	@echo "All tests passed."

lint: ## Lint shell scripts with ShellCheck
	@shellcheck scripts/*.sh tests/*.sh && echo "ShellCheck: all scripts OK"
