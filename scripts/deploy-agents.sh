#!/usr/bin/env bash
# Deploy all agent definitions to the OpenClaw VM.
#
# For each agent under agents/:
#   1. Reads agent.json and per-agent .env
#   2. Uploads SOUL.md, IDENTITY.md, and workspace files to the VM
#   3. Builds per-agent WhatsApp accounts, bindings, and channel config
#   4. Merges everything into openclaw.json on the VM
#
# Usage: Called by "make agents-deploy" — requires a running VM.
# Prerequisites: gcloud authenticated, VM reachable via IAP, jq installed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AGENTS_DIR="${REPO_ROOT}/agents"

TF_DIR="${REPO_ROOT}/terraform"
_tfvar() { grep -s "$1" "${TF_DIR}/terraform.tfvars" 2>/dev/null | head -1 | sed 's/.*=\s*"\(.*\)"/\1/'; }
PROJECT_ID=$(_tfvar project_id)
VM_NAME=$(cd "$TF_DIR" && terraform output -raw instance_name 2>/dev/null || echo "")
VM_ZONE=$(cd "$TF_DIR" && terraform output -raw instance_zone 2>/dev/null || echo "")

if [ -z "$VM_NAME" ] || [ -z "$VM_ZONE" ] || [ -z "$PROJECT_ID" ]; then
  echo "Error: Cannot determine VM name/zone/project. Run 'make tf-apply' first." >&2
  exit 1
fi

vm_ssh()  { gcloud compute ssh "$VM_NAME" --zone="$VM_ZONE" --project="$PROJECT_ID" --tunnel-through-iap -- "$@"; }
vm_scp()  { gcloud compute scp "$1" "$VM_NAME":"$2" --zone="$VM_ZONE" --project="$PROJECT_ID" --tunnel-through-iap; }

OPENCLAW_HOST="/home/openclaw/.openclaw"
OPENCLAW_CONTAINER="/home/node/.openclaw"
CONFIG_FILE="${OPENCLAW_HOST}/openclaw.json"

log() { echo "[deploy-agents] $*"; }

# ------------------------------------------------------------------
# 1. Validate first
# ------------------------------------------------------------------
log "Validating agent definitions..."
bash "${REPO_ROOT}/scripts/validate-agents.sh"

# ------------------------------------------------------------------
# 2. Discover agents
# ------------------------------------------------------------------
agent_dirs=()
for entry in "${AGENTS_DIR}"/*/; do
  [ -d "$entry" ] && [ -f "${entry}/agent.json" ] && agent_dirs+=("$entry")
done

if [ ${#agent_dirs[@]} -eq 0 ]; then
  log "No agents found under agents/. Nothing to deploy."
  exit 0
fi

log "Found ${#agent_dirs[@]} agent(s) to deploy."

# ------------------------------------------------------------------
# 3. Build the merged agents config
# ------------------------------------------------------------------
AGENTS_LIST="[]"
BINDINGS="[]"
WA_ACCOUNTS="{}"

read_env_var() {
  local file="$1" key="$2"
  grep -s "^${key}=" "$file" 2>/dev/null | head -1 | cut -d= -f2- || true
}

csv_to_json_array() {
  local csv="$1"
  if [ -z "$csv" ]; then
    echo "[]"
    return
  fi
  echo "$csv" | tr ',' '\n' | jq -R '.' | jq -s '.'
}

for agent_dir in "${agent_dirs[@]}"; do
  agent_id=$(basename "$agent_dir")
  config="${agent_dir}/agent.json"
  log "Processing agent: ${agent_id}"

  agent_env="${agent_dir}/.env"

  # Read WhatsApp vars from agent .env
  WA_NUM=""
  WA_ALLOW_FROM=""
  WA_GROUPS=""
  WA_GROUP_ALLOW_FROM=""
  if [ -f "$agent_env" ]; then
    WA_NUM=$(read_env_var "$agent_env" WHATSAPP_NUMBER)
    WA_ALLOW_FROM=$(read_env_var "$agent_env" WHATSAPP_ALLOW_FROM)
    WA_GROUPS=$(read_env_var "$agent_env" WHATSAPP_GROUPS)
    WA_GROUP_ALLOW_FROM=$(read_env_var "$agent_env" WHATSAPP_GROUP_ALLOW_FROM)
  fi

  # Read WhatsApp config from agent.json
  wa_account=$(jq -r '.whatsapp.account // empty' "$config")
  wa_dm_policy=$(jq -r '.whatsapp.dmPolicy // "allowlist"' "$config")
  wa_group_policy=$(jq -r '.whatsapp.groupPolicy // "allowlist"' "$config")
  wa_self_chat=$(jq -r '.whatsapp.selfChatMode // false' "$config")
  wa_mention_patterns=$(jq -c '.whatsapp.groupChat.mentionPatterns // []' "$config")

  # Build the agent entry for agents.list
  identity_name=$(jq -r '.identity.name' "$config")
  identity_emoji=$(jq -r '.identity.emoji // empty' "$config")
  model_primary=$(jq -r '.model.primary // .model // empty' "$config")
  workspace_host="${OPENCLAW_HOST}/workspace-${agent_id}"
  workspace_path="${OPENCLAW_CONTAINER}/workspace-${agent_id}"

  agent_entry=$(jq -n \
    --arg id "$agent_id" \
    --arg name "$identity_name" \
    --arg emoji "$identity_emoji" \
    --arg workspace "$workspace_path" \
    --arg model "$model_primary" \
    --argjson mentions "$wa_mention_patterns" \
    '{
      id: $id,
      identity: ({ name: $name } + (if $emoji != "" then { emoji: $emoji } else {} end)),
      workspace: $workspace
    }
    + (if $model != "" then { model: $model } else {} end)
    + (if ($mentions | length) > 0 then { groupChat: { mentionPatterns: $mentions } } else {} end)')

  AGENTS_LIST=$(echo "$AGENTS_LIST" | jq --argjson entry "$agent_entry" '. + [$entry]')

  # Add explicit bindings from agent.json
  agent_bindings=$(jq -c '.bindings // []' "$config")
  if [ "$agent_bindings" != "[]" ]; then
    agent_bindings=$(echo "$agent_bindings" | jq --arg id "$agent_id" '[.[] | . + { agentId: $id }]')
    BINDINGS=$(echo "$BINDINGS" | jq --argjson b "$agent_bindings" '. + $b')
  fi

  # Build per-agent WhatsApp account and bindings
  if [ -n "$WA_NUM" ] && [ -n "$wa_account" ]; then
    allow_from_arr=$(csv_to_json_array "$WA_ALLOW_FROM")
    groups_arr=$(csv_to_json_array "$WA_GROUPS")
    group_allow_arr=$(csv_to_json_array "$WA_GROUP_ALLOW_FROM")

    # Merge allowFrom from agent.json into .env values (agent.json wins on dupes)
    json_allow_from=$(jq -c '.whatsapp.allowFrom // []' "$config")
    if [ "$json_allow_from" != "[]" ]; then
      allow_from_arr=$(echo "$allow_from_arr" | jq --argjson extra "$json_allow_from" '. + $extra | unique')
    fi
    json_group_allow=$(jq -c '.whatsapp.groupAllowFrom // []' "$config")
    if [ "$json_group_allow" != "[]" ]; then
      group_allow_arr=$(echo "$group_allow_arr" | jq --argjson extra "$json_group_allow" '. + $extra | unique')
    fi

    # If WHATSAPP_ALLOW_FROM not set, default to the agent's own number
    if [ "$allow_from_arr" = "[]" ]; then
      allow_from_arr=$(jq -n --arg num "$WA_NUM" '[$num]')
    fi
    if [ "$group_allow_arr" = "[]" ]; then
      group_allow_arr="$allow_from_arr"
    fi

    # Build the WhatsApp account config
    wa_acct_config=$(jq -n \
      --arg dm_policy "$wa_dm_policy" \
      --argjson allow_from "$allow_from_arr" \
      --argjson self_chat "$wa_self_chat" \
      --arg group_policy "$wa_group_policy" \
      --argjson group_allow "$group_allow_arr" \
      --argjson groups "$groups_arr" \
      '{
        dmPolicy: $dm_policy,
        allowFrom: $allow_from,
        selfChatMode: $self_chat,
        groupPolicy: $group_policy,
        groupAllowFrom: $group_allow
      }
      + (if ($groups | length) > 0 then { groups: $groups } else {} end)')

    WA_ACCOUNTS=$(echo "$WA_ACCOUNTS" | jq --arg acct "$wa_account" --argjson cfg "$wa_acct_config" '.[$acct] = $cfg')

    # Route all messages on this WhatsApp account to this agent
    wa_binding=$(jq -n --arg id "$agent_id" --arg acct "$wa_account" '{
      agentId: $id,
      match: { channel: "whatsapp", accountId: $acct }
    }')
    BINDINGS=$(echo "$BINDINGS" | jq --argjson b "$wa_binding" '. + [$b]')
  fi

  # ------------------------------------------------------------------
  # Upload workspace files
  # ------------------------------------------------------------------
  log "  Creating workspace on VM: ${workspace_host}"
  vm_ssh "sudo mkdir -p '${workspace_host}' && sudo chown openclaw:openclaw '${workspace_host}'"

  if [ -f "${agent_dir}/SOUL.md" ]; then
    log "  Uploading SOUL.md..."
    vm_scp "${agent_dir}/SOUL.md" /tmp/_agent_soul
    vm_ssh "sudo mv /tmp/_agent_soul '${workspace_host}/SOUL.md' && sudo chown openclaw:openclaw '${workspace_host}/SOUL.md'"
  fi

  if [ -f "${agent_dir}/IDENTITY.md" ]; then
    log "  Uploading IDENTITY.md..."
    vm_scp "${agent_dir}/IDENTITY.md" /tmp/_agent_identity
    vm_ssh "sudo mv /tmp/_agent_identity '${workspace_host}/IDENTITY.md' && sudo chown openclaw:openclaw '${workspace_host}/IDENTITY.md'"
  fi

  if [ -d "${agent_dir}/workspace" ]; then
    data_files=$(find "${agent_dir}/workspace" -type f ! -name '.gitkeep' 2>/dev/null || true)
    if [ -n "$data_files" ]; then
      log "  Uploading workspace data files..."
      while IFS= read -r file; do
        rel_path="${file#"${agent_dir}/workspace/"}"
        target_dir=$(dirname "${workspace_host}/${rel_path}")
        vm_ssh "sudo mkdir -p '${target_dir}' && sudo chown openclaw:openclaw '${target_dir}'"
        vm_scp "$file" "/tmp/_agent_data"
        vm_ssh "sudo mv /tmp/_agent_data '${workspace_host}/${rel_path}' && sudo chown openclaw:openclaw '${workspace_host}/${rel_path}'"
      done <<< "$data_files"
    fi
  fi
done

# ------------------------------------------------------------------
# 4. Build and apply the merged openclaw.json patch
# ------------------------------------------------------------------
log "Building merged agent configuration..."

# Build the channels.whatsapp block with per-agent accounts
WA_CHANNELS="{}"
if [ "$(echo "$WA_ACCOUNTS" | jq 'length')" -gt 0 ]; then
  WA_CHANNELS=$(jq -n --argjson accounts "$WA_ACCOUNTS" '{ whatsapp: { accounts: $accounts } }')
fi

PATCH=$(jq -n \
  --argjson agents_list "$AGENTS_LIST" \
  --argjson bindings "$BINDINGS" \
  --argjson channels "$WA_CHANNELS" \
  '{
    agents: { list: $agents_list },
    bindings: $bindings
  }
  + (if ($channels | length) > 0 then { channels: $channels } else {} end)')

log "Uploading agent configuration to VM..."
echo "$PATCH" > /tmp/_agents_patch.json
vm_scp /tmp/_agents_patch.json /tmp/_agents_patch.json

vm_ssh "sudo test -f '${CONFIG_FILE}' || (echo '{}' | sudo tee '${CONFIG_FILE}' >/dev/null)"
vm_ssh "sudo jq -s '.[0] * .[1]' '${CONFIG_FILE}' /tmp/_agents_patch.json > /tmp/_openclaw_merged.json \
  && sudo mv /tmp/_openclaw_merged.json '${CONFIG_FILE}' \
  && sudo chown openclaw:openclaw '${CONFIG_FILE}' \
  && rm -f /tmp/_agents_patch.json"

rm -f /tmp/_agents_patch.json

# ------------------------------------------------------------------
# 5. Restart OpenClaw
# ------------------------------------------------------------------
log "Restarting OpenClaw to apply changes..."
vm_ssh "cd /home/openclaw && sudo docker compose restart"

log "Done. ${#agent_dirs[@]} agent(s) deployed successfully."
