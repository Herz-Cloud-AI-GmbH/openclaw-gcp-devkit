#!/usr/bin/env bash
# Test: Agent definitions and framework scripts are well-formed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
MIN_SOUL_BYTES=50

pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }

echo "=== Agent Framework Tests ==="

# Test 1: agents/ directory exists
if [ -d "${REPO_ROOT}/agents" ]; then
  pass "agents/ directory exists"
else
  fail "agents/ directory missing"
fi

# Test 2: Agent framework scripts exist and are executable
for script in scripts/validate-agents.sh scripts/deploy-agents.sh; do
  if [ -x "${REPO_ROOT}/${script}" ]; then
    pass "${script} exists and is executable"
  else
    fail "${script} missing or not executable"
  fi
done

# Test 3: agents/README.md exists
if [ -f "${REPO_ROOT}/agents/README.md" ]; then
  pass "agents/README.md exists"
else
  fail "agents/README.md missing"
fi

# Test 4: At least one agent is defined
agent_count=0
for d in "${REPO_ROOT}"/agents/*/; do
  [ -f "${d}/agent.json" ] && agent_count=$((agent_count + 1))
done
if [ "$agent_count" -gt 0 ]; then
  pass "${agent_count} agent(s) defined"
else
  fail "No agents defined under agents/"
fi

# Test 5: Each agent has required files and valid config
for agent_dir in "${REPO_ROOT}"/agents/*/; do
  [ -f "${agent_dir}/agent.json" ] || continue
  agent_id=$(basename "$agent_dir")

  # agent.json is valid JSON
  if jq empty "${agent_dir}/agent.json" 2>/dev/null; then
    pass "${agent_id}: agent.json is valid JSON"
  else
    fail "${agent_id}: agent.json is invalid JSON"
    continue
  fi

  # id field matches directory name
  json_id=$(jq -r '.id' "${agent_dir}/agent.json")
  if [ "$json_id" = "$agent_id" ]; then
    pass "${agent_id}: id matches directory name"
  else
    fail "${agent_id}: id '${json_id}' does not match directory '${agent_id}'"
  fi

  # identity.name is set
  name=$(jq -r '.identity.name // empty' "${agent_dir}/agent.json")
  if [ -n "$name" ]; then
    pass "${agent_id}: identity.name is set"
  else
    fail "${agent_id}: identity.name missing"
  fi

  # SOUL.md exists and has content
  if [ -f "${agent_dir}/SOUL.md" ]; then
    soul_size=$(wc -c < "${agent_dir}/SOUL.md")
    if [ "$soul_size" -gt "$MIN_SOUL_BYTES" ]; then
      pass "${agent_id}: SOUL.md has content (${soul_size} bytes)"
    else
      fail "${agent_id}: SOUL.md is too short (${soul_size} bytes)"
    fi
  else
    fail "${agent_id}: SOUL.md missing"
  fi

  # env.template exists
  if [ -f "${agent_dir}/env.template" ]; then
    pass "${agent_id}: env.template exists"
  else
    fail "${agent_id}: env.template missing"
  fi

  # WhatsApp config: account is set and valid
  if jq -e '.whatsapp.account' "${agent_dir}/agent.json" >/dev/null 2>&1; then
    wa_account=$(jq -r '.whatsapp.account' "${agent_dir}/agent.json")
    pass "${agent_id}: whatsapp.account is set (${wa_account})"
  else
    fail "${agent_id}: whatsapp.account missing"
  fi

  # WhatsApp config: dmPolicy is valid
  if jq -e '.whatsapp.dmPolicy' "${agent_dir}/agent.json" >/dev/null 2>&1; then
    dm_policy=$(jq -r '.whatsapp.dmPolicy' "${agent_dir}/agent.json")
    case "$dm_policy" in
      disabled|open|allowlist|pairing)
        pass "${agent_id}: whatsapp.dmPolicy is valid (${dm_policy})" ;;
      *)
        fail "${agent_id}: whatsapp.dmPolicy '${dm_policy}' is invalid" ;;
    esac
  fi

  # WhatsApp config: groupPolicy is valid
  if jq -e '.whatsapp.groupPolicy' "${agent_dir}/agent.json" >/dev/null 2>&1; then
    group_policy=$(jq -r '.whatsapp.groupPolicy' "${agent_dir}/agent.json")
    case "$group_policy" in
      disabled|open|allowlist|mention)
        pass "${agent_id}: whatsapp.groupPolicy is valid (${group_policy})" ;;
      *)
        fail "${agent_id}: whatsapp.groupPolicy '${group_policy}' is invalid" ;;
    esac
  fi

  # WhatsApp config: mentionPatterns is an array
  if jq -e '.whatsapp.groupChat.mentionPatterns | type == "array"' "${agent_dir}/agent.json" >/dev/null 2>&1; then
    pass "${agent_id}: whatsapp.groupChat.mentionPatterns is an array"
  fi

  # WhatsApp config: allowFrom / groupAllowFrom are valid E.164 arrays (if present)
  for af_field in allowFrom groupAllowFrom; do
    if jq -e ".whatsapp.${af_field}" "${agent_dir}/agent.json" >/dev/null 2>&1; then
      if jq -e ".whatsapp.${af_field} | type == \"array\"" "${agent_dir}/agent.json" >/dev/null 2>&1; then
        bad=$(jq -r ".whatsapp.${af_field}[] | select(test(\"^\\\\+[0-9]+$\") | not)" "${agent_dir}/agent.json" 2>/dev/null || true)
        if [ -z "$bad" ]; then
          pass "${agent_id}: whatsapp.${af_field} entries are valid E.164"
        else
          fail "${agent_id}: whatsapp.${af_field} has invalid entries: ${bad}"
        fi
      else
        fail "${agent_id}: whatsapp.${af_field} must be an array"
      fi
    fi
  done

  # env.template has WHATSAPP_NUMBER placeholder
  if [ -f "${agent_dir}/env.template" ]; then
    if grep -q "WHATSAPP_NUMBER" "${agent_dir}/env.template"; then
      pass "${agent_id}: env.template has WHATSAPP_NUMBER"
    else
      fail "${agent_id}: env.template missing WHATSAPP_NUMBER"
    fi
    if grep -q "WHATSAPP_ALLOW_FROM" "${agent_dir}/env.template"; then
      pass "${agent_id}: env.template has WHATSAPP_ALLOW_FROM"
    else
      fail "${agent_id}: env.template missing WHATSAPP_ALLOW_FROM"
    fi
  fi
done

# Test 6: validate-agents.sh runs successfully
if bash "${REPO_ROOT}/scripts/validate-agents.sh" >/dev/null 2>&1; then
  pass "validate-agents.sh passes"
else
  fail "validate-agents.sh fails"
fi

# Test 7: .gitignore blocks agent secrets
if grep -q 'agents/\*/.env' "${REPO_ROOT}/.gitignore"; then
  pass ".gitignore blocks agent .env files"
else
  fail ".gitignore does not block agent .env files"
fi

# Test 8: .gitignore blocks agent workspace data
if grep -q 'agents/\*/workspace' "${REPO_ROOT}/.gitignore"; then
  pass ".gitignore blocks agent workspace data"
else
  fail ".gitignore does not block agent workspace data"
fi

# Test 9: Agent docs exist
if [ -f "${REPO_ROOT}/docs/agents.md" ]; then
  pass "docs/agents.md exists"
else
  fail "docs/agents.md missing"
fi

# Test 10: Sample agent is defined
if [ -f "${REPO_ROOT}/agents/johndoe/agent.json" ]; then
  pass "johndoe sample agent defined"
else
  fail "johndoe sample agent missing"
fi

# Test 11: No duplicate WhatsApp accounts across agents
wa_accounts=()
duplicates=0
for agent_dir in "${REPO_ROOT}"/agents/*/; do
  [ -f "${agent_dir}/agent.json" ] || continue
  wa_acct=$(jq -r '.whatsapp.account // empty' "${agent_dir}/agent.json")
  [ -z "$wa_acct" ] && continue
  for existing in "${wa_accounts[@]+"${wa_accounts[@]}"}"; do
    if [ "$existing" = "$wa_acct" ]; then
      duplicates=$((duplicates + 1))
    fi
  done
  wa_accounts+=("$wa_acct")
done
if [ "$duplicates" -eq 0 ]; then
  pass "No duplicate WhatsApp accounts across agents"
else
  fail "${duplicates} duplicate WhatsApp account(s) found"
fi

# Test 12: Sample agent workspace has .gitkeep
if [ -f "${REPO_ROOT}/agents/johndoe/workspace/.gitkeep" ]; then
  pass "agents/johndoe/workspace/.gitkeep exists"
else
  fail "agents/johndoe/workspace/.gitkeep missing"
fi

# Summary
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
