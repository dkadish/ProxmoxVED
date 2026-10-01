#!/usr/bin/env bash

# Author: David Kadish
# License: MIT
# Source: https://claude.ai | https://playwright.dev

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  curl \
  git \
  unzip \
  wget \
  ca-certificates \
  gnupg \
  xvfb \
  fonts-liberation \
  fonts-noto-color-emoji \
  libasound2t64 \
  libatk-bridge2.0-0 \
  libatk1.0-0 \
  libcups2 \
  libdbus-1-3 \
  libdrm2 \
  libgbm1 \
  libgtk-3-0 \
  libnspr4 \
  libnss3 \
  libx11-xcb1 \
  libxcomposite1 \
  libxdamage1 \
  libxfixes3 \
  libxkbcommon0 \
  libxrandr2 \
  libxshmfence1 \
  libxtst6
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

msg_info "Installing Claude Code"
$STD npm install -g @anthropic-ai/claude-code
msg_ok "Installed Claude Code"

msg_info "Installing Playwright MCP"
$STD npm install -g @playwright/mcp
msg_ok "Installed Playwright MCP"

msg_info "Installing Playwright Chromium"
# Use the playwright binary bundled with @playwright/mcp to ensure version compatibility
PLAYWRIGHT_CLI="$(npm root -g)/@playwright/mcp/node_modules/.bin/playwright"
$STD "$PLAYWRIGHT_CLI" install chromium --with-deps
msg_ok "Installed Playwright Chromium"

msg_info "Configuring Claude Code MCP"
mkdir -p /root/.claude
cat <<'EOF' >/root/.claude/settings.json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": [
        "@playwright/mcp@latest",
        "--headless",
        "--no-sandbox"
      ]
    }
  }
}
EOF
msg_ok "Configured Claude Code MCP"

msg_info "Creating MOTD"
cat <<'EOF' >/etc/update-motd.d/99-claude-playwright
#!/bin/bash
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║          Claude Code + Playwright MCP Container       ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  To get started:                                      ║"
echo "║    export ANTHROPIC_API_KEY=sk-ant-...               ║"
echo "║    claude                                             ║"
echo "║                                                       ║"
echo "║  Playwright MCP is pre-configured in:                 ║"
echo "║    ~/.claude/settings.json                           ║"
echo "║                                                       ║"
echo "║  To run Claude tasks non-interactively:               ║"
echo "║    ANTHROPIC_API_KEY=sk-ant-... claude -p 'task'     ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
EOF
chmod +x /etc/update-motd.d/99-claude-playwright
msg_ok "Created MOTD"

motd_ssh
customize
cleanup_lxc
