# ai-devbox — AI Workstation Bootstrap

One-command setup for an AI/ML server with Ubuntu 24.04 LTS.
Installs: Ollama, Open WebUI, AdGuard Home, Immich, Grafana, SearXNG,
Whisper, ComfyUI, and a headless browser deal-finding agent.

**Created for:** Ryzen + Radeon AI PRO R9700 (32GB VRAM) workstation.
**Works on:** Any Ubuntu 24.04 LTS system (WSL2 or bare metal).

## Quick Install

```bash
git clone https://github.com/vbrhino/ai-devbox.git
cd ai-devbox
sudo ./install.sh
```

Then reboot → `sudo tailscale up` → give me the Tailscale IP → I finish the rest.

---

## What It Does

| Phase | What | Time |
|-------|------|------|
| 1. System | Static IP, Nix, Docker, firewall, SSH hardening | ~10 min |
| 2. AI Stack | Ollama, Hermes 3, Llama, Qwen models | ~10 min |
| 3. Services | AdGuard, Grafana, Immich, SearXNG, Open WebUI | ~10 min |
| 4. Extras | Deal agent, Whisper, ComfyUI (pulled async) | ~30 min |
| **Total** | Fully automated | **~60 min** |

## After Install

| Service | Port | URL |
|---------|------|-----|
| Open WebUI | 3000 | `http://192.168.x.x:3000` |
| AdGuard | 8080 | `http://192.168.x.x:8080` |
| Grafana | 3001 | `http://192.168.x.x:3001` |
| Prometheus | 9090 | `http://192.168.x.x:9090` |
| Immich | 2283 | `http://192.168.x.x:2283` |
| SearXNG | 8888 | `http://192.168.x.x:8888` |
| Whisper | 9000 | `http://192.168.x.x:9000` |
| ComfyUI | 8188 | `http://192.168.x.x:8188` |
| Ollama API | 11434 | `http://192.168.x.x:11434` |
| SSH | 22 | `ssh pi@192.168.x.x` |

## Remote Access

- Tailscale SSH: `sudo tailscale up --ssh`
- Direct SSH: port 22 (key-only, no passwords)

## Lessons Learned (v1 → v2)

| Lesson | Fix |
|--------|-----|
| Ubuntu 26.04 too new | Use **24.04 LTS** |
| ROCm not on 26.04 | 24.04 has full ROCm 7.2 support |
| Playwright/pyppeteer broken | 24.04 has working Chromium |
| IP changed after reboot | **Static IP** set during install |
| Docker DNS loop | `daemon.json` with 1.1.1.1 |
| UFW vs iptables conflict | Use **only UFW** |
| AdGuard port 53 conflict | Use port 5353, iptables redirect |
| Mixed firewall tools | UFW only, no iptables-persistent |
| Missing WiFi tools | Install `network-manager` |
