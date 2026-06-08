#!/usr/bin/env bash
# ============================================================================
# ai-devbox — AI Workstation bootstrap (Ubuntu + Nix home-manager)
#
# Works on: Ubuntu 24.04 LTS (WSL2 or bare-metal)
# GPU setup handled separately (see after-gpu-swap.sh)
# ============================================================================
set -euo pipefail

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERR]${NC}   $*"; }

FLAKE_DIR="${FLAKE_DIR:-$(cd "$(dirname "$0")" && pwd)}"

# ── 0. Detect environment ─────────────────────────────────────────────────
IS_WSL=false
if grep -qi microsoft /proc/version 2>/dev/null; then
  IS_WSL=true
  info "Detected: WSL environment"
else
  info "Detected: native Linux environment"
fi

# ── 1. Install required system packages ──────────────────────────────────
info "Installing required system packages..."
sudo apt update -qq
sudo apt install -y -qq \
  git curl ca-certificates \
  >/dev/null
ok "System packages installed"

# ── 2. Install Nix (multi-user via Determinate Systems) ──────────────────
if ! command -v nix &>/dev/null; then
  info "Installing Nix package manager..."
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null || true
  . "$HOME/.nix-profile/etc/profile.d/nix.sh" 2>/dev/null || true
  ok "Nix installed"
else
  ok "Nix already installed"
fi

export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"

# ── 3. Enable flakes ─────────────────────────────────────────────────────
mkdir -p "$HOME/.config/nix"
if ! grep -q "experimental-features" "$HOME/.config/nix/nix.conf" 2>/dev/null; then
  echo "experimental-features = nix-command flakes" >> "$HOME/.config/nix/nix.conf"
  ok "Flakes enabled"
fi

# ── 4. Configure GitHub token for Nix (avoids API rate limits) ──────────
if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
  GH_TOKEN=$(gh auth token 2>/dev/null)
  if [ -n "$GH_TOKEN" ] && ! grep -q "access-tokens" "$HOME/.config/nix/nix.conf" 2>/dev/null; then
    echo "access-tokens = github.com=$GH_TOKEN" >> "$HOME/.config/nix/nix.conf"
    ok "GitHub token configured for Nix"
  fi
fi

# ── 5. Init local git repo (Nix flakes need one) ─────────────────────────
if [ ! -d "$FLAKE_DIR/.git" ]; then
  info "Initialising local git repo for Nix flakes..."
  git -C "$FLAKE_DIR" init -q
  git -C "$FLAKE_DIR" add -A
  git -C "$FLAKE_DIR" -c user.name="install" -c user.email="install@local" commit -qm "init"
  ok "Local git repo initialised"
fi

git config --global --get-all safe.directory 2>/dev/null | grep -qxF "$FLAKE_DIR" \
  || git config --global --add safe.directory "$FLAKE_DIR"

# ── 6. Build & activate home-manager ─────────────────────────────────────
info "Building and activating home-manager profile (first run: 5-15 min)..."
nix run home-manager -- switch --flake "${FLAKE_DIR}#default" --impure --no-write-lock-file -b backup
ok "home-manager activated!"

# Re-source session vars
__HM_SESS_VARS_SOURCED=
. "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" 2>/dev/null || true

# ── 7. Install extra tools (not managed by Nix) ──────────────────────────
. "$FLAKE_DIR/scripts/extras.sh"
install_ollama
install_tailscale
install_python_ml_stack
install_llamacpp

# ── 8. Set zsh as default shell ──────────────────────────────────────────
ZSH_PATH="$HOME/.nix-profile/bin/zsh"
if [ -x "$ZSH_PATH" ]; then
  CURRENT_SHELL=$(getent passwd "$USER" | cut -d: -f7)
  if [ "$CURRENT_SHELL" != "$ZSH_PATH" ]; then
    if ! grep -qF "$ZSH_PATH" /etc/shells 2>/dev/null; then
      echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
    fi
    info "Changing default shell to zsh (needs sudo)..."
    sudo chsh -s "$ZSH_PATH" "$USER"
    ok "Default shell set to zsh"
  else
    ok "Shell is already zsh"
  fi
fi

# ── 9. Create setup script symlink for easy access ───────────────────────
mkdir -p "$HOME/.local/bin"
ln -sf "$FLAKE_DIR/scripts/setup.sh" "$HOME/.local/bin/ai-devbox-setup"
ln -sf "$FLAKE_DIR/scripts/update.sh" "$HOME/.local/bin/ai-devbox-update"
ok "Symlinks created: ai-devbox-setup, ai-devbox-update"

# ── 10. Set up Docker (WSL: use Windows Docker; bare-metal: install native)
if $IS_WSL; then
  info "WSL detected — Docker will use Rancher Desktop / Docker Desktop (Windows)"
  ok "Docker on Windows — make sure WSL integration is enabled in Docker Desktop"
else
  info "Native Linux — installing Docker Engine..."
  if ! command -v dockerd &>/dev/null; then
    sudo apt install -y -qq docker.io docker-compose 2>/dev/null || {
      curl -fsSL https://get.docker.com | sudo sh
    }
    sudo systemctl enable --now docker 2>/dev/null || true
    sudo usermod -aG docker "$USER"
    ok "Docker Engine installed"
  else
    ok "Docker already installed"
  fi
fi

# ── 11. sysctl tuning ────────────────────────────────────────────────────
info "Tuning kernel parameters..."
SYSCTL_CONF="/etc/sysctl.d/99-ai-devbox.conf"
SYSCTL_CONTENT="# ai-devbox — tuned for AI workloads
fs.inotify.max_user_instances = 1024
fs.inotify.max_user_watches   = 524288
fs.inotify.max_queued_events  = 65536
vm.nr_hugepages = 4096
vm.max_map_count = 1048576
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728"

if [ ! -f "$SYSCTL_CONF" ]; then
  echo "$SYSCTL_CONTENT" | sudo tee "$SYSCTL_CONF" >/dev/null
  sudo sysctl --system >/dev/null 2>&1
  ok "Kernel parameters tuned"
else
  ok "Kernel parameters already configured"
fi

# ── 12. Ensure Nix profile is sourced for login shells ────────────────────
PROFILE="$HOME/.profile"
NIX_SOURCE='
# Nix
if [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
  . "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi
# home-manager session variables
if [ -e "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
  . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
fi'

if ! grep -q "hm-session-vars" "$PROFILE" 2>/dev/null; then
  echo "$NIX_SOURCE" >> "$PROFILE"
  ok "Nix profile added to ~/.profile"
fi

# ── 13. MOTD ─────────────────────────────────────────────────────────────
info "Creating welcome banner..."
sudo mkdir -p /etc/update-motd.d
cat | sudo tee /etc/update-motd.d/99-ai-devbox >/dev/null << 'MOTD'
#!/bin/bash
echo ""
echo "  🤖  AI Devbox — Ubuntu 24.04 LTS"
echo "  ⚡  Run 'ai-devbox-setup' for initial config"
echo "  🌐  Open WebUI: http://$(hostname -I 2>/dev/null | awk '{print $1}'):3000"
echo "  📦  Ollama:     http://$(hostname -I 2>/dev/null | awk '{print $1}'):11434"
echo "  📊  Status:     ~/status.sh"
echo ""
MOTD
sudo chmod +x /etc/update-motd.d/99-ai-devbox
ok "Welcome banner installed"

# ── 14. Status script ────────────────────────────────────────────────────
cat > "$HOME/status.sh" << 'STATUS'
#!/bin/bash
echo "╔═══════════════════════════════════════════╗"
echo "║         AI Devbox — System Status         ║"
echo "╚═══════════════════════════════════════════╝"
echo ""
echo "── Uptime ──"
uptime -p
echo ""
echo "── GPU ──"
if command -v rocm-smi &>/dev/null; then
  sudo rocm-smi --showproductname --showuse 2>/dev/null || echo "(no AMD GPU detected)"
fi
if command -v nvidia-smi &>/dev/null; then
  nvidia-smi --query-gpu=name,memory.used,memory.total,temperature.gpu --format=csv,noheader 2>/dev/null || true
fi
echo ""
echo "── Ollama Models ──"
curl -s http://localhost:11434/api/tags 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for m in data.get('models', []):
        name = m.get('name', '?')
        size = m.get('size', 0)
        print(f'  {name}  ({size/1e9:.1f} GB)')
except: print('  (none loaded or Ollama not running)')
" 2>/dev/null || echo "  Ollama not reachable"
echo ""
echo "── Docker ──"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "  Docker not running"
echo ""
echo "── Disk ──"
df -h / /data 2>/dev/null || df -h /
echo ""
echo "── Memory ──"
free -h
echo ""
echo "── Tailscale ──"
tailscale status 2>/dev/null || echo "  Tailscale not configured"
STATUS
chmod +x "$HOME/status.sh"
ok "Status script: ~/status.sh"

# ── 15. Create after-gpu-swap script (for post-GPU-swap) ─────────────────
chmod +x "$FLAKE_DIR/scripts/after-gpu-swap.sh"
ok "Post-swap script: ~/ai-devbox/scripts/after-gpu-swap.sh"
ok "Post-swap script: ~/ai-devbox/scripts/after-gpu-swap.sh"

# ── Done ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           ✅  ai-devbox Install Complete!                    ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  Next steps:                                                 ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  1. Re-login or open new terminal for zsh                    ║${NC}"
echo -e "${GREEN}║  2. Run the setup script:                                    ║${NC}"
echo -e "${GREEN}║       ai-devbox-setup                                         ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  3. Configure Tailscale:                                     ║${NC}"
echo -e "${GREEN}║       sudo tailscale up                                       ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  4. Start the AI stack:                                      ║${NC}"
echo -e "${GREEN}║       ollama pull llama3.2:3b  # test model                  ║${NC}"
echo -e "${GREEN}║       open-webui               # start web UI               ║${NC}"
echo -e "${GREEN}║       ~/status.sh              # check everything           ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  5. After GPU swap (Wed/Thu):                                ║${NC}"
echo -e "${GREEN}║       sudo ~/ai-devbox/scripts/after-gpu-swap.sh            ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
