#!/usr/bin/env bash
# Validate prerequisites for deploying OpenClaw on GCP.
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
ERRORS=0

check_cmd() {
  local cmd="$1"
  local label="${2:-$cmd}"
  if command -v "$cmd" &>/dev/null; then
    printf "${GREEN}✓${NC} %s found: %s\n" "$label" "$(command -v "$cmd")"
  else
    printf "${RED}✗${NC} %s not found\n" "$label"
    ERRORS=$((ERRORS + 1))
  fi
}

echo "=== OpenClaw on GCP — Prerequisite Check ==="
echo ""

check_cmd terraform  "Terraform"
check_cmd gcloud     "Google Cloud SDK"
check_cmd make       "Make"
check_cmd jq         "jq"
check_cmd shellcheck "ShellCheck"

# Docker is installed on the remote GCP VM by startup.sh — not required locally.
if command -v docker &>/dev/null; then
  printf "${GREEN}✓${NC} Docker found locally (optional): %s\n" "$(command -v docker)"
else
  printf "  ℹ  Docker not found locally (not required — runs on the GCP VM)\n"
fi

echo ""

# Check gcloud auth
ACCOUNT=$(gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null | head -1)
if [ -n "$ACCOUNT" ]; then
  printf "${GREEN}✓${NC} gcloud authenticated as: %s\n" "$ACCOUNT"
else
  printf '%s✗%s gcloud not authenticated. Run: gcloud auth login\n' "$RED" "$NC"
  ERRORS=$((ERRORS + 1))
fi

# Check project
if [ -n "${TF_VAR_project_id:-}" ]; then
  printf "${GREEN}✓${NC} GCP project: %s\n" "$TF_VAR_project_id"
else
  printf '%s✗%s GCP project not set. Export TF_VAR_project_id or set in terraform.tfvars\n' "$RED" "$NC"
  ERRORS=$((ERRORS + 1))
fi

echo ""
if [ "$ERRORS" -eq 0 ]; then
  printf '%sAll prerequisites met.%s\n' "$GREEN" "$NC"
else
  printf "${RED}%d prerequisite(s) missing. Please fix before proceeding.${NC}\n" "$ERRORS"
  exit 1
fi
