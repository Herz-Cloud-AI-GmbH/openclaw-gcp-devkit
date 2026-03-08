#!/usr/bin/env bash
# Startup script for the OpenClaw GCP Compute Engine instance.
# This script runs as root on first boot via metadata_startup_script.
set -euo pipefail

OPENCLAW_USER="openclaw"
OPENCLAW_HOME="/home/${OPENCLAW_USER}"
OPENCLAW_DATA="${OPENCLAW_HOME}/.openclaw"
LOG_FILE="/var/log/openclaw-startup.log"

log() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*" | tee -a "$LOG_FILE"; }

# ------------------------------------------------------------------
# 1. System packages + Docker CE from official repo
# ------------------------------------------------------------------
log "Installing base dependencies..."
apt-get update -qq
apt-get install -y -qq jq curl ca-certificates gnupg

log "Adding Docker official GPG key and repository..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
# shellcheck source=/dev/null
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

log "Installing Docker CE and Compose plugin..."
apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin

# ------------------------------------------------------------------
# 2. Create dedicated user
# ------------------------------------------------------------------
if ! id "$OPENCLAW_USER" &>/dev/null; then
  log "Creating user ${OPENCLAW_USER}..."
  useradd -m -s /bin/bash "$OPENCLAW_USER"
fi
usermod -aG docker "$OPENCLAW_USER"

# ------------------------------------------------------------------
# 3. Enable and start Docker
# ------------------------------------------------------------------
systemctl enable docker
systemctl start docker

# ------------------------------------------------------------------
# 4. Prepare OpenClaw data directories (host bind mounts)
#    These survive container rebuilds, Docker reinstalls, and volume
#    prunes — the host filesystem is the source of truth.
# ------------------------------------------------------------------
log "Preparing OpenClaw data directories..."
mkdir -p "${OPENCLAW_DATA}/workspace"
chown -R "${OPENCLAW_USER}:${OPENCLAW_USER}" "${OPENCLAW_HOME}"

# ------------------------------------------------------------------
# 5. Create docker-compose.yml
# ------------------------------------------------------------------
log "Writing docker-compose.yml..."
cat > "${OPENCLAW_HOME}/docker-compose.yml" <<COMPOSE
services:
  openclaw:
    image: ghcr.io/openclaw/openclaw:latest
    container_name: openclaw
    restart: unless-stopped
    env_file:
      - .env
    environment:
      - HOME=/home/node
      - NODE_ENV=production
      - TERM=xterm-256color
      - XDG_CONFIG_HOME=/home/node/.openclaw
      - OPENCLAW_GATEWAY_BIND=lan
      - OPENCLAW_GATEWAY_PORT=18789
    ports:
      - "127.0.0.1:18789:18789"
    volumes:
      - ${OPENCLAW_DATA}:/home/node/.openclaw
      - ${OPENCLAW_DATA}/workspace:/home/node/.openclaw/workspace
    command: ["node", "dist/index.js", "gateway", "--bind", "lan", "--port", "18789"]
COMPOSE

chown "${OPENCLAW_USER}:${OPENCLAW_USER}" "${OPENCLAW_HOME}/docker-compose.yml"

# ------------------------------------------------------------------
# 6. Create default .env if not present
# ------------------------------------------------------------------
if [ ! -f "${OPENCLAW_HOME}/.env" ]; then
  log "Creating default .env file..."
  GENERATED_TOKEN=$(openssl rand -hex 32)
  GENERATED_KEYRING=$(openssl rand -hex 16)
  cat > "${OPENCLAW_HOME}/.env" <<ENV
# Gateway authentication token (auto-generated on first boot)
OPENCLAW_GATEWAY_TOKEN=${GENERATED_TOKEN}

# Gateway keyring password (protects stored OAuth tokens / secrets)
GOG_KEYRING_PASSWORD=${GENERATED_KEYRING}

# OpenClaw Model Provider Configuration
# Uncomment and fill in the provider you want to use.

# --- Anthropic Claude (recommended) ---
# ANTHROPIC_API_KEY=sk-ant-...

# --- OpenAI GPT ---
# OPENAI_API_KEY=sk-...

# --- Google Gemini ---
# GOOGLE_GENERATIVE_AI_API_KEY=...

# --- KIMI K2.5 (Moonshot AI) ---
# MOONSHOT_API_KEY=sk-...

# --- GitHub Copilot (uses your GitHub token with Copilot subscription) ---
# GITHUB_TOKEN=ghp-...
ENV
  chown "${OPENCLAW_USER}:${OPENCLAW_USER}" "${OPENCLAW_HOME}/.env"
fi

# ------------------------------------------------------------------
# 7. Pull image and start OpenClaw
# ------------------------------------------------------------------
log "Pulling OpenClaw Docker image..."
docker pull ghcr.io/openclaw/openclaw:latest

log "Starting OpenClaw..."
cd "${OPENCLAW_HOME}"
sudo -u "${OPENCLAW_USER}" docker compose up -d

# Configure gateway mode and allowed origins for the Control UI.
# Uses a throwaway container to write config to the shared volume,
# then restarts the running container to pick up the changes.
log "Configuring gateway..."
docker run --rm \
  -v "${OPENCLAW_DATA}:/home/node/.openclaw" \
  ghcr.io/openclaw/openclaw:latest \
  node dist/index.js config set gateway.mode local 2>/dev/null || true
docker run --rm \
  -v "${OPENCLAW_DATA}:/home/node/.openclaw" \
  ghcr.io/openclaw/openclaw:latest \
  node dist/index.js config set gateway.controlUi.allowedOrigins '["http://127.0.0.1:18789"]' \
  --strict-json 2>/dev/null || true

# Restart to pick up config changes.
docker restart openclaw 2>/dev/null || true

log "Startup complete. OpenClaw is running on 127.0.0.1:18789"
