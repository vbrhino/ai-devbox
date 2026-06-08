#!/usr/bin/env bash
#
# extras.sh — install/update tools not managed by Nix.
# Sourced by both install.sh and update.sh. Idempotent.

info()  { echo -e "\033[0;36m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[0;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }

# ── Ollama ──────────────────────────────────────────────────────────────
install_ollama() {
  if command -v ollama &>/dev/null; then
    info "Ollama already installed, checking for update..."
    # Ollama self-updates, so just ensure service is running
  else
    info "Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
  fi

  # Ensure service is enabled
  sudo systemctl enable --now ollama 2>/dev/null || true

  # Make Ollama listen on all interfaces (for LAN access)
  sudo mkdir -p /etc/systemd/system/ollama.service.d
  cat | sudo tee /etc/systemd/system/ollama.service.d/override.conf >/dev/null << 'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
EOF
  sudo systemctl daemon-reload
  sudo systemctl restart ollama 2>/dev/null || true
  ok "Ollama installed and configured"
}

# ── Tailscale ───────────────────────────────────────────────────────────
install_tailscale() {
  if command -v tailscale &>/dev/null; then
    ok "Tailscale already installed"
    return 0
  fi

  info "Installing Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh
  ok "Tailscale installed. Run: sudo tailscale up"
}

# ── Python ML stack ────────────────────────────────────────────────────
install_python_ml_stack() {
  info "Installing Python ML/AI packages..."

  pip3 install --quiet --upgrade \
    pip \
    setuptools \
    wheel \
    huggingface-hub \
    hf_transfer \
    transformers \
    sentencepiece \
    accelerate \
    datasets \
    bitsandbytes \
    psutil \
    gpustat 2>/dev/null || warn "Some Python packages had issues"

  # vLLM — will reconfigure for ROCm after GPU swap
  pip3 install --quiet vllm 2>/dev/null || warn "vLLM install deferred (needs GPU)"

  ok "Python ML packages installed (CPU mode)"
}

# ── llama.cpp (clone + build with both CPU and ROCm paths) ─────────────
install_llamacpp() {
  if [ -d "$HOME/llama.cpp" ]; then
    ok "llama.cpp already cloned"
    return 0
  fi

  info "Cloning llama.cpp..."
  git clone --depth 1 https://github.com/ggerganov/llama.cpp.git "$HOME/llama.cpp"

  info "Attempting CPU build..."
  cd "$HOME/llama.cpp"
  mkdir -p build && cd build
  cmake .. -DLLAMA_CUDA=OFF -DLLAMA_HIPBLAS=OFF -DLLAMA_AVX2=ON -DLLAMA_FMA=ON
  make -j"$(nproc)" 2>/dev/null || warn "CPU build failed (will try again post-GPU-swap)"
  cd ~

  ok "llama.cpp cloned"
}

# ── Open WebUI (Docker) ────────────────────────────────────────────────
install_openwebui() {
  mkdir -p "$HOME/ai-devbox/docker/open-webui/data"

  cat > "$HOME/ai-devbox/docker/open-webui/docker-compose.yml" << 'DOCKERCOMPOSE'
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    ports:
      - "3000:8080"
    volumes:
      - ./data:/app/backend/data
    environment:
      - OLLAMA_BASE_URL=http://host.docker.internal:11434
    extra_hosts:
      - "host.docker.internal:host-gateway"
    restart: unless-stopped
DOCKERCOMPOSE

  # Pull the image (background if it takes long)
  cd "$HOME/ai-devbox/docker/open-webui"
  docker compose pull 2>/dev/null || warn "Open WebUI pull deferred — run 'open-webui' later"
  cd ~

  ok "Open WebUI configured at ~/ai-devbox/docker/open-webui"
}

# ── Run all installs ────────────────────────────────────────────────────
# install.sh calls individual functions; update.sh calls these too.
# This file doesn't auto-run — it's sourced by install.sh/update.sh.
