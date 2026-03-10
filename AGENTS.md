# AGENTS.md

Deploy OpenClaw on GCP e2-medium via Terraform + Docker.
Per-agent configuration: each agent in `agents/<id>/` has its own WhatsApp account, channel policies, SOUL.md, and secrets.

## Structure

- `terraform/` — IaC: main.tf, compute.tf, network.tf, iam.tf, schedule.tf, variables.tf, outputs.tf
- `scripts/` — startup.sh (Docker only, runs once), provision.sh (Python/tooling, idempotent via `make vm-provision`), check-prerequisites.sh, setup-providers.sh, validate-agents.sh, deploy-agents.sh
- `config/` — env.template (gateway-level LLM API keys only)
- `agents/` — Per-agent definitions (agent.json, SOUL.md, IDENTITY.md, env.template, workspace/)
- `tests/` — test_terraform_validate.sh, test_scripts.sh, test_agents.sh
- `docs/` — architecture.md, agents.md

## Commands

```bash
make auth                                    # gcloud login + ADC (after container rebuild)
make check                                   # verify prerequisites
make bootstrap                               # create GCS state bucket (one-time)
make tf-init                                 # terraform init
make tf-plan                                 # terraform plan (saves file)
make tf-apply                                # apply saved plan
make tf-destroy                              # tear down
make vm-start                                # start VM (if stopped)
make vm-stop                                 # stop VM (saves compute cost)
make vm-ssh                                  # SSH into VM (IAP)
make vm-tunnel                               # IAP tunnel → localhost:18789
make oc-cli                                  # interactive TUI terminal chat
make oc-status / oc-logs / oc-restart        # container management
make oc-update                               # update to latest image + doctor --fix + redeploy agents
make vm-provision                            # install/update Python venv + agent tooling on VM (idempotent)
make oc-upload-env ENV_FILE=config/.env      # push gateway API keys
make oc-setup                                # configure LLM providers on VM (reads config/.env)
make agents-validate                         # validate agent definitions locally
make agents-plan                             # show +added / ~updated / -removed on VM
make agents-apply                            # deploy agents + remove orphaned workspaces
make agents-list                             # list discovered agents
make agent-whatsapp-link AGENT=<id>          # link WhatsApp for a specific agent
make test                                    # run all tests
make lint                                    # shellcheck
```

## VM commands (via `make vm-ssh`)

```bash
sudo docker exec openclaw node dist/index.js dashboard --no-open   # get dashboard URL
sudo docker exec openclaw node dist/index.js devices list           # list pairing requests
sudo docker exec openclaw node dist/index.js devices approve <id>   # approve browser
```

## Key facts

- Image: `ghcr.io/openclaw/openclaw:latest`, gateway runs `--bind lan --port 18789`
- No external IP — IAP SSH only, Cloud NAT for outbound
- Firewall: IAP range `35.235.240.0/20` SSH only, deny-all fallback
- Host bind mounts at `~/.openclaw/` — not Docker named volumes
- Gateway config: `gateway.mode=local`, `controlUi.allowedOrigins=["http://127.0.0.1:18789"]`
- DevContainer forwards port 18789 to host; browser accesses Control UI directly
- Shell scripts: `set -euo pipefail`, must pass ShellCheck
- Terraform: validate must pass, state in GCS (`<project_id>-tf-state`), no secrets in code
- Per-agent WhatsApp: each agent has its own `whatsapp.account` in agent.json, own number in .env, own channel policies and bindings
- `config/env.template` — gateway-level only (LLM API keys); no WhatsApp config
- Agent SOUL.md, IDENTITY.md, and channel config are per-agent in `agents/<id>/`
- After DevContainer rebuild: run `make auth` (sets project from terraform.tfvars)
