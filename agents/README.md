# Agent Definitions

Each subdirectory under `agents/` defines one OpenClaw agent. The deployment
framework reads every agent folder, validates its configuration, and deploys
all agents to the shared VM with per-agent WhatsApp accounts and channel policies.

## Directory Layout

```
agents/
├── README.md                  # This file
├── <agent-id>/
│   ├── agent.json             # Required — agent config (identity, model, WhatsApp, bindings)
│   ├── SOUL.md                # Required — agent personality and behaviour rules
│   ├── IDENTITY.md            # Optional — public-facing identity (name, emoji, theme)
│   ├── env.template           # Required — template for agent-specific secrets
│   ├── .env                   # Gitignored — actual secrets (copy from env.template)
│   └── workspace/             # Optional — initial data files (uploaded to VM)
│       └── ...
```

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
     "model": { "primary": "anthropic/claude-sonnet-4-5" },
     "whatsapp": {
       "account": "my-agent",
       "dmPolicy": "allowlist",
       "allowFrom": ["+4917612345678"],
       "groupPolicy": "allowlist",
       "selfChatMode": true,
       "groupChat": { "mentionPatterns": ["MyAgent", "@MyAgent"] }
     },
     "bindings": []
   }
   ```

3. **Write `SOUL.md`** — the agent's personality, values, boundaries, and
   behavioural rules. This is the most important file.

4. **Copy and fill `env.template` → `.env`:**
   ```bash
   WHATSAPP_NUMBER=+4915112345678
   WHATSAPP_ALLOW_FROM=+4917612345678,+4915198765432
   WHATSAPP_GROUPS=120363424282127706@g.us
   WHATSAPP_GROUP_ALLOW_FROM=+4917612345678
   ```

5. **Validate and deploy:**
   ```bash
   make agents-validate
   make agents-deploy
   make agent-whatsapp-link AGENT=my-agent
   ```

## agent.json Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | yes | Unique agent identifier (must match directory name) |
| `identity.name` | string | yes | Display name |
| `identity.emoji` | string | no | Emoji for UI and logs |
| `identity.theme` | string | no | Personality theme hint |
| `model` | string/object | no | LLM model override (defaults to gateway default) |
| `whatsapp.account` | string | yes | WhatsApp account name (unique per agent) |
| `whatsapp.dmPolicy` | string | no | DM policy: `disabled`, `open`, `allowlist`, `pairing` (default: `allowlist`) |
| `whatsapp.groupPolicy` | string | no | Group policy: `disabled`, `open`, `allowlist`, `mention` (default: `allowlist`) |
| `whatsapp.selfChatMode` | boolean | no | Enable self-chat mode (default: `true`) |
| `whatsapp.allowFrom` | array | no | E.164 phone numbers allowed to DM this agent (merged with `.env` `WHATSAPP_ALLOW_FROM`) |
| `whatsapp.groupAllowFrom` | array | no | E.164 numbers allowed to trigger this agent in groups (merged with `.env` `WHATSAPP_GROUP_ALLOW_FROM`) |
| `whatsapp.groupChat.mentionPatterns` | array | no | Patterns that trigger the agent in group chats |
| `bindings` | array | no | Additional channel routing rules |

### env.template Variables

| Variable | Description |
|----------|-------------|
| `WHATSAPP_NUMBER` | Agent's WhatsApp phone number (E.164 format) |
| `WHATSAPP_ALLOW_FROM` | Comma-separated E.164 numbers allowed to DM this agent |
| `WHATSAPP_GROUPS` | Comma-separated WhatsApp group JIDs this agent may join |
| `WHATSAPP_GROUP_ALLOW_FROM` | Comma-separated E.164 numbers allowed to trigger in groups |

### How Deployment Works

`make agents-deploy` reads each agent's `agent.json` and `.env`, then generates:

1. **`agents.list`** — one entry per agent with identity, workspace, model, and mention patterns
2. **`bindings`** — per-agent WhatsApp account bindings + optional group bindings
3. **`channels.whatsapp.accounts`** — per-agent WhatsApp account with DM/group policies and allowlists

This is merged into `openclaw.json` on the VM, following OpenClaw's
[multi-agent routing](https://docs.openclaw.ai/concepts/multi-agent) pattern.

## Security

- **`.env` files are gitignored** — never commit secrets.
- **`workspace/` data files** may contain sensitive information and are
  gitignored by default. Only commit example/template files.
- Agent definitions are isolated — one agent's config cannot affect another's.
- Each agent gets its own WhatsApp account — no shared phone numbers.

## Isolation Guarantees

- Each agent gets its own workspace on the VM (`~/.openclaw/workspace-<id>/`).
- SOUL.md and IDENTITY.md are per-agent and never shared.
- WhatsApp accounts are per-agent with independent DM/group allowlists.
- Channel bindings ensure messages are routed to the correct agent.
- Agent A's `.env` secrets are never visible to agent B's configuration.
