# Session Summary — June 8-10, 2026

## Goal

Transform a gaming PC (RTX 4070 Ti → AMD Radeon AI PRO R9700) into a headless
AI workstation + dual boot (Windows/Linux) with remote gaming capability.

## What Was Built

### Server (Ubuntu 26.04 LTS — will reinstall to 24.04)

| Service | Status | Details |
|---------|--------|---------|
| **AdGuard Home** | ✅ Running | DNS ad-blocking, port 5353, redirect 53→5353 |
| **Ollama + Hermes 3** | ✅ Running | Local LLM for agents + analysis |
| **Open WebUI** | ✅ Running | Browser UI for LLMs |
| **Grafana + Prometheus** | ✅ Running | System monitoring |
| **Immich** | ✅ Running | Photo server |
| **SearXNG** | ✅ Running | Meta search engine (100+ engines) |
| **Whisper** | ⏳ Pulled | Speech-to-text (not tested) |
| **ComfyUI** | ⏳ Pulled | Stable Diffusion (not tested) |
| **Deal Agent** | ✅ Installed | AI-powered price comparison |
| **AI Profile** | ✅ Installed | Personal profiling with Hermes |

### Hardware

- CPU: AMD Ryzen (Raphael)
- GPU: AMD Radeon AI PRO R9700 (Navi 48, 32GB VRAM, gfx1201)
- RAM: 32GB
- SSD1: WD Blue 2TB (Ubuntu)
- SSD2: Samsung 2TB (Windows + 1TB backup)

### Network

- IP: 192.168.4.72 (Deco mesh network)
- Tailscale: 100.116.127.78
- Gateway: 192.168.4.1

## Issues Encountered

See [LESSONS.md](LESSONS.md) for full details. Most critical issues:

1. **Ubuntu 26.04 too new** — ROCm, Playwright, many packages don't work
2. **IP not static** — Changed after reboot, broke everything
3. **Docker DNS circular dependency** — AdGuard loop
4. **iptables-persistent removed UFW** — Package conflict
5. **Python 3.14 incompatibility** — pyppeteer crashes

## Next Session Plan

1. Install Ubuntu 24.04 LTS on WD Blue
2. `git clone https://github.com/vbrhino/ai-devbox.git`
3. `sudo ./install.sh` — ONE COMMAND
4. `sudo tailscale up --ssh`
5. pi takes over remotely

## Remote Access

User: `pi` with SSH key + passwordless sudo.
Tailscale SSH: enabled.
