#!/usr/bin/env bash
# Provision agent tooling on the OpenClaw GCP VM.
# Safe to run multiple times — fully idempotent.
# Usage: make vm-provision
set -euo pipefail

OPENCLAW_USER="openclaw"
OPENCLAW_HOME="/home/${OPENCLAW_USER}"
VENV_DIR="${OPENCLAW_HOME}/venv"
LOG_FILE="/var/log/openclaw-provision.log"

log() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*" | tee -a "$LOG_FILE"; }

log "=== OpenClaw VM Provisioning ==="

# python3 and python3-venv are separate packages on Debian — install both
log "Installing Python 3 + venv..."
apt-get update -qq
apt-get install -y -qq python3 python3-venv
log "  $(python3 --version)"

# Recreate the venv if missing or broken (pip absent = broken from a prior failed run)
log "Setting up venv at ${VENV_DIR}..."
if [ ! -x "${VENV_DIR}/bin/pip" ]; then
  rm -rf "${VENV_DIR}"
  python3 -m venv "${VENV_DIR}"
fi

# Add packages here as agent skills require them, then re-run make vm-provision
"${VENV_DIR}/bin/pip" install --quiet --upgrade \
  requests \
  beautifulsoup4 \
  lxml
chown -R "${OPENCLAW_USER}:${OPENCLAW_USER}" "${VENV_DIR}"

# Add future tool sections here (e.g. GitHub CLI, himalaya)

log "=== Provisioning complete ==="
"${VENV_DIR}/bin/python3" -c "import requests, bs4; print('requests + beautifulsoup4 OK')"
