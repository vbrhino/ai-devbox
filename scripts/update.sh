#!/usr/bin/env bash
#
# update.sh — update ai-devbox: system + Nix + extras
# Idempotent — safe to re-run anytime.
set -euo pipefail

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }

for f in "$HOME/.nix-profile/etc/profile.d/nix.sh" "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"; do
  [[ -f "$f" ]] && . "$f"
done
export PATH="$HOME/.nix-profile/bin:$HOME/.local/bin:$PATH"

FLAKE_DIR="${FLAKE_DIR:-$HOME/ai-devbox}"

# ── 1. Ubuntu system updates ─────────────────────────────────────────────
info "Updating Ubuntu system packages..."
sudo apt update && sudo apt upgrade -y
ok "Ubuntu packages updated"

# ── 2. Clean up old packages ─────────────────────────────────────────────
info "Removing unused packages..."
sudo apt autoremove -y
ok "Cleanup complete"

# ── 3. Update Nix flake inputs ───────────────────────────────────────────
info "Updating Nix flake inputs..."
nix flake update --flake "$FLAKE_DIR"
ok "Flake inputs updated"

# ── 4. Rebuild home-manager profile ──────────────────────────────────────
info "Rebuilding home-manager profile..."
home-manager switch --flake "${FLAKE_DIR}#default" --impure -b backup
ok "home-manager profile rebuilt"

__HM_SESS_VARS_SOURCED=
. "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" 2>/dev/null || true

# ── 5. Update extra tools ────────────────────────────────────────────────
. "$FLAKE_DIR/scripts/extras.sh"
install_ollama
install_python_ml_stack

# ── 6. Garbage collect Nix ────────────────────────────────────────────────
info "Collecting Nix garbage (older than 7 days)..."
nix-collect-garbage --delete-older-than 7d
ok "Nix garbage collected"

# ── 7. Update Ollama models (pull latest tags) ──────────────────────────
if command -v ollama &>/dev/null; then
  info "Updating Ollama models..."
  ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | while read -r model; do
    [ -z "$model" ] && continue
    info "  Pulling latest: $model"
    ollama pull "$model" 2>/dev/null || true
  done
fi

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  All updates complete!                     ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════╝${NC}"
