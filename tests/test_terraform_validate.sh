#!/usr/bin/env bash
# Test: Terraform configuration is valid.
set -euo pipefail

TF_DIR="$(cd "$(dirname "$0")/../terraform" && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }

echo "=== Terraform Validation Tests ==="

# Test 1: Required files exist
for f in main.tf variables.tf compute.tf network.tf iam.tf outputs.tf; do
  if [ -f "${TF_DIR}/${f}" ]; then
    pass "${f} exists"
  else
    fail "${f} missing"
  fi
done

# Test 2: terraform init succeeds
echo ""
echo "--- terraform init ---"
if terraform -chdir="$TF_DIR" init -backend=false -input=false >/dev/null 2>&1; then
  pass "terraform init succeeded"
else
  fail "terraform init failed"
fi

# Test 3: terraform validate succeeds
echo ""
echo "--- terraform validate ---"
if terraform -chdir="$TF_DIR" validate >/dev/null 2>&1; then
  pass "terraform validate succeeded"
else
  fail "terraform validate failed"
fi

# Summary
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
