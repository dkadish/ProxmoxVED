#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/dkadish/ProxmoxVED/ubuntu-claude-playwright"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Author: David Kadish
# License: MIT
# Source: https://claude.ai | https://playwright.dev

APP="Claude-Playwright"
var_tags="${var_tags:-ai;automation}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /usr/local/bin/claude ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating Claude Code"
  $STD npm update -g @anthropic-ai/claude-code
  msg_ok "Updated Claude Code"
  msg_info "Updating Playwright MCP"
  $STD npm update -g @playwright/mcp
  msg_ok "Updated Playwright MCP"
  msg_info "Updating ${APP} LXC"
  apt_update_safe
  $STD apt -y upgrade
  msg_ok "Updated ${APP} LXC"
  msg_ok "Updated successfully!"
  exit
}

start

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  if command -v whiptail &>/dev/null && [ -t 0 ] && [[ "$TERM" != "dumb" ]]; then
    ANTHROPIC_API_KEY=$(whiptail \
      --backtitle "Proxmox VE Helper Scripts" \
      --title "ANTHROPIC API KEY" \
      --passwordbox "\nEnter your Anthropic API key (sk-ant-...):\n(Leave empty to configure later)" \
      10 60 3>&1 1>&2 2>&3) || true
  fi
fi
export ANTHROPIC_API_KEY

build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}RDP access: ${BGN}${IP}:3389${CL}"
echo -e "${INFO}${YW}RDP credentials are saved in the container at: ${BGN}/root/.rdp-credentials${CL}"
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo -e "${INFO}${YW}No API key provided — set ${BGN}ANTHROPIC_API_KEY${YW} in ${BGN}/etc/environment${YW} inside the container${CL}"
fi
