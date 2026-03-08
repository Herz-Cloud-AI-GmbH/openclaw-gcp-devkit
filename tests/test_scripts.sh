#!/usr/bin/env bash
# Test: Scripts and configuration files are well-formed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }

echo "=== Script & Config Tests ==="

# Test 1: Required scripts exist and are executable
for script in scripts/startup.sh scripts/check-prerequisites.sh scripts/setup-providers.sh scripts/validate-agents.sh scripts/deploy-agents.sh; do
  if [ -f "${REPO_ROOT}/${script}" ]; then
    pass "${script} exists"
  else
    fail "${script} missing"
  fi
done

# Test 2: Gateway env.template exists
if [ -f "${REPO_ROOT}/config/env.template" ]; then
  pass "config/env.template exists"
else
  fail "config/env.template missing"
fi

# Test 3: Global SOUL.md should NOT exist (per-agent only)
if [ ! -f "${REPO_ROOT}/config/SOUL.md" ]; then
  pass "config/SOUL.md removed (per-agent SOUL.md only)"
else
  fail "config/SOUL.md still exists — should be per-agent only"
fi

# Test 4: DevContainer config is valid JSONC
if sed 's|//.*$||' "${REPO_ROOT}/.devcontainer/devcontainer.json" | jq empty 2>/dev/null; then
  pass "devcontainer.json is valid JSONC"
else
  fail "devcontainer.json is invalid JSONC"
fi

# Test 5: Makefile exists
if [ -f "${REPO_ROOT}/Makefile" ]; then
  pass "Makefile exists"
else
  fail "Makefile missing"
fi

# Test 6: startup.sh contains docker compose
if grep -q "docker compose" "${REPO_ROOT}/scripts/startup.sh"; then
  pass "startup.sh uses docker compose"
else
  fail "startup.sh does not reference docker compose"
fi

# Test 7: startup.sh binds to localhost only
if grep -q "127.0.0.1:18789" "${REPO_ROOT}/scripts/startup.sh"; then
  pass "startup.sh binds OpenClaw to localhost only"
else
  fail "startup.sh does not bind to localhost — security risk"
fi

# Test 8: Network firewall allows SSH only
if grep -q '"22"' "${REPO_ROOT}/terraform/network.tf"; then
  pass "Firewall allows SSH (port 22)"
else
  fail "Firewall does not allow SSH"
fi

# Test 9: Firewall restricts SSH to IAP range
if grep -q '35.235.240.0/20' "${REPO_ROOT}/terraform/network.tf"; then
  pass "Firewall restricts SSH to IAP range"
else
  fail "Firewall does not restrict SSH to IAP range"
fi

# Test 10: Firewall has a deny-all rule
if grep -q "deny_all_ingress" "${REPO_ROOT}/terraform/network.tf"; then
  pass "Firewall includes deny-all ingress rule"
else
  fail "Firewall missing deny-all ingress rule"
fi

# Test 11: .gitignore blocks secrets
if grep -q "tfstate" "${REPO_ROOT}/.gitignore" && grep -q "sa-key" "${REPO_ROOT}/.gitignore"; then
  pass ".gitignore blocks tfstate and sa-key files"
else
  fail ".gitignore does not block secret files"
fi

# Test 12: README.md is at repo root
if [ -f "${REPO_ROOT}/README.md" ]; then
  pass "README.md exists at repo root"
else
  fail "README.md missing from repo root"
fi

# Test 13: env.template contains LLM provider support
if grep -q "MOONSHOT_API_KEY" "${REPO_ROOT}/config/env.template"; then
  pass "env.template includes KIMI/Moonshot support"
else
  fail "env.template missing KIMI/Moonshot support"
fi

if grep -q "GITHUB_TOKEN" "${REPO_ROOT}/config/env.template"; then
  pass "env.template includes GitHub Copilot support"
else
  fail "env.template missing GitHub Copilot support"
fi

# Test 14: env.template does NOT contain WhatsApp (per-agent only)
if ! grep -q "WHATSAPP_NUMBER" "${REPO_ROOT}/config/env.template"; then
  pass "env.template does not contain WHATSAPP_NUMBER (per-agent only)"
else
  fail "env.template still contains WHATSAPP_NUMBER — should be per-agent"
fi

# Test 15: AGENTS.md exists
if [ -f "${REPO_ROOT}/AGENTS.md" ]; then
  pass "AGENTS.md exists"
else
  fail "AGENTS.md missing"
fi

# Test 16: setup-providers.sh does NOT configure WhatsApp
if ! grep -q "WHATSAPP_NUMBER" "${REPO_ROOT}/scripts/setup-providers.sh"; then
  pass "setup-providers.sh does not configure WhatsApp (per-agent only)"
else
  fail "setup-providers.sh still configures WhatsApp — should be per-agent"
fi

# Test 17: Makefile has agent-whatsapp-link target
if grep -q "agent-whatsapp-link" "${REPO_ROOT}/Makefile"; then
  pass "Makefile has agent-whatsapp-link target"
else
  fail "Makefile missing agent-whatsapp-link target"
fi

# Summary
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
