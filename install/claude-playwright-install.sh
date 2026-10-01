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
  openssl \
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

msg_info "Installing Desktop Environment and RDP"
$STD apt install -y \
  xfce4 \
  xfce4-terminal \
  xrdp \
  dbus-x11
msg_ok "Installed Desktop Environment and RDP"

msg_info "Configuring RDP with TLS"
# Generate a self-signed TLS certificate for xrdp
openssl req -x509 -newkey rsa:4096 \
  -keyout /etc/xrdp/key.pem \
  -out /etc/xrdp/cert.pem \
  -days 3650 -nodes \
  -subj "/CN=$(hostname)" \
  2>/dev/null
chmod 600 /etc/xrdp/key.pem
chown xrdp:xrdp /etc/xrdp/key.pem
chmod 644 /etc/xrdp/cert.pem

# Force TLS and point to the generated cert/key
sed -i 's/^security_layer=.*/security_layer=tls/' /etc/xrdp/xrdp.ini
sed -i 's|^certificate=.*|certificate=/etc/xrdp/cert.pem|' /etc/xrdp/xrdp.ini
sed -i 's|^key_file=.*|key_file=/etc/xrdp/key.pem|' /etc/xrdp/xrdp.ini

# Use XFCE4 for all RDP sessions
printf '#!/bin/bash\nexec startxfce4\n' > /etc/skel/.xsession
chmod +x /etc/skel/.xsession
cp /etc/skel/.xsession /root/.xsession

systemctl enable -q xrdp
msg_ok "Configured RDP with TLS"

msg_info "Creating RDP user 'claude'"
RDP_PASS="$(openssl rand -base64 18 | tr -d '+/=' | head -c 20)"
useradd -m -s /bin/bash claude
echo "claude:${RDP_PASS}" | chpasswd
cp /etc/skel/.xsession /home/claude/.xsession
chown claude:claude /home/claude/.xsession

# Save credentials for the operator to retrieve
cat >/root/.rdp-credentials <<EOF
RDP User:     claude
RDP Password: ${RDP_PASS}
RDP Port:     3389
EOF
chmod 600 /root/.rdp-credentials
msg_ok "Created RDP user 'claude'"

msg_info "Configuring Claude Code MCP"
# Configure MCP for root
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

# Configure MCP for the claude user
mkdir -p /home/claude/.claude
cp /root/.claude/settings.json /home/claude/.claude/settings.json
chown -R claude:claude /home/claude/.claude
msg_ok "Configured Claude Code MCP"

msg_info "Setting Anthropic API Key"
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}" >>/etc/environment
  msg_ok "Set Anthropic API Key in /etc/environment"
else
  msg_info "No API key provided — add ANTHROPIC_API_KEY to /etc/environment later"
fi

msg_info "Creating MOTD"
cat <<'EOF' >/etc/update-motd.d/99-claude-playwright
#!/bin/bash
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║          Claude Code + Playwright MCP Container       ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  RDP: connect to port 3389 (user: claude)             ║"
echo "║    Credentials: /root/.rdp-credentials               ║"
echo "║                                                       ║"
echo "║  Claude Code (CLI):                                   ║"
echo "║    claude                                             ║"
echo "║                                                       ║"
echo "║  Playwright MCP pre-configured in:                    ║"
echo "║    ~/.claude/settings.json                           ║"
echo "║                                                       ║"
echo "║  Non-interactive task:                                ║"
echo "║    claude -p 'your task here'                        ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
EOF
chmod +x /etc/update-motd.d/99-claude-playwright
msg_ok "Created MOTD"

motd_ssh
customize
cleanup_lxc
