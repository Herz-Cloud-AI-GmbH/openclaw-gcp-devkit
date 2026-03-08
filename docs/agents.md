# Agent Framework — Architecture

## Overview

This repository serves as a **common deployment ground** for OpenClaw agents.
The core infrastructure (Terraform, VM management, Docker) is shared. Agent
definitions live in isolated directories under `agents/` and are deployed to the
VM at runtime. Each agent has its own WhatsApp account, channel policies,
personality, and secrets.

```
┌─────────────────────────────────────────────────────────────────┐
│                      Repository Layout                          │
│                                                                 │
│  terraform/        Shared infrastructure (VM, VPC, IAM, NAT)    │
│  scripts/          Shared scripts (startup, deploy, validate)   │
│  config/           Gateway-level config (.env for LLM API keys) │
│                                                                 │
│  agents/                                                        │
│  ├── johndoe/     Sample agent definition                       │
│  │   ├── agent.json   Config (identity, model, WhatsApp, binds) │
│  │   ├── SOUL.md      Personality and behaviour rules           │
│  │   ├── IDENTITY.md  Public-facing identity                    │
│  │   ├── env.template Secret template (WA number, allowlists)   │
│  │   ├── .env         Actual secrets (gitignored)               │
│  │   └── workspace/   Initial data files (gitignored)           │
│  └── my-agent/    Another agent definition                      │
│      └── ...                                                    │
└─────────────────────────────────────────────────────────────────┘
```

## Design Principles

1. **Agent isolation** — each agent has its own directory, workspace, secrets,
   SOUL.md, and WhatsApp account. Agent A cannot read or affect Agent B.
2. **Per-agent channels** — each agent has its own WhatsApp number, DM/group
   policies, and allowlists. No shared phone numbers.
3. **Infrastructure stays shared** — Terraform, the VM, Docker, and the OpenClaw
   gateway are managed once. Agents are layered on top.
4. **Gateway-level vs agent-level** — LLM API keys are gateway-level (`config/.env`).
   WhatsApp numbers, channel policies, and personalities are per-agent.
5. **Secrets stay out of version control** — agent `.env` files and workspace
   data are gitignored. Only templates and definitions are committed.
6. **Validate before deploy** — `make agents-validate` checks all agent configs
   locally before any deployment to the VM.

## Deployment Flow

```
Developer workstation                           GCP VM
─────────────────────                           ──────

1. make agents-validate
   ├── Check agent.json syntax + WhatsApp schema
   ├── Check required files
   ├── Check field consistency
   └── Detect duplicate WhatsApp accounts

2. make agents-deploy
   ├── For each agent:
   │   ├── Read agent.json + .env
   │   ├── Upload SOUL.md, IDENTITY.md       ──►  ~/.openclaw/workspace-<id>/
   │   └── Upload workspace data             ──►  ~/.openclaw/workspace-<id>/
   │
   ├── Build merged config patch
   │   ├── agents.list[]                      (per-agent identity + mentions)
   │   ├── bindings[]                         (per-agent WhatsApp account routing)
   │   └── channels.whatsapp.accounts{}       (per-agent DM/group policies)
   │
   └── Apply patch to openclaw.json          ──►  ~/.openclaw/openclaw.json
       └── Restart OpenClaw

3. make agent-whatsapp-link AGENT=<id>
   └── Link WhatsApp for specific agent      ──►  QR scan with agent's phone
```

## On the VM

After deployment, the VM filesystem looks like:

```
/home/openclaw/
├── .env                            # Gateway secrets (LLM API keys)
├── docker-compose.yml              # Docker config
└── .openclaw/
    ├── openclaw.json               # Merged config (agents + bindings + WhatsApp accounts)
    ├── credentials/
    │   └── whatsapp/
    │       └── johndoe/            # John Doe WhatsApp credentials
    ├── workspace-johndoe/          # John Doe workspace
    │   ├── SOUL.md
    │   ├── IDENTITY.md
    │   └── ...
    └── workspace-another-agent/    # Another agent workspace
        ├── SOUL.md
        ├── IDENTITY.md
        └── ...
```

## Agent Configuration Merging

The deploy script builds a JSON patch from all agent definitions and deep-merges
it into the existing `openclaw.json`. Example output:

```json
{
  "agents": {
    "list": [
      {
        "id": "johndoe",
        "identity": { "name": "John Doe", "emoji": "🤖" },
        "workspace": "~/.openclaw/workspace-johndoe",
        "model": "anthropic/claude-sonnet-4-5",
        "groupChat": { "mentionPatterns": ["JohnDoe", "@JohnDoe"] }
      },
      {
        "id": "my-agent",
        "identity": { "name": "My Agent", "emoji": "🔧" },
        "workspace": "~/.openclaw/workspace-my-agent",
        "model": "anthropic/claude-sonnet-4-5",
        "groupChat": { "mentionPatterns": ["MyAgent", "@MyAgent"] }
      }
    ]
  },
  "bindings": [
    { "agentId": "johndoe", "match": { "channel": "whatsapp", "accountId": "johndoe" } },
    { "agentId": "my-agent", "match": { "channel": "whatsapp", "accountId": "my-agent" } }
  ],
  "channels": {
    "whatsapp": {
      "accounts": {
        "johndoe": {
          "dmPolicy": "allowlist",
          "allowFrom": ["+4911111111"],
          "selfChatMode": true,
          "groupPolicy": "allowlist",
          "groupAllowFrom": ["+492222222"]
        },
        "my-agent": {
          "dmPolicy": "allowlist",
          "allowFrom": ["+4917612345678"],
          "selfChatMode": true,
          "groupPolicy": "allowlist",
          "groupAllowFrom": ["+4917612345678"]
        }
      }
    }
  }
}
```

This follows OpenClaw's [multi-agent routing](https://docs.openclaw.ai/concepts/multi-agent)
pattern: each WhatsApp account is bound to exactly one agent, and channel policies
are scoped per-account.

## Security Considerations

| Concern | Mitigation |
|---------|------------|
| Agent secrets in git | `.env` files are gitignored; only `env.template` is committed |
| Cross-agent data access | Each agent has its own workspace directory on the VM |
| Cross-agent WhatsApp | Each agent has its own WhatsApp account with independent allowlists |
| Unauthorised message routing | Bindings restrict each agent to its own WhatsApp account |
| Config corruption | Validation runs before every deploy; JSON merge is atomic |
| VM-level isolation | All agents run in the same OpenClaw container but with separate workspaces |
