#!/usr/bin/env bash
#
# setup.sh — interactive setup for a fresh ai-devbox.
# Idempotent — safe to re-run anytime.
set -euo pipefail

for f in "$HOME/.nix-profile/etc/profile.d/nix.sh" "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"; do
  [[ -f "$f" ]] && . "$f"
done
export PATH="$HOME/.nix-profile/bin:$HOME/.local/bin:$PATH"

section() { echo -e "\n\033[1;32m[$1]\033[0m"; }
skip()    { echo "  skipped (already configured)"; }

# ── Git identity ──────────────────────────────────────────────────────────
setup_git() {
  section "Git"

  CURRENT_NAME=$(git config --global user.name 2>/dev/null || true)
  CURRENT_EMAIL=$(git config --global user.email 2>/dev/null || true)

  if [[ -n "$CURRENT_NAME" && -n "$CURRENT_EMAIL" ]]; then
    echo "  name:  $CURRENT_NAME"
    echo "  email: $CURRENT_EMAIL"
    read -rp "  Reconfigure? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || return 0
  fi

  read -rp "  Full name: " name
  read -rp "  Email: " email
  git config --global user.name "$name"
  git config --global user.email "$email"
  echo "  done."
}

# ── GitHub authentication ─────────────────────────────────────────────────
setup_gh() {
  section "GitHub"

  if ! command -v gh &>/dev/null; then
    echo "  gh not found — skipping"
    return 0
  fi

  if gh auth status &>/dev/null 2>&1; then
    echo "  authenticated as $(gh api user --jq '.login' 2>/dev/null || echo 'unknown')"
  else
    echo "  token expired or missing — re-authenticating..."
    gh auth login
  fi

  # Update Nix access token
  NIX_CONF="$HOME/.config/nix/nix.conf"
  if [ -f "$NIX_CONF" ]; then
    GH_TOKEN=$(gh auth token 2>/dev/null)
    if [ -n "$GH_TOKEN" ]; then
      if grep -q "access-tokens" "$NIX_CONF" 2>/dev/null; then
        sed -i "s|^access-tokens.*|access-tokens = github.com=$GH_TOKEN|" "$NIX_CONF"
      else
        echo "access-tokens = github.com=$GH_TOKEN" >> "$NIX_CONF"
      fi
      echo "  nix access token updated"
    fi
  fi
}

# ── Tailscale check ───────────────────────────────────────────────────────
setup_tailscale() {
  section "Tailscale"

  if ! command -v tailscale &>/dev/null; then
    echo "  Tailscale not installed — run: curl -fsSL https://tailscale.com/install.sh | sh"
    return 0
  fi

  if tailscale status 2>/dev/null | grep -q "$(hostname)"; then
    echo "  Tailscale is up:"
    tailscale status 2>/dev/null | head -3
  else
    echo "  Tailscale is installed but not connected."
    echo "  Run: sudo tailscale up"
    read -rp "  Connect now? [y/N] " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      sudo tailscale up
    fi
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────
main() {
  echo "=== ai-devbox Setup ==="

  setup_git
  setup_gh
  setup_tailscale

  echo -e "\n\033[1;32mSetup complete.\033[0m"
  echo "  Next: pull some models and start the web UI:"
  echo "    ollama pull llama3.2:3b"
  echo "    open-webui"
  echo "    ~/status.sh"
}

main
