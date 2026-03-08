#!/usr/bin/env bash
# Configure OpenClaw LLM providers in openclaw.json on the VM.
# Called remotely by "make oc-setup" — runs as root on the VM.
#
# Reads env vars: MOONSHOT_API_KEY
# WhatsApp channel config is handled per-agent by deploy-agents.sh.
# Requires: jq (installed by startup.sh)
set -euo pipefail

CONFIG="/home/openclaw/.openclaw/openclaw.json"

if [ ! -f "$CONFIG" ]; then
  echo "Error: $CONFIG not found — is OpenClaw running?" >&2
  exit 1
fi

CHANGED=0

merge_patch() {
  local patch="$1"
  local tmp
  tmp=$(mktemp)
  jq -s '.[0] * .[1]' "$CONFIG" <(echo "$patch") > "$tmp"
  mv "$tmp" "$CONFIG"
  chown openclaw:openclaw "$CONFIG"
  CHANGED=1
}

# ------------------------------------------------------------------
# Moonshot / Kimi K2.5 provider
# ------------------------------------------------------------------
if [ -n "${MOONSHOT_API_KEY:-}" ]; then
  echo "Configuring Moonshot / Kimi K2.5 provider..."
  merge_patch "$(jq -n --arg key "$MOONSHOT_API_KEY" '{
    agents: {
      defaults: {
        model: { primary: "moonshot/kimi-k2.5" },
        models: {
          "moonshot/kimi-k2.5":              { alias: "Kimi K2.5" },
          "moonshot/kimi-k2-0905-preview":   { alias: "Kimi K2" },
          "moonshot/kimi-k2-turbo-preview":  { alias: "Kimi K2 Turbo" },
          "moonshot/kimi-k2-thinking":       { alias: "Kimi K2 Thinking" },
          "moonshot/kimi-k2-thinking-turbo": { alias: "Kimi K2 Thinking Turbo" }
        }
      }
    },
    models: {
      mode: "merge",
      providers: {
        moonshot: {
          baseUrl: "https://api.moonshot.ai/v1",
          apiKey: $key,
          api: "openai-completions",
          models: [
            { id: "kimi-k2.5",              name: "Kimi K2.5",              reasoning: false, input: ["text"], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 256000, maxTokens: 8192 },
            { id: "kimi-k2-0905-preview",   name: "Kimi K2 0905 Preview",   reasoning: false, input: ["text"], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 256000, maxTokens: 8192 },
            { id: "kimi-k2-turbo-preview",  name: "Kimi K2 Turbo",          reasoning: false, input: ["text"], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 256000, maxTokens: 8192 },
            { id: "kimi-k2-thinking",       name: "Kimi K2 Thinking",       reasoning: true,  input: ["text"], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 256000, maxTokens: 8192 },
            { id: "kimi-k2-thinking-turbo", name: "Kimi K2 Thinking Turbo", reasoning: true,  input: ["text"], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 256000, maxTokens: 8192 }
          ]
        }
      }
    }
  }')"
  echo "  Moonshot provider configured (default model: moonshot/kimi-k2.5)."
else
  echo "  Skipping Moonshot — MOONSHOT_API_KEY not set."
fi

if [ "$CHANGED" -eq 1 ]; then
  echo "Restarting OpenClaw to apply changes..."
  cd /home/openclaw && docker compose restart
  echo "Done."
else
  echo "Nothing to configure."
fi
