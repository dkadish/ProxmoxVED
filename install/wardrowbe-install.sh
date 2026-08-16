#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: David Kadish (dkadish)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Anyesh/wardrowbe

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# AI backend selection: an existing OpenAI-compatible/Ollama endpoint is reused
# as-is; leaving it blank installs Ollama locally in this container.
var_ai_base_url="${var_ai_base_url:-}"
var_ai_api_key="${var_ai_api_key:-}"
var_ai_vision_model="${var_ai_vision_model:-llava:7b}"
var_ai_text_model="${var_ai_text_model:-gemma3}"

if [[ -z "${var_ai_base_url:-}" ]]; then
  read -rp "${TAB3}Existing Ollama/OpenAI-compatible endpoint URL (blank installs Ollama locally): " var_ai_base_url
fi

if [[ -n "$var_ai_base_url" ]]; then
  AI_BASE_URL="$var_ai_base_url"
  AI_API_KEY="${var_ai_api_key:-not-needed}"
else
  AI_BASE_URL="http://127.0.0.1:11434/v1"
  AI_API_KEY="not-needed"
fi

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  libpq-dev \
  libheif1 \
  libde265-0 \
  libglib2.0-0 \
  libgomp1 \
  redis-server
systemctl enable -q --now redis-server
msg_ok "Installed Dependencies"

PG_VERSION="16" setup_postgresql
PG_DB_NAME="wardrobe" PG_DB_USER="wardrobe" setup_postgresql_db
NODE_VERSION="22" setup_nodejs
UV_PYTHON="3.12" setup_uv

if [[ -z "$var_ai_base_url" ]]; then
  msg_info "Installing Ollama"
  $STD bash -c "curl -fsSL https://ollama.com/install.sh | sh"
  for _ in $(seq 1 30); do
    curl -fsS http://127.0.0.1:11434/api/version >/dev/null 2>&1 && break
    sleep 2
  done
  msg_ok "Installed Ollama"

  msg_info "Pulling AI Models (Patience)"
  $STD ollama pull "$var_ai_vision_model"
  $STD ollama pull "$var_ai_text_model"
  msg_ok "Pulled AI Models"
fi

fetch_and_deploy_gh_release "wardrowbe" "Anyesh/wardrowbe" "tarball"

msg_info "Setting up Python Environment"
cd /opt/wardrowbe/backend
$STD uv venv --python 3.12 /opt/wardrowbe/backend/.venv
$STD uv pip install --python /opt/wardrowbe/backend/.venv \
  -r requirements.txt \
  -r requirements-extras.txt
msg_ok "Set up Python Environment"

msg_info "Downloading Background Removal Model"
$STD /opt/wardrowbe/backend/.venv/bin/python -c "from rembg import new_session; new_session()"
msg_ok "Downloaded Background Removal Model"

msg_info "Configuring Wardrowbe"
mkdir -p /opt/wardrowbe-data/wardrobe
cat <<EOF >/opt/wardrowbe/backend/.env
DEBUG=true
SECRET_KEY=$(openssl rand -hex 32)
DATABASE_URL=postgresql+asyncpg://wardrobe:${PG_DB_PASS}@localhost:5432/wardrobe
REDIS_URL=redis://127.0.0.1:6379/0
STORAGE_PATH=/opt/wardrowbe-data/wardrobe
CORS_ORIGINS=["http://${LOCAL_IP}:3000","http://localhost:3000"]
AI_BASE_URL=${AI_BASE_URL}
AI_API_KEY=${AI_API_KEY}
AI_VISION_MODEL=${var_ai_vision_model}
AI_TEXT_MODEL=${var_ai_text_model}
AI_INTERNAL_ENABLED=true
EOF
cat <<EOF >/opt/wardrowbe/frontend/.env
NODE_ENV=production
PORT=3000
HOSTNAME=0.0.0.0
BACKEND_URL=http://127.0.0.1:8000
NEXTAUTH_URL=http://${LOCAL_IP}:3000
NEXTAUTH_SECRET=$(openssl rand -hex 32)
DEV_MODE=true
EOF
msg_ok "Configured Wardrowbe"

msg_info "Running Database Migrations"
cd /opt/wardrowbe/backend
DATABASE_URL="postgresql+asyncpg://wardrobe:${PG_DB_PASS}@localhost:5432/wardrobe" \
  $STD /opt/wardrowbe/backend/.venv/bin/alembic upgrade head
msg_ok "Ran Database Migrations"

msg_info "Building Frontend"
cd /opt/wardrowbe/frontend
$STD npm ci
$STD npm run build
msg_ok "Built Frontend"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/wardrowbe-backend.service
[Unit]
Description=Wardrowbe Backend
Wants=network-online.target
After=network-online.target postgresql.service redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/wardrowbe/backend
ExecStart=/opt/wardrowbe/backend/.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/wardrowbe-worker.service
[Unit]
Description=Wardrowbe Worker
Wants=network-online.target
After=network-online.target wardrowbe-backend.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/wardrowbe/backend
ExecStart=/opt/wardrowbe/backend/.venv/bin/arq app.workers.worker.WorkerSettings
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/wardrowbe-frontend.service
[Unit]
Description=Wardrowbe Frontend
Wants=network-online.target
After=network-online.target wardrowbe-backend.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/wardrowbe/frontend
EnvironmentFile=/opt/wardrowbe/frontend/.env
ExecStart=/opt/wardrowbe/frontend/node_modules/.bin/next start -H 0.0.0.0 -p 3000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now wardrowbe-backend wardrowbe-worker wardrowbe-frontend
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
