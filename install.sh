#!/usr/bin/env bash
# ============================================================================
# ai-devbox — AI Workstation Bootstrap (Ubuntu 24.04 LTS)
#
# One command to set up everything: AI stack, services, security, monitoring.
# Run on a fresh Ubuntu 24.04 LTS Server install.
#
# Usage: sudo ./install.sh
# ============================================================================
set -euo pipefail

# ── Colors ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERR]${NC}   $*"; }

if [ "$(id -u)" -ne 0 ]; then
    err "Run with: sudo ./install.sh"
    exit 1
fi

# ── Detect environment ─────────────────────────────────────────────────────
IS_WSL=false
grep -qi microsoft /proc/version 2>/dev/null && IS_WSL=true
HOST_USER="${SUDO_USER:-root}"
HOST_HOME=$(eval echo ~"$HOST_USER")
SERVER_IP=$(ip -4 route get 1 | awk '{print $7; exit}' 2>/dev/null || echo "192.168.x.x")

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              AI Workstation Bootstrap v2                    ║${NC}"
echo -e "${GREEN}║           Ubuntu 24.04 LTS - One Install to Rule Them All  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 1: SYSTEM
# ═══════════════════════════════════════════════════════════════════════════

info "=== PHASE 1: System ==="

# 1.1 — Update system
apt update && apt upgrade -y && apt autoremove -y

# 1.2 — Install base packages
apt install -y \
    curl wget git htop btop \
    ufw \
    network-manager \
    ca-certificates gnupg lsb-release \
    unattended-upgrades \
    tmux screen \
    python3 python3-pip python3-venv python3-bs4 python3-requests \
    build-essential cmake pkg-config \
    lm-sensors smartmontools pciutils \
    iptables

# 1.3 — Enable unattended security upgrades
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
ok "Unattended upgrades enabled"

# 1.4 — Static IP (interactive)
info "Network configuration"
DEFAULT_IFACE=$(ip route get 1 | awk '{print $5; exit}')
CURRENT_IP=$(ip -4 addr show "$DEFAULT_IFACE" | grep -oP 'inet \K[\d.]+' 2>/dev/null || echo "?")
CURRENT_GW=$(ip route | grep default | awk '{print $3}' | head -1)
echo "  Interface: $DEFAULT_IFACE"
echo "  Current IP: $CURRENT_IP"
echo "  Gateway: $CURRENT_GW"
echo ""
read -rp "  Set static IP? [IP/n] (e.g., 192.168.68.64): " STATIC_IP
if [ -n "$STATIC_IP" ] && [ "$STATIC_IP" != "n" ]; then
    # Detect if using Netplan or NetworkManager
    if [ -d /etc/netplan ]; then
        cat > /etc/netplan/00-installer-config.yaml << NETPLAN
network:
  version: 2
  ethernets:
    $DEFAULT_IFACE:
      dhcp4: false
      addresses:
        - $STATIC_IP/24
      routes:
        - to: default
          via: $CURRENT_GW
      nameservers:
        addresses:
          - 1.1.1.1
          - 8.8.8.8
NETPLAN
        netplan apply 2>/dev/null || true
    else
        nmcli con mod "$DEFAULT_IFACE" ipv4.addresses "$STATIC_IP/24" 2>/dev/null || true
        nmcli con mod "$DEFAULT_IFACE" ipv4.gateway "$CURRENT_GW" 2>/dev/null || true
        nmcli con mod "$DEFAULT_IFACE" ipv4.dns "1.1.1.1 8.8.8.8" 2>/dev/null || true
        nmcli con mod "$DEFAULT_IFACE" ipv4.method manual 2>/dev/null || true
        nmcli con up "$DEFAULT_IFACE" 2>/dev/null || true
    fi
    SERVER_IP="$STATIC_IP"
    ok "Static IP set: $STATIC_IP"
fi

# 1.5 — Firewall (UFW only, no iptables-persistent mixing)
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 3000/tcp comment 'Open WebUI'
ufw allow 8080/tcp comment 'AdGuard'
ufw allow 3001/tcp comment 'Grafana'
ufw allow 9090/tcp comment 'Prometheus'
ufw allow 2283/tcp comment 'Immich'
ufw allow 8888/tcp comment 'SearXNG'
ufw allow 9000/tcp comment 'Whisper'
ufw allow 8188/tcp comment 'ComfyUI'
ufw allow 11434/tcp comment 'Ollama'
ufw --force enable
ok "Firewall configured"

# 1.6 — SSH hardening
sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
rm -f /etc/ssh/sshd_config.d/50-cloud-init.conf 2>/dev/null || true
systemctl restart sshd
ok "SSH hardened (key-only, no root)"

# 1.7 — Kernel tuning
cat > /etc/sysctl.d/90-ai.conf << 'EOF'
vm.nr_hugepages = 4096
vm.max_map_count = 1048576
fs.inotify.max_user_watches = 524288
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
EOF
sysctl --system
ok "Kernel tuned"

# 1.8 — Create pi user with SSH key
PI_HOME="/home/pi"
if ! id pi &>/dev/null; then
    useradd -m -G sudo -s /bin/bash pi
    mkdir -p "$PI_HOME/.ssh"
    # Add public key — replace with your own in production
    cat > "$PI_HOME/.ssh/authorized_keys" << 'KEY'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINADY+Z9DWXNWpbcGAPwl7v5zM2YGsuhw2cUgdLd5EKw rvb@PW08HMY7
KEY
    chown -R pi:pi "$PI_HOME/.ssh"
    chmod 700 "$PI_HOME/.ssh" && chmod 600 "$PI_HOME/.ssh/authorized_keys"
    echo "pi ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/pi
    chmod 440 /etc/sudoers.d/pi
    ok "User 'pi' created with SSH key + passwordless sudo"
else
    ok "User 'pi' already exists"
fi

# 1.9 — Headless boot
systemctl set-default multi-user.target
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub 2>/dev/null || true
update-grub 2>/dev/null || true
ok "Headless boot: GRUB 3s timeout"

# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 2: NIX + HOME-MANAGER
# ═══════════════════════════════════════════════════════════════════════════

info "=== PHASE 2: Nix + home-manager ==="

# 2.1 — Install Nix (if not present)
if ! command -v nix &>/dev/null; then
    curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null || true
    ok "Nix installed"
fi
export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"

# 2.2 — Enable flakes
mkdir -p "$HOME/.config/nix"
if ! grep -q "experimental-features" "$HOME/.config/nix/nix.conf" 2>/dev/null; then
    echo "experimental-features = nix-command flakes" >> "$HOME/.config/nix/nix.conf"
fi

# 2.3 — Build home-manager
FLAKE_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ ! -d "$FLAKE_DIR/.git" ]; then
    git -C "$FLAKE_DIR" init -q
    git -C "$FLAKE_DIR" add -A
    git -C "$FLAKE_DIR" -c user.name="install" -c user.email="install@local" commit -qm "init"
fi
git config --global --get-all safe.directory 2>/dev/null | grep -qxF "$FLAKE_DIR" \
    || git config --global --add safe.directory "$FLAKE_DIR"

info "Building Nix environment (first run: 5-15 min)..."
nix run home-manager -- switch --flake "${FLAKE_DIR}#default" --impure --no-write-lock-file -b backup 2>&1 | tail -3
ok "Nix environment activated"

# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 3: DOCKER
# ═══════════════════════════════════════════════════════════════════════════

info "=== PHASE 3: Docker ==="

# 3.1 — Install Docker Engine (not via snap/Nix, proper apt)
if ! command -v dockerd &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
    ok "Docker Engine installed"
fi

# 3.2 — Configure Docker DNS (prevent AdGuard loop)
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
  "dns": ["1.1.1.1", "8.8.8.8"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

systemctl enable --now docker
usermod -aG docker "$HOST_USER"
usermod -aG docker pi
ok "Docker configured + DNS set"

# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 4: OLLAMA + OPEN WEBUI
# ═══════════════════════════════════════════════════════════════════════════

info "=== PHASE 4: Ollama + Open WebUI ==="

# 4.1 — Install Ollama
if [ ! -x /usr/local/bin/ollama ]; then
    curl -fsSL https://ollama.com/install.sh | sh
fi
systemctl enable --now ollama

# Configure Ollama for LAN access
mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf << 'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
EOF
systemctl daemon-reload
systemctl restart ollama
ok "Ollama installed"

# 4.2 — Pull models (background)
info "Pulling AI models (background)..."
ollama pull llama3.2:3b 2>/dev/null || true &
ollama pull llama3.1:8b 2>/dev/null || true &
ollama pull hermes3:8b 2>/dev/null || true &
ollama pull qwen2.5-coder:14b 2>/dev/null || true &

# 4.3 — Open WebUI
mkdir -p /home/pi/docker/open-webui/data
cat > /home/pi/docker/open-webui/docker-compose.yml << 'YAML'
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
YAML
chown -R pi:pi /home/pi/docker
ok "Open WebUI configured"

# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 5: SERVICES (Docker Compose)
# ═══════════════════════════════════════════════════════════════════════════

info "=== PHASE 5: Services ==="

# 5.1 — AdGuard Home
mkdir -p /home/pi/docker/adguard/{work,conf}
cat > /home/pi/docker/adguard/docker-compose.yml << 'YAML'
services:
  adguard:
    image: adguard/adguardhome:latest
    container_name: adguard
    restart: unless-stopped
    network_mode: host
    dns:
      - 1.1.1.1
      - 8.8.8.8
    volumes:
      - ./work:/opt/adguardhome/work
      - ./conf:/opt/adguardhome/conf
YAML

# Pre-configure AdGuard (port 5353 for DNS, 8080 for web)
cat > /home/pi/docker/adguard/conf/AdGuardHome.yaml << 'YAML'
http:
  address: 0.0.0.0:8080
  session_ttl: 3h
users: []
dns:
  port: 5353
  bind_hosts:
    - 0.0.0.0
  upstream_dns:
    - 1.1.1.1
  bootstrap_dns:
    - 1.1.1.1
  blocking_ipv4: ""
  blocking_ipv6: ""
schema_version: 18
YAML

# iptables redirect: port 53 → 5353
iptables -t nat -A PREROUTING -p udp --dport 53 -m addrtype --dst-type LOCAL -j REDIRECT --to-port 5353
iptables -t nat -A PREROUTING -p tcp --dport 53 -m addrtype --dst-type LOCAL -j REDIRECT --to-port 5353
iptables -t nat -A OUTPUT -p udp --dport 5353 -j RETURN
iptables -t nat -A OUTPUT -p tcp --dport 5353 -j RETURN
iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-port 5353
iptables -t nat -A OUTPUT -p tcp --dport 53 -j REDIRECT --to-port 5353

# Save iptables for boot (rc.local approach, no iptables-persistent)
cat > /etc/rc.local << 'EOF'
#!/bin/bash
iptables -t nat -A PREROUTING -p udp --dport 53 -m addrtype --dst-type LOCAL -j REDIRECT --to-port 5353
iptables -t nat -A PREROUTING -p tcp --dport 53 -m addrtype --dst-type LOCAL -j REDIRECT --to-port 5353
iptables -t nat -A OUTPUT -p udp --dport 5353 -j RETURN
iptables -t nat -A OUTPUT -p tcp --dport 5353 -j RETURN
iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-port 5353
iptables -t nat -A OUTPUT -p tcp --dport 53 -j REDIRECT --to-port 5353
exit 0
EOF
chmod +x /etc/rc.local
ok "AdGuard configured (port 8080 web, 5353 DNS, 53→redirect)"

# 5.2 — Grafana + Prometheus
mkdir -p /home/pi/docker/grafana
cat > /home/pi/docker/grafana/docker-compose.yml << 'YAML'
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana_data:/var/lib/grafana
    ports:
      - "3001:3000"

volumes:
  prometheus_data:
  grafana_data:
YAML

cat > /home/pi/docker/grafana/prometheus.yml << 'YAML'
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: node
    static_configs:
      - targets: ['localhost:9100']
YAML
ok "Grafana + Prometheus configured"

# 5.3 — Node Exporter
docker run -d --name node_exporter --restart unless-stopped \
    --network host --pid host \
    -v /proc:/host/proc:ro -v /sys:/host/sys:ro -v /:/rootfs:ro \
    prom/node-exporter:latest \
    --path.procfs=/host/proc --path.sysfs=/host/sys --path.rootfs=/rootfs 2>/dev/null || true

# 5.4 — Immich
mkdir -p /home/pi/docker/immich
cat > /home/pi/docker/immich/docker-compose.yml << 'YAML'
name: immich
services:
  immich-server:
    image: ghcr.io/immich-app/immich-server:release
    container_name: immich_server
    restart: unless-stopped
    ports:
      - 2283:2283
    environment:
      DB_HOSTNAME: immich_postgres
      DB_USERNAME: postgres
      DB_PASSWORD: postgres
      DB_DATABASE_NAME: immich
      REDIS_HOSTNAME: immich_redis
    volumes:
      - ./upload:/usr/src/app/upload
      - /etc/localtime:/etc/localtime:ro
    depends_on:
      - redis
      - database

  immich-machine-learning:
    image: ghcr.io/immich-app/immich-machine-learning:release
    container_name: immich_machine_learning
    restart: unless-stopped
    volumes:
      - ./ml-cache:/cache
    environment:
      DB_HOSTNAME: immich_postgres
      DB_USERNAME: postgres
      DB_PASSWORD: postgres
      DB_DATABASE_NAME: immich

  redis:
    image: redis:6.2-alpine
    container_name: immich_redis
    restart: unless-stopped

  database:
    image: tensorchord/pgvecto-rs:pg14-v0.2.0
    container_name: immich_postgres
    restart: unless-stopped
    environment:
      POSTGRES_PASSWORD: postgres
      POSTGRES_USER: postgres
      POSTGRES_DB: immich
    volumes:
      - ./postgres:/var/lib/postgresql/data
YAML

# 5.5 — SearXNG
mkdir -p /home/pi/docker/searxng/searxng-data
cat > /home/pi/docker/searxng/docker-compose.yml << 'YAML'
services:
  searxng:
    image: searxng/searxng:latest
    container_name: searxng
    restart: unless-stopped
    ports:
      - "8888:8080"
    volumes:
      - ./searxng-data:/etc/searxng:rw
    environment:
      - SEARXNG_BASE_URL=http://$SERVER_IP:8888
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - SETGID
      - SETUID
YAML

# Fix permissions for SearXNG
chown -R 977:977 /home/pi/docker/searxng/searxng-data 2>/dev/null || true
ok "All services configured"

# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 6: DEAL FINDER AGENT
# ═══════════════════════════════════════════════════════════════════════════

info "=== PHASE 6: Deal Finder Agent ==="

mkdir -p /home/pi/deal-agent/{results,.cache}

# Install Python deps
pip3 install requests beautifulsoup4 lxml --break-system-packages -q 2>/dev/null || true

# Copy deal-agent.py from repo
if [ -f "$FLAKE_DIR/scripts/deal-agent.py" ]; then
    cp "$FLAKE_DIR/scripts/deal-agent.py" /home/pi/deal-agent/deal-agent.py
    chmod +x /home/pi/deal-agent/deal-agent.py
    ok "Deal agent installed"
fi

# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 7: TAILSCALE
# ═══════════════════════════════════════════════════════════════════════════

info "=== PHASE 7: Tailscale ==="
if ! command -v tailscale &>/dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
    ok "Tailscale installed"
fi

# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 8: BACKUP
# ═══════════════════════════════════════════════════════════════════════════

info "=== PHASE 8: Backup ==="
cat > /home/pi/backup.sh << 'SCRIPT'
#!/bin/bash
LOG=/var/log/backup.log
DATE=$(date +%Y-%m-%d)
log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a $LOG; }
log "=== Backup $DATE ==="
rsync -av --delete /home/pi/docker/ /mnt/backup/docker-configs/ >> $LOG 2>&1 || true
df -h /mnt/backup >> $LOG || true
log "=== Done ==="
SCRIPT
chmod +x /home/pi/backup.sh
(crontab -l 2>/dev/null; echo '0 3 * * * /home/pi/backup.sh') | crontab - 2>/dev/null || true
ok "Daily backup cron at 3am"

# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 9: STATUS SCRIPT + MOTD
# ═══════════════════════════════════════════════════════════════════════════

cat > /home/pi/status.sh << 'STATUS'
#!/bin/bash
echo "╔═══════════════════════════════════════════╗"
echo "║        AI Workstation Status              ║"
echo "╚═══════════════════════════════════════════╝"
echo "Uptime: $(uptime -p)"
echo "IP: $(hostname -I | awk '{print $1}')"
echo ""
echo "── Docker ──"
docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null || echo "Docker not running"
echo ""
echo "── Ollama Models ──"
curl -s http://localhost:11434/api/tags 2>/dev/null | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    for m in d.get('models',[]):
        n=m.get('name','?')
        s=m.get('size',0)
        print(f'  {n}  ({s/1e9:.1f} GB)')
except: print('  (none)')
" 2>/dev/null || echo "  Ollama not running"
echo ""
echo "── GPU ──"
lspci | grep -i 'radeon\|nvidia' | head -3 2>/dev/null || echo "  no GPU detected"
echo ""
echo "── Disk ──"
df -h / /home /mnt/backup 2>/dev/null | column -t
STATUS
chmod +x /home/pi/status.sh
ok "Status script: ~/status.sh"

# ═══════════════════════════════════════════════════════════════════════════
#  START SERVICES
# ═══════════════════════════════════════════════════════════════════════════

info "=== Starting services ==="
# Start Docker services in background
for dir in adguard grafana immich searxng open-webui; do
    cd "/home/pi/docker/$dir" 2>/dev/null && docker compose up -d 2>/dev/null &
done
cd /

# ═══════════════════════════════════════════════════════════════════════════
#  SUMMARY
# ═══════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           ✅  Install Complete!                             ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║  Access URLs:                                               ║${NC}"
echo -e "${GREEN}║    Open WebUI:  http://${SERVER_IP}:3000                     ${NC}"
echo -e "${GREEN}║    AdGuard:     http://${SERVER_IP}:8080                     ${NC}"
echo -e "${GREEN}║    Grafana:     http://${SERVER_IP}:3001 (admin/admin)       ${NC}"
echo -e "${GREEN}║    Immich:      http://${SERVER_IP}:2283                     ${NC}"
echo -e "${GREEN}║    SearXNG:     http://${SERVER_IP}:8888                     ${NC}"
echo -e "${GREEN}║    Deal agent:  ~/deal-agent/deal-agent.py                   ${NC}"
echo -e "${GREEN}║                                                              ${NC}"
echo -e "${GREEN}║  Next steps:                                                 ${NC}"
echo -e "${GREEN}║    1. Reboot → log in                                       ${NC}"
echo -e "${GREEN}║    2. sudo tailscale up --ssh                               ${NC}"
echo -e "${GREEN}║    3. Give me the Tailscale IP                              ${NC}"
echo -e "${GREEN}║    4. I'll finish: ROCm, models, config                     ${NC}"
echo -e "${GREEN}║                                                              ${NC}"
echo -e "${GREEN}║  After GPU swap: sudo ~/ai-devbox/scripts/after-gpu-swap.sh ${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
