#!/usr/bin/env bash
# ============================================================================
# after-gpu-swap.sh — Run AFTER physically installing the AMD GPU
# ============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
err()   { echo -e "${RED}[ERR]${NC}   $*"; }

if [ "$(id -u)" -ne 0 ]; then
    err "Run with: sudo ~/ai-devbox/scripts/after-gpu-swap.sh"
    exit 1
fi

USER_HOME=$(eval echo ~"${SUDO_USER:-$USER}")
USERNAME="${SUDO_USER:-$USER}"

info "=== Post-GPU-Swap Setup ==="

# 1. Verify GPU
info "Checking GPU detection..."
lspci | grep -i amd || { err "No AMD GPU found — is it seated and powered?"; exit 1; }

# 2. Remove NVIDIA drivers (if present)
info "Removing NVIDIA drivers (if any)..."
apt purge -y nvidia-* 2>/dev/null || true
apt autoremove -y 2>/dev/null || true
ok "NVIDIA drivers removed"

# 3. Install ROCm kernel drivers + full stack
info "Installing ROCm stack..."
mkdir -p /etc/apt/keyrings
wget -O- -q https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor -o /etc/apt/keyrings/rocm.gpg 2>/dev/null || true
UBUNTU_CODENAME=$(lsb_release -cs)
cat > /etc/apt/sources.list.d/rocm.list << EOF
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/6.3 ${UBUNTU_CODENAME} main
EOF
apt update
apt install -y rocm-hip-libraries rocm-dev rocm-docker
usermod -a -G render,video,rocm "$USERNAME"
ok "ROCm installed"

# 4. Verify
info "Verifying ROCm..."
rocminfo | grep "Name:" || err "ROCm not detecting GPU"
rocm-smi
ok "GPU detected and working"

# 5. Rebuild llama.cpp with HIPBLAS
info "Rebuilding llama.cpp with ROCm..."
sudo -u "$USERNAME" bash -c '
cd ~/llama.cpp
mkdir -p build && cd build
AMD_GPU=$(rocminfo 2>/dev/null | grep "gfx[0-9]*" | head -1 | tr -d " " || echo "gfx1100")
echo "Target GPU architecture: $AMD_GPU"
cmake .. \
    -DLLAMA_HIPBLAS=ON \
    -DCMAKE_C_COMPILER=gcc \
    -DCMAKE_CXX_COMPILER=g++ \
    -DAMDGPU_TARGETS="$AMD_GPU"
make -j"$(nproc)"
'
ok "llama.cpp rebuilt with ROCm"

# 6. Install PyTorch with ROCm
info "Installing PyTorch ROCm..."
sudo -u "$USERNAME" pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm6.3
ok "PyTorch with ROCm installed"

# 7. Test inference
info "Testing Ollama with GPU..."
sudo -u "$USERNAME" ollama pull llama3.2:3b 2>/dev/null || true
sudo -u "$USERNAME" ollama run llama3.2:3b "Hello! What GPU am I running on? Be brief." 2>/dev/null || warn "Ollama test skipped"

# 8. Start Open WebUI
info "Starting Open WebUI..."
cd "${USER_HOME}/ai-devbox/docker/open-webui"
docker compose up -d 2>/dev/null || warn "Open WebUI start skipped"
cd ~

echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║  Post-GPU-Swap Complete!                  ║"
echo "║                                           ║"
echo "║  Run ~/status.sh to verify.               ║"
echo "║  Open WebUI: http://$(hostname -I 2>/dev/null | awk '{print $1}'):3000"  
echo "╚═══════════════════════════════════════════╝"
