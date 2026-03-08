#!/usr/bin/env bash
# Validate all agent definitions under agents/.
# Checks: required files, JSON syntax, required fields, id consistency,
#         WhatsApp config schema.
# Exit 0 if all agents valid, exit 1 on any error.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AGENTS_DIR="${REPO_ROOT}/agents"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

ERRORS=0
WARNINGS=0
AGENTS_CHECKED=0
MIN_SOUL_BYTES=50

error() { ERRORS=$((ERRORS + 1)); printf "${RED}  ✗ %s${NC}\n" "$1"; }
ok()    { printf "${GREEN}  ✓ %s${NC}\n" "$1"; }
warn()  { WARNINGS=$((WARNINGS + 1)); printf "${YELLOW}  ⚠ %s${NC}\n" "$1"; }

echo "=== Agent Definition Validation ==="
echo ""

agent_dirs=()
for entry in "${AGENTS_DIR}"/*/; do
  [ -d "$entry" ] || continue
  agent_dirs+=("$entry")
done

if [ ${#agent_dirs[@]} -eq 0 ]; then
  echo "No agent directories found under ${AGENTS_DIR}/"
  echo "Create one with: mkdir -p agents/my-agent && ..."
  exit 0
fi

# Track WhatsApp accounts to detect duplicates
wa_accounts=()

for agent_dir in "${agent_dirs[@]}"; do
  agent_id=$(basename "$agent_dir")
  echo "--- Agent: ${agent_id} ---"
  AGENTS_CHECKED=$((AGENTS_CHECKED + 1))

  # 1. Required files
  for required in agent.json SOUL.md; do
    if [ -f "${agent_dir}/${required}" ]; then
      ok "${required} exists"
    else
      error "${required} missing"
    fi
  done

  # 2. env.template should exist
  if [ -f "${agent_dir}/env.template" ]; then
    ok "env.template exists"
  else
    warn "env.template missing (no secrets template for this agent)"
  fi

  # 3. Validate agent.json syntax
  config="${agent_dir}/agent.json"
  if [ -f "$config" ]; then
    if jq empty "$config" 2>/dev/null; then
      ok "agent.json is valid JSON"
    else
      error "agent.json is invalid JSON"
      continue
    fi

    # 4. Required fields
    json_id=$(jq -r '.id // empty' "$config")
    if [ -z "$json_id" ]; then
      error "agent.json missing required field: id"
    elif [ "$json_id" != "$agent_id" ]; then
      error "agent.json id '${json_id}' does not match directory name '${agent_id}'"
    else
      ok "agent.json id matches directory name"
    fi

    identity_name=$(jq -r '.identity.name // empty' "$config")
    if [ -z "$identity_name" ]; then
      error "agent.json missing required field: identity.name"
    else
      ok "identity.name is set: ${identity_name}"
    fi

    # 5. Bindings validation
    if jq -e '.bindings' "$config" >/dev/null 2>&1; then
      if jq -e '.bindings | type == "array"' "$config" >/dev/null 2>&1; then
        ok "bindings is an array"
      else
        error "bindings must be an array"
      fi
    fi

    # 6. WhatsApp config validation
    if jq -e '.whatsapp' "$config" >/dev/null 2>&1; then
      if jq -e '.whatsapp | type == "object"' "$config" >/dev/null 2>&1; then
        ok "whatsapp config is an object"
      else
        error "whatsapp must be an object"
      fi

      wa_account=$(jq -r '.whatsapp.account // empty' "$config")
      if [ -n "$wa_account" ]; then
        ok "whatsapp.account is set: ${wa_account}"
        # Check for duplicate accounts
        for existing in "${wa_accounts[@]+"${wa_accounts[@]}"}"; do
          if [ "$existing" = "$wa_account" ]; then
            error "whatsapp.account '${wa_account}' is used by another agent"
          fi
        done
        wa_accounts+=("$wa_account")
      else
        warn "whatsapp.account not set (needed for per-agent WhatsApp)"
      fi

      wa_dm_policy=$(jq -r '.whatsapp.dmPolicy // empty' "$config")
      if [ -n "$wa_dm_policy" ]; then
        case "$wa_dm_policy" in
          disabled|open|allowlist|pairing)
            ok "whatsapp.dmPolicy is valid: ${wa_dm_policy}" ;;
          *)
            error "whatsapp.dmPolicy '${wa_dm_policy}' is invalid (must be disabled|open|allowlist|pairing)" ;;
        esac
      fi

      wa_group_policy=$(jq -r '.whatsapp.groupPolicy // empty' "$config")
      if [ -n "$wa_group_policy" ]; then
        case "$wa_group_policy" in
          disabled|open|allowlist|mention)
            ok "whatsapp.groupPolicy is valid: ${wa_group_policy}" ;;
          *)
            error "whatsapp.groupPolicy '${wa_group_policy}' is invalid (must be disabled|open|allowlist|mention)" ;;
        esac
      fi

      if jq -e '.whatsapp.groupChat.mentionPatterns' "$config" >/dev/null 2>&1; then
        if jq -e '.whatsapp.groupChat.mentionPatterns | type == "array"' "$config" >/dev/null 2>&1; then
          ok "whatsapp.groupChat.mentionPatterns is an array"
        else
          error "whatsapp.groupChat.mentionPatterns must be an array"
        fi
      fi

      # allowFrom validation (optional E.164 number array)
      for af_field in allowFrom groupAllowFrom; do
        if jq -e ".whatsapp.${af_field}" "$config" >/dev/null 2>&1; then
          if jq -e ".whatsapp.${af_field} | type == \"array\"" "$config" >/dev/null 2>&1; then
            ok "whatsapp.${af_field} is an array"
            bad_nums=$(jq -r ".whatsapp.${af_field}[] | select(test(\"^\\\\+[0-9]+$\") | not)" "$config" 2>/dev/null || true)
            if [ -n "$bad_nums" ]; then
              error "whatsapp.${af_field} contains invalid E.164 numbers: ${bad_nums}"
            else
              ok "whatsapp.${af_field} entries are valid E.164"
            fi
          else
            error "whatsapp.${af_field} must be an array"
          fi
        fi
      done
    fi

    # 7. Check .env has WHATSAPP_NUMBER if whatsapp.account is configured
    if jq -e '.whatsapp.account' "$config" >/dev/null 2>&1; then
      agent_env="${agent_dir}/.env"
      if [ -f "$agent_env" ]; then
        if grep -q '^WHATSAPP_NUMBER=' "$agent_env" 2>/dev/null; then
          ok "WHATSAPP_NUMBER set in .env"
        else
          warn "whatsapp.account configured but WHATSAPP_NUMBER not set in .env"
        fi
      else
        warn ".env not found — copy env.template to .env and fill in WHATSAPP_NUMBER"
      fi
    fi
  fi

  # 8. SOUL.md should not be empty
  if [ -f "${agent_dir}/SOUL.md" ]; then
    soul_size=$(wc -c < "${agent_dir}/SOUL.md")
    if [ "$soul_size" -lt "$MIN_SOUL_BYTES" ]; then
      warn "SOUL.md is very short (${soul_size} bytes) — consider adding more detail"
    else
      ok "SOUL.md has content (${soul_size} bytes)"
    fi
  fi

  echo ""
done

echo "=== Summary ==="
echo "Agents checked: ${AGENTS_CHECKED}"
echo "Errors: ${ERRORS}"
echo "Warnings: ${WARNINGS}"

if [ "$ERRORS" -gt 0 ]; then
  printf '%sValidation failed — fix errors above before deploying.%s\n' "$RED" "$NC"
  exit 1
else
  printf '%sAll agents valid.%s\n' "$GREEN" "$NC"
fi
