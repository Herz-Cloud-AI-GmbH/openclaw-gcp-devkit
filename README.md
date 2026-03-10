# OpenClaw on GCP

Deploy [OpenClaw](https://github.com/openclaw/openclaw) — an open-source, privacy-focused AI personal assistant — on a GCP Compute Engine instance. Manage your emails and calendars via WhatsApp, Signal, and other messaging channels.

## Features

- **One-command deploy** — Terraform provisions a GCP `e2-medium` instance with OpenClaw pre-installed
- **Secure by default** — No external IP, IAP-tunneled SSH, OpenClaw bound to localhost, deny-all firewall
- **Per-agent configuration** — Each agent has its own WhatsApp number, channel policies, personality, and secrets
- **Multi-agent WhatsApp** — Each agent gets a dedicated WhatsApp account with independent DM/group allowlists
- **DevContainer** — Pre-configured development environment with all tools
- **Makefile** — Convenient commands for every operation (`tf-*`, `vm-*`, `oc-*`, `agents-*`)

## Quick Start

> **Tip:** Open this repository in the [DevContainer](.devcontainer/devcontainer.json) — all tools are pre-installed and port 18789 is forwarded to your host automatically.

### 1. Authenticate

```bash
make auth
```

This runs `gcloud auth login` (CLI) and `gcloud auth application-default login` (Terraform/GCS). The project is set automatically from `terraform.tfvars`. Re-run after every DevContainer rebuild.

### 2. Configure

```bash
# Terraform variables
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform.tfvars — set project_id, region, zone

# Gateway API keys (at least one LLM provider required)
cp config/env.template config/.env
# Edit config/.env — uncomment and fill in your provider key
```

Supported providers: Anthropic Claude, OpenAI, Google Gemini, KIMI K2.5 (Moonshot), GitHub Copilot.

> `OPENCLAW_GATEWAY_TOKEN` and `GOG_KEYRING_PASSWORD` are auto-generated on the VM. Only set them in `config/.env` if you want to override the defaults.

### 3. Configure Agents

Each agent has its own directory under `agents/`. Configure WhatsApp and secrets per agent:

```bash
# For each agent (e.g. johndoe):
cp agents/johndoe/env.template agents/johndoe/.env
# Edit agents/johndoe/.env:
#   WHATSAPP_NUMBER=+4915112345678
#   WHATSAPP_ALLOW_FROM=+4917612345678,+4915198765432
#   WHATSAPP_GROUPS=120363424282127706@g.us
#   WHATSAPP_GROUP_ALLOW_FROM=+4917612345678

# Validate all agents
make agents-validate
```

Each agent's `agent.json` defines its WhatsApp account name, DM/group policies, and mention patterns. The `.env` file provides the actual phone number and allowlists.

### 4. Deploy

```bash
make check       # Verify prerequisites
make bootstrap   # Create GCS bucket for remote state (one-time)
make tf-init     # Initialise Terraform
make tf-plan     # Preview changes
make tf-apply    # Deploy to GCP (~2 min for VM + startup script)

# Install Python + agent tooling on the VM (run once after VM creation)
make vm-provision
```

### 5. Upload Config & Deploy Agents

```bash
# Upload gateway API keys
make oc-upload-env ENV_FILE=config/.env
make oc-restart

# Configure LLM providers (Moonshot/KIMI if using)
make oc-setup

# Preview what will change, then apply
make agents-plan    # shows +added / ~updated / -removed
make agents-apply   # deploys all agents + removes orphaned workspaces
```

### 6. Link WhatsApp for Each Agent

Each agent has its own WhatsApp account. Link them one at a time:

```bash
make agent-whatsapp-link AGENT=johndoe   # Scan QR with the agent's phone
# Repeat for each agent in agents/
```

### 7. Access the Control UI

```bash
make vm-tunnel   # Opens IAP SSH tunnel (keep running)
```

Open **http://localhost:18789** in your host browser. On first visit:

1. Get the dashboard URL with token:
   ```bash
   make vm-ssh
   sudo docker exec openclaw node dist/index.js dashboard --no-open
   ```
2. Paste the printed URL (includes `#token=...`) into your browser.
3. If you see "pairing required", approve the browser device:
   ```bash
   sudo docker exec openclaw node dist/index.js devices list
   sudo docker exec openclaw node dist/index.js devices approve <requestId>
   ```
4. Refresh the browser — the Control UI connects.

### 8. Connect Additional Services

With the tunnel running and the Control UI open:

- **Signal** — Channels → Signal → follow pairing instructions
- **Gmail** — Skills → Email → OAuth2 consent flow
- **Calendar** — Skills → Calendar → authorise Google Calendar

## Command Reference

| Command | Description |
|---------|-------------|
| **Setup** | |
| `make auth` | Authenticate gcloud CLI + ADC (run after container rebuild) |
| `make check` | Verify prerequisites are installed |
| `make bootstrap` | Create GCS bucket for remote state (one-time) |
| **Terraform (tf-)** | |
| `make tf-init` | Initialise Terraform (with GCS remote state) |
| `make tf-plan` | Preview infrastructure changes (saves plan file) |
| `make tf-apply` | Apply saved plan (or interactive if no plan) |
| `make tf-destroy` | Tear down all GCP resources |
| `make tf-output` | Show Terraform outputs (name, zone) |
| **VM (vm-)** | |
| `make vm-start` | Start the VM (if stopped) |
| `make vm-stop` | Stop the VM (saves compute cost; disk persists) |
| `make vm-ssh` | SSH into the VM (via IAP) |
| `make vm-tunnel` | IAP SSH tunnel — forwards localhost:18789 to the VM |
| `make vm-provision` | Install/update Python venv + agent tooling on the VM (idempotent) |
| **OpenClaw (oc-)** | |
| `make oc-cli` | Interactive TUI terminal chat |
| `make oc-status` | Show OpenClaw container status |
| `make oc-logs` | Tail container logs |
| `make oc-restart` | Restart the container |
| `make oc-update` | Pull latest image, run `doctor --fix` for migrations, redeploy agents |
| `make oc-upload-env ENV_FILE=config/.env` | Upload gateway .env (API keys) to the VM |
| `make oc-setup` | Configure LLM providers on VM (reads `config/.env`) |
| **Agents** | |
| `make agents-validate` | Validate agent definitions locally (no VM required) |
| `make agents-plan` | Show what will be added, updated, or removed on the VM |
| `make agents-apply` | Deploy all agents + remove orphaned workspaces |
| `make agents-deploy` | Alias for `agents-apply` (backwards compatibility) |
| `make agents-list` | List discovered agents with WhatsApp accounts |
| `make agent-whatsapp-link AGENT=<id>` | Link WhatsApp for a specific agent (interactive QR scan) |
| **Dev** | |
| `make test` | Run validation tests |
| `make lint` | Lint shell scripts with ShellCheck |

### On the VM (via `make vm-ssh`)

| Command | Description |
|---------|-------------|
| `sudo docker exec openclaw node dist/index.js dashboard --no-open` | Get tokenized dashboard URL |
| `sudo docker exec openclaw node dist/index.js devices list` | List pending device pairing requests |
| `sudo docker exec openclaw node dist/index.js devices approve <id>` | Approve a browser device |

## Per-Agent Configuration

All agent-specific configuration lives in `agents/<id>/`:

| File | Purpose |
|------|---------|
| `agent.json` | Agent identity, model, WhatsApp account/policies, bindings |
| `SOUL.md` | Agent personality and behaviour rules |
| `IDENTITY.md` | Public-facing identity (name, emoji, role) |
| `env.template` | Template for agent secrets (WhatsApp number, allowlists) |
| `.env` | Actual secrets (gitignored — copy from env.template) |
| `workspace/` | Initial data files (uploaded to VM on deploy) |

### WhatsApp Configuration

Each agent's WhatsApp setup is split between `agent.json` (policies) and `.env` (secrets):

**agent.json** — channel policies and mention patterns:
```json
{
  "whatsapp": {
    "account": "johndoe",
    "dmPolicy": "allowlist",
    "groupPolicy": "allowlist",
    "selfChatMode": true,
    "groupChat": {
      "mentionPatterns": ["JohnDoe", "@JohnDoe"]
    }
  }
}
```

**.env** — phone number and allowlists:
```bash
WHATSAPP_NUMBER=+4915112345678
WHATSAPP_ALLOW_FROM=+4917612345678,+4915198765432
WHATSAPP_GROUPS=120363424282127706@g.us
WHATSAPP_GROUP_ALLOW_FROM=+4917612345678
```

`make agents-apply` reads both files and generates the proper OpenClaw multi-account WhatsApp configuration with per-agent bindings.

### Gateway vs Agent Configuration

| Setting | Where | File |
|---------|-------|------|
| LLM API keys | Gateway | `config/.env` |
| Gateway token / keyring | Gateway | `config/.env` |
| LLM provider setup (Moonshot) | Gateway | `make oc-setup` |
| WhatsApp number | Per-agent | `agents/<id>/.env` |
| WhatsApp DM/group policies | Per-agent | `agents/<id>/agent.json` |
| WhatsApp allowlists | Per-agent | `agents/<id>/.env` |
| Personality (SOUL.md) | Per-agent | `agents/<id>/SOUL.md` |
| Agent identity | Per-agent | `agents/<id>/agent.json` |
| Model selection | Per-agent | `agents/<id>/agent.json` |

## Creating a New Agent

1. **Create the directory:**
   ```bash
   mkdir -p agents/my-agent/workspace
   ```

2. **Write `agent.json`:**
   ```json
   {
     "id": "my-agent",
     "identity": { "name": "My Agent", "emoji": "🤖" },
     "model": { "primary": "moonshot/kimi-k2.5" },
     "whatsapp": {
       "account": "my-agent",
       "dmPolicy": "allowlist",
       "groupPolicy": "allowlist",
       "selfChatMode": true,
       "groupChat": { "mentionPatterns": ["MyAgent", "@MyAgent"] }
     },
     "bindings": []
   }
   ```

3. **Write `SOUL.md`** — the agent's personality, values, and behavioural rules.

4. **Copy and fill `env.template` → `.env`** with the agent's WhatsApp number and allowlists.

5. **Validate and deploy:**
   ```bash
   make agents-validate
   make agents-plan
   make agents-apply
   make agent-whatsapp-link AGENT=my-agent
   ```

See [`agents/README.md`](agents/README.md) and [`docs/agents.md`](docs/agents.md) for full documentation.

## Costs

| Resource | Estimated Monthly Cost |
|----------|----------------------|
| e2-medium (2 vCPU, 4 GB) | ~$24 |
| 20 GB standard disk | ~$0.80 |
| Cloud NAT gateway | ~$1.00 |
| Network egress (minimal) | ~$0.10 |
| **Total** | **~$26** |

> Use `e2-micro` ($7/month) or Spot/Preemptible instances for further savings.

### Auto Start/Stop Schedule (optional)

Reduce compute costs by automatically stopping the VM at night and starting it in the morning. Add to `terraform.tfvars`:

```hcl
vm_schedule_enabled  = true
vm_schedule_timezone = "Europe/Berlin"
vm_schedule_start    = "0 8 * * 1-5"   # 08:00 weekdays
vm_schedule_stop     = "0 22 * * *"     # 22:00 every day
```

Then `make tf-plan && make tf-apply`. Running 14h/day weekdays only cuts compute cost by ~60%. You can also start/stop manually with `make vm-start` / `make vm-stop`.

## Cleanup

```bash
make tf-destroy   # Removes all GCP resources
```

## License

MIT — see [LICENSE](LICENSE).
