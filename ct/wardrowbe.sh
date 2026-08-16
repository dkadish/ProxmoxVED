#!/usr/bin/env bash
# Engine comes from community-scripts/core; this repo only ships the scripts.
# A local core checkout wins (COMMUNITY_SCRIPTS_CORE_DIR, else a sibling ../core),
# so a fork or branch of core can be tested without editing this file.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: David Kadish (dkadish)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Anyesh/wardrowbe

APP="Wardrowbe"
var_tags="${var_tags:-ai;lifestyle}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/wardrowbe ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "wardrowbe" "Anyesh/wardrowbe"; then
    msg_info "Stopping Services"
    systemctl stop wardrowbe-frontend wardrowbe-worker wardrowbe-backend
    msg_ok "Stopped Services"

    create_backup /opt/wardrowbe/backend/.env /opt/wardrowbe/frontend/.env

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "wardrowbe" "Anyesh/wardrowbe" "tarball"

    restore_backup

    msg_info "Updating Backend"
    cd /opt/wardrowbe/backend
    $STD uv venv --python 3.12 /opt/wardrowbe/backend/.venv
    $STD uv pip install --python /opt/wardrowbe/backend/.venv \
      -r requirements.txt \
      -r requirements-extras.txt
    DATABASE_URL="$(grep -E '^DATABASE_URL=' /opt/wardrowbe/backend/.env | cut -d= -f2-)" \
      $STD /opt/wardrowbe/backend/.venv/bin/alembic upgrade head
    msg_ok "Updated Backend"

    msg_info "Rebuilding Frontend"
    cd /opt/wardrowbe/frontend
    $STD npm ci
    $STD npm run build
    msg_ok "Rebuilt Frontend"

    msg_info "Starting Services"
    systemctl start wardrowbe-backend wardrowbe-worker wardrowbe-frontend
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
