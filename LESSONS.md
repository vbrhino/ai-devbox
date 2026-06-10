# ai-devbox — Lessons Learned

Everything we discovered the hard way during the initial setup.
Read this before starting a new install.

---

## 1. OS Selection: Ubuntu 24.04 LTS, not 26.04

**The mistake:** Installed Ubuntu 26.04 LTS (Resolute Raccoon) because it was the latest.

**The fallout:**
- ROCm 7.2 has no packages for 26.04 → no GPU compute
- Playwright/pyppeteer can't install Chromium → no headless browser
- Various Python 3.14 incompatibilities → scripts fail
- Smaller package ecosystem → missing libraries

**The fix:** Use **Ubuntu 24.04 LTS (Noble)** . It has:
- Full ROCm 7.2 support
- Playwright/Chromium out of the box
- Python 3.12 (everything works)
- 5 years support until 2029
- Largest community = most tutorials

## 2. Network: Set Static IP During Install

**The mistake:** Relied on DHCP, set static IP via netplan after install.

**The fallout:**
- Server IP changed on reboot (`.68.64` → `.68.76` → `.4.72`)
- Broke all DNS configurations
- Had to update every service URL
- iptables rules referenced wrong IP

**The fix:** During `install.sh`, prompt for static IP and configure it immediately.
Use both Netplan and NetworkManager detection for compatibility.

## 3. Docker DNS: Configure Before Starting Containers

**The mistake:** Started containers before setting Docker's DNS.

**The fallout:**
- Containers used host's `/etc/resolv.conf` → pointed to 127.0.0.53 → systemd-resolved
- systemd-resolved was configured to use local DNS → circular dependency
- AdGuard couldn't resolve upstream → all DNS queries timed out
- Had to restart all containers multiple times

**The fix:** Set `/etc/docker/daemon.json` with `"dns": ["1.1.1.1", "8.8.8.8"]` **before** starting Docker.

## 4. Firewall: Pick ONE — UFW or iptables

**The mistake:** Installed `iptables-persistent` which removed UFW (package conflict).

**The fallout:**
- UFW got uninstalled during `apt install iptables-persistent`
- Had to reinstall UFW and re-add all rules
- Both tools managing the same chains → conflicts
- No clear audit trail of what was allowed

**The fix:** Use **UFW only** for port management.
Use **rc.local** (not iptables-persistent) for port 53→5353 redirect.
Never install `iptables-persistent` — it conflicts with UFW.

## 5. Port 53 Redirect: Use rc.local for Persistence

**The mistake:** Used `iptables-persistent` which removed UFW.

**The fix:** Save iptables rules in `/etc/rc.local` (executed on every boot):

```bash
#!/bin/bash
iptables -t nat -A PREROUTING -p udp --dport 53 -m addrtype --dst-type LOCAL -j REDIRECT --to-port 5353
iptables -t nat -A PREROUTING -p tcp --dport 53 -m addrtype --dst-type LOCAL -j REDIRECT --to-port 5353
iptables -t nat -A OUTPUT -p udp --dport 5353 -j RETURN
iptables -t nat -A OUTPUT -p tcp --dport 5353 -j RETURN
iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-port 5353
iptables -t nat -A OUTPUT -p tcp --dport 53 -j REDIRECT --to-port 5353
exit 0
```

The `RETURN` rules for OUTPUT port 5353 are critical — without them,
containers' own DNS queries get redirected back to themselves, causing timeouts.

## 6. AdGuard: Use Port 5353, Not 53

**The mistake:** Tried to bind AdGuard to port 53 directly.

**The fallout:**
- systemd-resolved already occupies port 53 on 127.0.0.53
- AdGuard with `network_mode: host` couldn't bind port 53
- Had to switch to `network_mode: bridge` with port mapping

**The fix:** Run AdGuard on **port 5353** for DNS, **port 8080** for web UI.
Use iptables to transparently redirect port 53 → 5353.

## 7. SSH: Disable Cloud-Init Override

**The mistake:** Edited `/etc/ssh/sshd_config` but cloud-init overrode it.

**The fallout:**
- `sshd -T` showed `passwordauthentication yes` despite config change
- Discovered `/etc/ssh/sshd_config.d/50-cloud-init.conf` had `PasswordAuthentication yes`

**The fix:** 
```bash
rm -f /etc/ssh/sshd_config.d/50-cloud-init.conf
```
Or just overwrite it.

## 8. SearXNG: Volume Permissions

**The mistake:** Didn't set correct UID for SearXNG config directory.

**The fallout:** Container couldn't write `settings.yml` → kept crashing.

**The fix:** SearXNG container runs as UID **977**. Set volume permissions:
```bash
sudo chown -R 977:977 searxng-data/
```

## 9. AdGuard Config: Pre-create settings.yml

**The mistake:** Let AdGuard generate its config, but it defaulted to port 3000
which conflicted with Open WebUI.

**The fix:** Pre-create `settings.yml` with:
```yaml
http:
  address: 0.0.0.0:8080
dns:
  port: 5353
```

## 10. WiFi: Netplan Config with Password in Plaintext

**The issue:** Netplan WiFi config contains the WiFi password in plaintext.
Anyone with sudo access (or physical access) can read it.

**The fix:** Use NetworkManager for WiFi instead. Or at least `chmod 600`
the netplan file.

## 11. Separate User for Remote Access

**The lesson:** Create a dedicated `pi` user with SSH key and passwordless sudo
from the very beginning. This avoids:
- Sharing your personal account credentials
- Permission issues between users
- Having to create temporary users later

## 12. Background Installs Need Proper Logging

**The lesson:** When pulling Docker images in the background, write logs to
a predictable location with PID tracking. Without this, you don't know if
they succeeded or failed.

```bash
nohup docker compose up -d > /tmp/service-install.log 2>&1 &
echo $! > /tmp/service-install.pid
```

## 13. Tailscale in Userspace

**The lesson:** Tailscale can run entirely in userspace without root:
```bash
tailscaled --state=mem: --tun=userspace-networking --socket=/tmp/tailscaled.sock
tailscale --socket=/tmp/tailscaled.sock up
```
This works on locked-down corporate laptops where you can't get root.

## 14. SSH Through Tailscale Userspace

Use the `nc` subcommand as a ProxyCommand:
```bash
ssh -o ProxyCommand="tailscale --socket=/tmp/tailscaled.sock nc %h 22" user@machine
```

## 15. Don't Mix Python Installations

**The mistake:** Had both Nix Python (3.13) and system Python (3.14).
Packages installed for one didn't work for the other.

**The fix:** Stick with system Python on Ubuntu 24.04 (3.12, works with everything).
If using Nix, use Nix Python exclusively.

---

## Architecture Decisions

### Why Nix + home-manager?

- Reproducible: same tools everywhere
- No sudo needed for package installs
- 180+ CLI tools in one command
- Isolated from system packages

### Why Docker for services?

- Isolation: AdGuard, Grafana, Immich don't interfere
- Easy updates: `docker compose pull && docker compose up -d`
- Simple backups: back up the volume mounts
- Testable: can run locally on any machine

### Why SearXNG over direct scraping?

- Aggregates 100+ search engines
- No CAPTCHAs (single user instance)
- Clean JSON API for programmatic use
- Self-hosted = no API costs
- Includes Google, Bing, DuckDuckGo results

### Why UFW over iptables directly?

- Simpler syntax
- Automatic rule ordering
- IPv6 support built-in
- Logging built-in
- Less error-prone

---

## Quick Reference

```bash
# After fresh Ubuntu 24.04 install:
sudo ./install.sh

# Connect remote access:
sudo tailscale up --ssh

# The user 'pi' has passwordless sudo and SSH key access.
# Default password for admin interfaces:
#   Grafana: admin / admin
#   AdGuard: set during first browser visit
#   Immich:  set during first browser visit

# All services are in /home/pi/docker/<service>/
# Each has its own docker-compose.yml
```
