# ai-devbox

AI Workstation dev environment — Ubuntu 24.04 LTS + Nix home-manager.

One command installs everything needed for AI/ML: Python stack, Ollama,
Open WebUI, llama.cpp, Docker, Tailscale, ROCm staging, and 120+ CLI tools.

**Works on:** WSL2 (for testing today) and bare-metal Linux (for the final build).

## Quick Start

```bash
cd ~
git clone <this-repo> ai-devbox
cd ai-devbox
./install.sh
```

Then open a new terminal and run:

```bash
ai-devbox-setup          # interactive: git, GitHub, Tailscale
sudo tailscale up        # connect to your tailnet
ollama pull llama3.2:3b  # pull a test model
open-webui               # start the browser UI
~/status.sh              # check everything
```

## After GPU Swap

```bash
sudo ~/ai-devbox/scripts/after-gpu-swap.sh
```

This removes NVIDIA drivers, installs ROCm, rebuilds llama.cpp with HIPBLAS,
and installs PyTorch with ROCm backend.

## File Layout

```
ai-devbox/
├── flake.nix              # Nix flake manifest
├── home.nix               # All packages + shell config
├── install.sh             # Bootstrap: Nix → home-manager → extras
├── README.md
├── config/
└── scripts/
    ├── setup.sh           # Interactive: git, GitHub, Tailscale
    ├── extras.sh          # Non-Nix tools (Ollama, Python, llama.cpp)
    ├── update.sh          # Update everything
    └── after-gpu-swap.sh  # Run after physical GPU swap
```
