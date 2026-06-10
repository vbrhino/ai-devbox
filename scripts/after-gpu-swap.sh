#!/usr/bin/env bash
# ============================================================================
# after-gpu-swap.sh — Run AFTER physically installing the AMD GPU.
# Works best on Ubuntu 24.04 LTS (has full ROCm support).
# ============================================================================
set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
err()   { echo -e "${RED}[ERR]${NC}   $*"; }

if [ "$(id -u)" -ne 0 ]; then
    err "Run: sudo ~/ai-devbox/scripts/after-gpu-swap.sh"
    exit 1
fi

info "=== Post-GPU-Swap Setup ==="

# 1. Verify GPU
info "Checking GPU detection..."
lspci | grep -i 'vga.*amd\|radeon' || { err "No AMD GPU found"; exit 1; }

# 2. Remove NVIDIA drivers (if any)
info "Removing NVIDIA drivers..."
apt purge -y nvidia-* 2>/dev/null || true
apt autoremote -y 2>/dev/null || true
ok "NVIDIA drivers removed"

# 3. Install ROCm (Ubuntu 24.04 LTS)
info "Installing ROCm stack..."
mkdir -p /etc/apt/keyrings
wget -O- -q https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor -o /etc/apt/keyrings/rocm.gpg 2>/dev/null || true
cat > /etc/apt/sources.list.d/rocm.list << EOF
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.2 noble main
EOF
apt update
apt install -y rocm-hip-libraries rocm-dev rocm-docker
usermod -a -G render,video,rocm pi
usermod -a -G render,video,rocm tech 2>/dev/null || true
ok "ROCm installed"

# 4. Verify
info "Verifying ROCm..."
rocminfo | grep "Name:" || err "ROCm not detecting GPU"
rocm-smi | head -15
ok "GPU detected"

# 5. Install PyTorch with ROCm
info "Installing PyTorch ROCm..."
pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm6.3 --break-system-packages -q 2>/dev/null
ok "PyTorch with ROCm installed"

# 6. Install Playwright + Chromium (for deal agent)
info "Installing Playwright (headless browser)..."
pip3 install playwright --break-system-packages -q 2>/dev/null || true
playwright install chromium --with-deps 2>/dev/null || true
ok "Headless browser installed"

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Post-GPU-Swap Complete!                  ║${NC}"
echo -e "${GREEN}║  ROCm, PyTorch, Playwright installed.     ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════╝${NC}"
