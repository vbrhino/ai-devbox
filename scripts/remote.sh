#!/usr/bin/env bash
# ============================================================================
# remote.sh — Start Cloudflare Tunnel for remote SSH access
# ============================================================================
# Run this on your Ubuntu machine to give pi remote access.
# It creates a secure HTTPS tunnel through Cloudflare.
#
# Usage:
#   ~/ai-devbox/scripts/remote.sh
#   ~/ai-devbox/scripts/remote.sh --bg     # run in background
# ============================================================================
set -euo pipefail

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }

# Check cloudflared
if ! command -v cloudflared &>/dev/null; then
  echo "Installing cloudflared..."
  sudo curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
  sudo chmod +x /usr/local/bin/cloudflared
fi

# Start tunnel
if [ "${1:-}" = "--bg" ]; then
  nohup cloudflared tunnel --url ssh://localhost:22 > /tmp/cloudflared.log 2>&1 &
  sleep 3
  URL=$(grep -o 'https://[a-z0-9.-]*\.trycloudflare\.com' /tmp/cloudflared.log 2>/dev/null | head -1 || echo "(check /tmp/cloudflared.log)")
  echo "Tunnel started in background."
  echo "URL: $URL"
  echo "Share this URL with pi to connect."
else
  cloudflared tunnel --url ssh://localhost:22
fi
