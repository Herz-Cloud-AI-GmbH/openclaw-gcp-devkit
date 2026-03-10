# Architecture — OpenClaw on GCP

## Overview

This project deploys OpenClaw as a single Docker container on a GCP Compute Engine instance. The architecture prioritises simplicity, cost-efficiency, and security for a solo developer.

```
┌─────────────────────────────────────────────────────────────────┐
│                     Developer Workstation                       │
│                                                                 │
│  ┌──────────────┐    SSH Tunnel (port 18789)                    │
│  │  Browser      │◄──────────────────────────┐                  │
│  │  localhost:   │                            │                  │
│  │  18789        │                            │                  │
│  └──────────────┘                            │                  │
│                                               │                  │
│  ┌──────────────┐    SSH via IAP tunnel       │                  │
│  │  Terminal     │────────────────────────────┤                  │
│  │  gcloud ssh   │                            │                  │
│  └──────────────┘                            │                  │
└───────────────────────────────────────────────┼─────────────────┘
                                                │
                    ┌───────────────────────────┼─────────────────┐
                    │         GCP Project        │                 │
                    │                            │                 │
                    │  ┌─── VPC Network ────────┼───────────────┐ │
                    │  │                         │               │ │
                    │  │  Firewall: IAP SSH only  │               │ │
                    │  │  Cloud NAT (outbound)    │               │ │
                    │  │                         │               │ │
                    │  │  ┌──────────────────────▼─────────────┐ │ │
                    │  │  │  Compute Engine (e2-medium)         │ │ │
                    │  │  │  Debian 12 · 2 vCPU · 4 GB RAM     │ │ │
                    │  │  │  No external IP                     │ │ │
                    │  │  │                                     │ │ │
                    │  │  │  ┌───────────────────────────────┐  │ │ │
                    │  │  │  │  Docker                        │  │ │ │
                    │  │  │  │  ┌─────────────────────────┐   │  │ │ │
                    │  │  │  │  │  OpenClaw Container      │   │  │ │ │
                    │  │  │  │  │  127.0.0.1:18789         │   │  │ │ │
                    │  │  │  │  │                          │   │  │ │ │
                    │  │  │  │  │  ┌──────┐ ┌──────────┐   │   │  │ │ │
                    │  │  │  │  │  │ Gate │ │ Skills    │   │   │  │ │ │
                    │  │  │  │  │  │ way  │ │ Email/Cal │   │   │  │ │ │
                    │  │  │  │  │  └──────┘ └──────────┘   │   │  │ │ │
                    │  │  │  │  └──────────▲──────────────┘   │  │ │ │
                    │  │  │  │             │ Volume Mount      │  │ │ │
                    │  │  │  └─────────────┼──────────────────┘  │ │ │
                    │  │  │               │                      │ │ │
                    │  │  │  ┌────────────▼────────────────────┐ │ │ │
                    │  │  │  │  Persistent Data                 │ │ │ │
                    │  │  │  │  ~/.openclaw/  (config, state)   │ │ │ │
                    │  │  │  │  SOUL.md, .env                   │ │ │ │
                    │  │  │  └──────────────────────────────────┘ │ │ │
                    │  │  └──────────────────────────────────────┘ │ │
                    │  └──────────────────────────────────────────┘ │
                    │                                                │
                    │  IAM: openclaw-vm-sa (logging + monitoring)    │
                    │        + IAP tunnel access for deployer        │
                    └────────────────────────────────────────────────┘

External APIs (outbound via Cloud NAT):
  ├── Anthropic / OpenAI / Google AI / Moonshot (KIMI) / GitHub Copilot  (LLM provider)
  ├── WhatsApp / Signal               (messaging channels)
  └── Gmail / Google Calendar          (email & calendar)
```

## Components

### 1. DevContainer

| File | Purpose |
|------|---------|
| `.devcontainer/devcontainer.json` | VS Code / Codespaces dev environment |

Pre-installs Terraform, gcloud, make, jq, and ShellCheck. Docker is not required locally — it runs on the GCP VM.

### 2. Terraform Infrastructure

| File | Purpose |
|------|---------|
| `terraform/main.tf` | Provider, backend, and version constraints |
| `terraform/variables.tf` | Configurable parameters |
| `terraform/compute.tf` | Compute Engine instance |
| `terraform/network.tf` | VPC, subnet, Cloud NAT, firewall rules |
| `terraform/iam.tf` | Service account, IAP tunnel access |
| `terraform/outputs.tf` | Instance name and zone |

### 3. Deployment Scripts

| File | Purpose |
|------|---------|
| `scripts/startup.sh` | VM startup script — installs Docker, pulls OpenClaw, starts container (runs once) |
| `scripts/provision.sh` | Installs Python venv and agent tooling on the VM (idempotent, via `make vm-provision`) |
| `scripts/check-prerequisites.sh` | Validates local tool prerequisites |
| `scripts/setup-providers.sh` | Configures LLM providers on the VM |
| `scripts/validate-agents.sh` | Validates agent definitions locally |
| `scripts/deploy-agents.sh` | Deploys all agents to the VM |

### 4. Configuration

| File | Purpose |
|------|---------|
| `config/env.template` | Template for gateway-level LLM provider API keys |
| `agents/<id>/agent.json` | Per-agent identity, model, WhatsApp policies, bindings |
| `agents/<id>/SOUL.md` | Per-agent personality and behaviour rules |
| `agents/<id>/env.template` | Per-agent secrets template (WhatsApp number, allowlists) |

## GCP Services

### Compute Engine

A single `e2-medium` VM (2 vCPU, 4 GB RAM) running Debian 12. Docker and OpenClaw are installed automatically by the startup script. The instance has **no external IP** — all inbound access goes through IAP, and all outbound traffic routes through Cloud NAT.

### Identity-Aware Proxy (IAP)

IAP provides a zero-trust access layer for the VM. Instead of exposing SSH on a public IP, `gcloud compute ssh --tunnel-through-iap` establishes an encrypted tunnel from the developer's machine through Google's IAP infrastructure to the VM's internal IP.

**How it works:**

1. The developer runs `make vm-ssh` or `make vm-tunnel`.
2. `gcloud` authenticates the user via their Google identity.
3. IAP verifies the user has the `roles/iap.tunnelResourceAccessor` role.
4. If authorised, IAP proxies the TCP connection (port 22) to the VM over Google's internal network.
5. The VM firewall only accepts SSH from the IAP IP range (`35.235.240.0/20`), rejecting all other inbound traffic.

**Why IAP instead of a public IP:**

- Compliant with org policies that block external IPs (`constraints/compute.vmExternalIpAccess`).
- No SSH port exposed to the internet — eliminates brute-force and scanning attacks.
- Access is identity-based (Google account + IAM role), not network-based (IP allowlists).
- Audit logging of every tunnel session via Cloud Audit Logs.

**Required API:** `iap.googleapis.com` (enabled during GCP setup).

### Cloud NAT

A NAT gateway attached to the VPC router. It gives the VM outbound internet access without an external IP, used for:

- `apt-get update` and package installation during startup
- `docker pull ghcr.io/openclaw/openclaw:latest`
- Outbound API calls to LLM providers, messaging services, and email/calendar APIs

Cloud NAT uses automatic IP allocation and covers all subnets in the VPC.

### VPC Network

A dedicated VPC (`openclaw-network`) with a single subnet (`10.0.1.0/24`). Isolates OpenClaw resources from the default network. Two firewall rules:

| Rule | Source | Action | Priority |
|------|--------|--------|----------|
| `openclaw-allow-iap-ssh` | `35.235.240.0/20` (IAP) | Allow TCP/22 | default (1000) |
| `openclaw-deny-all-ingress` | `0.0.0.0/0` | Deny all | 65534 |

### Cloud IAM

Three IAM bindings:

| Role | Principal | Purpose |
|------|-----------|---------|
| `roles/logging.logWriter` | VM service account | Write logs to Cloud Logging |
| `roles/monitoring.metricWriter` | VM service account | Write metrics to Cloud Monitoring |
| `roles/iap.tunnelResourceAccessor` | Deployer (auto-detected) | Allow IAP SSH tunnel access |

### Cloud Storage (GCS)

A single bucket (`<project_id>-tf-state`) stores Terraform remote state. Created by `make bootstrap` with:

- **Uniform bucket-level access** — no per-object ACLs
- **Object versioning** — enables state rollback
- **Public access prevention** — state is never publicly accessible
- **Built-in state locking** — prevents concurrent `terraform apply`

## Security Design

| Control | Implementation |
|---------|---------------|
| No external IP | VM has no public IP; SSH via IAP tunnel only |
| Network isolation | Dedicated VPC; firewall allows SSH from IAP range (`35.235.240.0/20`) only |
| No public API | Docker port mapping restricts to `127.0.0.1:18789`; gateway uses `--bind lan` for Control UI |
| Access method | IAP tunnel + DevContainer port forward; device pairing required on first browser connect |
| Outbound only | Cloud NAT provides outbound internet (apt-get, docker pull) |
| Least-privilege IAM | Dedicated service account with logging/monitoring roles only |
| Remote state | Terraform state stored in a versioned GCS bucket, not locally |
| No secrets in code | `.gitignore` excludes `.env`, `*.tfstate`, `sa-key.json` |
| Deny-all fallback | Low-priority firewall rule denies all non-IAP ingress |

## Data Flow

1. **Developer** runs `make vm-tunnel` to open an IAP SSH tunnel from the DevContainer to the GCP instance.
2. The DevContainer forwards port 18789 to the host machine (`forwardPorts` in `devcontainer.json`).
3. **Browser** on the host connects to `localhost:18789`, which reaches the OpenClaw Gateway through the tunnel chain.
4. **OpenClaw Gateway** processes requests, routing to the configured LLM provider.
5. **Skills** (Email, Calendar) connect to external APIs using OAuth2 or app passwords.
6. **Channels** (WhatsApp, Signal) maintain persistent connections to messaging services.
7. **All data** (conversations, config, state) stays on the VM's host filesystem (`~/.openclaw/`).

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Single VM, no Kubernetes | Simplicity for solo developer; e2-medium is sufficient |
| Docker instead of bare metal | Reproducible, easy updates via `docker pull` |
| IAP tunnel instead of HTTPS | No certificate management, no domain, no external IP required |
| Terraform instead of gcloud CLI | Declarative, version-controlled, idempotent |
| GCS remote state | State survives dev container rebuilds; built-in locking and versioning |
| No external IP + Cloud NAT | Compliant with org policies; outbound-only internet via NAT |
| Dedicated VPC | Isolation from default network; explicit firewall rules |
| Host bind mounts | Data on the host filesystem survives container rebuilds, Docker reinstalls, and volume prunes |
| Gateway `--bind lan` + `mode=local` | Enables the HTTP Control UI; Docker's `127.0.0.1` port mapping keeps it off the network |
| Device pairing | Browser must be approved as a trusted device on first connect; token stored in localStorage |
| DevContainer port forwarding | Port 18789 forwarded from container to host; browser accesses UI without extra setup |

## Cost Analysis

| Resource | Specification | Monthly Cost (USD) |
|----------|--------------|-------------------|
| Compute Engine | e2-medium, us-central1 | ~$24.27 |
| Boot Disk | 20 GB pd-standard | ~$0.80 |
| Cloud NAT | Gateway + minimal data processing | ~$1.00 |
| Network | Minimal egress | ~$0.10 |
| **Total** | | **~$26.17** |

### Cost Reduction Options

- **Spot/Preemptible instance**: ~60% discount (acceptable for non-critical personal use)
- **e2-micro**: Free tier eligible, 0.25 vCPU / 1 GB (may be tight for OpenClaw)
- **Committed use discounts**: 1-year commitment for ~37% savings

## Multi-Agent Framework

The repository supports deploying multiple isolated agents to a single VM.
Each agent has its own WhatsApp account, channel policies, personality, and secrets.
See [`docs/agents.md`](agents.md) for the full agent framework architecture.

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Agent definitions in `agents/<id>/` | Isolation by directory; each agent is self-contained |
| Per-agent WhatsApp accounts | Each agent has its own phone number, DM/group policies, and allowlists |
| Per-agent workspaces on VM | OpenClaw natively supports `workspace-<id>` directories |
| Gateway-level vs agent-level config | LLM API keys are shared; WhatsApp/personality are per-agent |
| JSON merge for config | Idempotent; agents are layered onto the existing `openclaw.json` |
| Validation before deploy | Catches config errors locally before touching the VM |
| Secrets in gitignored `.env` | Agent-specific WhatsApp numbers and allowlists stay local |
