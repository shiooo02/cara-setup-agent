#!/usr/bin/env bash
# uninstall.sh - bersih total: stop service, kill PID, hapus docker
# container, hapus semua direktori install. Buat starting fresh.
#
# Pakai:           sudo bash uninstall.sh
# Skip prompt:     sudo DEEP_CLEAN=1 bash uninstall.sh
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/lib.sh"

require_root

cat <<'EOF'
================================================
  UNINSTALL TOTAL: Hermes + 9Router + Tunnel
================================================

Yang bakal dihapus / dibersihin:

  Service systemd:
    - 9router (legacy npm), 9router-tunnel
    - hermes, hermes-gateway, hermes-cron, dll

  Docker container & image:
    - container '9router' (decolua/9router:latest)
    - image decolua/9router (kalo confirm)
    - container hermes-* (kalo ada)

  Process / PID:
    - Semua proses 'cloudflared'
    - Semua proses 'hermes', 'python ... hermes'

  File:
    - /root/.hermes        (config, .env, sessions, logs, skills, memori, SOUL.md)
    - /root/.9router       (DB admin + provider config)
    - /usr/local/lib/hermes-agent  (kode Hermes)
    - /usr/local/bin/hermes, /usr/local/bin/cloudflared
    - /etc/systemd/system/hermes*.service, /etc/systemd/system/9router*.service
    - cache: ~/.cache/uv, ~/.cache/pip (hermes-related)

  Yang TIDAK dihapus:
    - Docker engine (mungkin lo butuh buat container lain)
    - Node.js, Python, uv
    - Firewall rule (UFW)
    - API key di provider (revoke manual di tiap dashboard)
    - Bot Telegram (revoke manual di @BotFather kalau perlu)

EOF

DEEP="${DEEP_CLEAN:-0}"

if [[ "$DEEP" != "1" ]]; then
  if ! confirm "Yakin uninstall semua?"; then
    echo "Cancelled."
    exit 0
  fi
fi

# ============================================================================
# 1. Stop & disable systemd services
# ============================================================================
step "Stop & disable systemd services"

UNITS=(
  hermes
  hermes-gateway
  hermes-cron
  hermes-discord
  hermes-slack
  hermes-whatsapp
  hermes-signal
  9router
  9router-tunnel
  cloudflared
)

for svc in "${UNITS[@]}"; do
  if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}.service"; then
    log "Stop $svc"
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
    systemctl reset-failed "$svc" 2>/dev/null || true
    rm -f "/etc/systemd/system/${svc}.service"
    rm -f "/etc/systemd/system/multi-user.target.wants/${svc}.service"
    ok "Service $svc dihapus"
  fi
done

if [[ -d /root/.config/systemd/user ]]; then
  for svc in hermes hermes-gateway; do
    rm -f "/root/.config/systemd/user/${svc}.service" 2>/dev/null || true
  done
fi

systemctl daemon-reload

# ============================================================================
# 2. Stop & remove Docker container 9router
# ============================================================================
step "Hapus container Docker 9router"

if command -v docker >/dev/null 2>&1; then
  containers=$(docker ps -a --filter 'name=9router' --format '{{.Names}}' 2>/dev/null || true)
  if [[ -n "$containers" ]]; then
    log "Container ditemukan: $containers"
    echo "$containers" | xargs -r docker stop 2>/dev/null || true
    echo "$containers" | xargs -r docker rm -f 2>/dev/null || true
    ok "Container 9router dihapus"
  fi

  # Cek juga container hermes-* (kalo ada)
  hermes_containers=$(docker ps -a --filter 'name=hermes' --format '{{.Names}}' 2>/dev/null || true)
  if [[ -n "$hermes_containers" ]]; then
    log "Container hermes ditemukan: $hermes_containers"
    if [[ "$DEEP" == "1" ]] || confirm "Stop & hapus container Hermes?"; then
      echo "$hermes_containers" | xargs -r docker stop 2>/dev/null || true
      echo "$hermes_containers" | xargs -r docker rm -f 2>/dev/null || true
      ok "Container hermes dihapus"
    fi
  fi

  # Image cleanup (optional)
  images=$(docker images --filter 'reference=*9router*' --format '{{.Repository}}:{{.Tag}}' 2>/dev/null || true)
  if [[ -n "$images" ]]; then
    log "Image 9router ditemukan: $images"
    if [[ "$DEEP" == "1" ]] || confirm "Hapus juga image 9router (~200MB)?"; then
      echo "$images" | xargs -r docker rmi -f 2>/dev/null || true
      ok "Image dihapus"
    fi
  fi
else
  log "Docker ga keinstall, skip"
fi

# ============================================================================
# 3. Kill stray processes
# ============================================================================
step "Kill proses yang masih jalan (non-docker)"

PATTERNS=(
  "cloudflared.*tunnel"
  "node.*hermes"
  "python.*hermes"
  "python.*hermes_cli"
  "hermes-agent"
  "hermes_gateway"
  "/usr/local/bin/hermes"
)

for pat in "${PATTERNS[@]}"; do
  pids=$(pgrep -f "$pat" 2>/dev/null || true)
  if [[ -n "$pids" ]]; then
    log "Kill: $pat -> PID $(echo $pids | tr '\n' ' ')"
    echo "$pids" | xargs -r kill 2>/dev/null || true
    sleep 1
    pids2=$(pgrep -f "$pat" 2>/dev/null || true)
    if [[ -n "$pids2" ]]; then
      echo "$pids2" | xargs -r kill -9 2>/dev/null || true
    fi
  fi
done
ok "Proses dibersihin"

# ============================================================================
# 4. Hapus binary
# ============================================================================
step "Hapus binary global"
rm -f /usr/local/bin/cloudflared
rm -f /usr/local/bin/hermes
rm -f /root/.local/bin/hermes 2>/dev/null || true
rm -f /usr/local/bin/9router /usr/bin/9router 2>/dev/null || true  # legacy npm
ok "Binary dihapus"

# ============================================================================
# 5. Hapus packages
# ============================================================================
step "Hapus npm + python packages"
npm uninstall -g 9router 2>/dev/null || true   # legacy npm install
rm -rf /usr/local/lib/hermes-agent 2>/dev/null || true
rm -rf /root/.hermes/hermes-agent 2>/dev/null || true  # legacy layout
ok "Packages dihapus"

# ============================================================================
# 6. Hapus direktori data
# ============================================================================
step "Hapus direktori config & data"

if [[ "$DEEP" == "1" ]] || confirm "Hapus /root/.hermes (KONFIG, .env, SOUL.md, sessions, skills)?"; then
  rm -rf /root/.hermes
  ok "/root/.hermes dihapus"
fi

if [[ "$DEEP" == "1" ]] || confirm "Hapus /root/.9router (DB admin + password + provider config)?"; then
  rm -rf /root/.9router
  ok "/root/.9router dihapus"
fi

# ============================================================================
# 7. Cache & sisa
# ============================================================================
step "Bersihin cache & sisa"

rm -rf /root/.cache/uv 2>/dev/null || true
find /root/.cache/pip -maxdepth 3 -name '*hermes*' -exec rm -rf {} + 2>/dev/null || true
find /root/.npm -maxdepth 3 -name '*hermes*' -exec rm -rf {} + 2>/dev/null || true
find /root/.npm -maxdepth 3 -name '*9router*' -exec rm -rf {} + 2>/dev/null || true

rm -f /var/log/9router-tunnel.log
rm -f /var/log/hermes*.log 2>/dev/null || true

if [[ -d /root/.cloudflared ]]; then
  if [[ "$DEEP" == "1" ]] || confirm "Hapus /root/.cloudflared (named tunnel credentials)?"; then
    rm -rf /root/.cloudflared
    ok "/root/.cloudflared dihapus"
  fi
fi
rm -rf /etc/cloudflared 2>/dev/null || true
rm -rf /tmp/.9r-cli-helper 2>/dev/null || true

ok "Cache dibersihin"

# ============================================================================
# 8. Verifikasi
# ============================================================================
step "Verifikasi"

LEFTOVER=()

for svc in "${UNITS[@]}"; do
  if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}.service"; then
    LEFTOVER+=("service: $svc")
  fi
done

# Cek docker container masih ada
if command -v docker >/dev/null 2>&1; then
  docker_left=$(docker ps -a --filter 'name=9router' --format '{{.Names}}' 2>/dev/null || true)
  if [[ -n "$docker_left" ]]; then
    LEFTOVER+=("docker: $docker_left")
  fi
fi

for pat in "${PATTERNS[@]}"; do
  if pgrep -f "$pat" >/dev/null 2>&1; then
    LEFTOVER+=("proses: $pat")
  fi
done

for d in /root/.hermes /root/.9router /usr/local/lib/hermes-agent; do
  if [[ -e "$d" ]]; then
    LEFTOVER+=("dir: $d")
  fi
done

for b in hermes 9router cloudflared; do
  if command -v "$b" >/dev/null 2>&1; then
    LEFTOVER+=("bin: $(which $b)")
  fi
done

if [[ ${#LEFTOVER[@]} -eq 0 ]]; then
  ok "VPS bersih total. Siap install dari nol."
else
  warn "Ada sisa yang ga ke-hapus (mungkin lo jawab 'n' di prompt):"
  for item in "${LEFTOVER[@]}"; do
    echo "    - $item"
  done
  echo
  warn "Buat hapus paksa semua tanpa prompt:"
  echo "    sudo DEEP_CLEAN=1 bash uninstall.sh"
fi

echo
ok "Uninstall selesai. Install ulang dari nol:"
echo "    sudo bash install.sh"
echo
