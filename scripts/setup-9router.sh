#!/usr/bin/env bash
# Install 9Router as Docker container.
#
# Kenapa Docker bukan npm? 9router 0.4.50 punya interactive launcher menu
# ("Choose Interface" -> Web UI/Terminal UI/Tray/Exit) yg butuh TTY.
# Pas dijalanin lewat systemd (no TTY), wrapper-nya exit -> service stuck
# di restart loop dengan exit code 0 ("Deactivated successfully" terus).
#
# Docker image dari decolua/9router:latest punya ENTRYPOINT yg langsung
# start Next.js server tanpa menu interaktif. Plus better-sqlite3 udah
# pre-compiled di image, jadi ga perlu native compile pas first start
# (yg di VPS RAM kecil bisa OOM-kill).
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

require_root

# ---------- 1. Pastikan Docker terinstall ----------
step "Cek Docker"
if command -v docker >/dev/null 2>&1; then
  ok "Docker udah keinstall: $(docker --version | head -1)"
else
  log "Install docker.io dari apt"
  apt-get install -y docker.io
  systemctl enable docker
  systemctl start docker
  ok "Docker terinstall: $(docker --version | head -1)"
fi

# Pastiin Docker daemon jalan
if ! systemctl is-active --quiet docker; then
  log "Start Docker daemon"
  systemctl start docker
  sleep 2
fi

# ---------- 2. Stop & hapus container 9router lama (kalo ada) ----------
step "Bersihin container 9router lama (kalo ada)"
if docker ps -a --format '{{.Names}}' | grep -q '^9router$'; then
  log "Stop & hapus container '9router' lama"
  docker stop 9router 2>/dev/null || true
  docker rm 9router 2>/dev/null || true
fi

# ---------- 3. Pull image terbaru ----------
step "Pull image decolua/9router:latest"
log "Ini bisa makan 1-2 menit (image ~200MB)"
docker pull decolua/9router:latest
ok "Image siap"

# ---------- 4. Bersihin npm 9router lama (legacy install) ----------
# Kalo user sebelumnya install lewat npm install -g 9router, hapus dulu
# biar ga conflict (binary di PATH bisa mancing user run yg salah)
step "Bersihin npm 9router lama (legacy)"
if command -v 9router >/dev/null 2>&1; then
  log "npm 9router ditemukan, hapus"
  npm uninstall -g 9router 2>/dev/null || true
  rm -f /usr/bin/9router /usr/local/bin/9router 2>/dev/null || true
fi

# Hapus runtime npm yang korup (kalo ada)
if [[ -d /root/.9router/runtime ]]; then
  log "Hapus /root/.9router/runtime (sisa dari npm install lama)"
  rm -rf /root/.9router/runtime
fi

# Pastikan data dir ada (Docker bind mount ke sini)
mkdir -p "$NINER_DIR"

# ---------- 5. Hapus systemd unit lama (kalo dari install npm sebelumnya) ----------
if [[ -f /etc/systemd/system/9router.service ]]; then
  log "Stop & hapus 9router.service lama (yg pakai npm)"
  systemctl stop 9router 2>/dev/null || true
  systemctl disable 9router 2>/dev/null || true
  systemctl reset-failed 9router 2>/dev/null || true
  rm -f /etc/systemd/system/9router.service
  systemctl daemon-reload
fi

# ---------- 6. Start container ----------
step "Start container 9router"
# --restart unless-stopped: container auto-restart kalo crash, tapi
#                          stop kalo user manual `docker stop`
# -p 127.0.0.1:20128:20128: bind ke localhost only (tunnel yg expose ke public)
# -v $NINER_DIR:/app/data: persist DB + provider config di /root/.9router
# --memory 1024m: hard limit (image lebih ringan dari npm version)
# --memory-swap 1536m: kasih ruang swap kalo perlu
docker run -d \
  --name 9router \
  --restart unless-stopped \
  --memory 1024m \
  --memory-swap 1536m \
  -p 127.0.0.1:${NINER_PORT}:20128 \
  -v "${NINER_DIR}:/app/data" \
  -e DATA_DIR=/app/data \
  -e PORT=20128 \
  -e HOSTNAME=0.0.0.0 \
  decolua/9router:latest

ok "Container 9router started"

# ---------- 7. Tunggu 9router responsive ----------
log "Nunggu 9router siap di port ${NINER_PORT}..."
if wait_for_9router 60; then
  ok "9router up & running di ${NINER_BASE}"
else
  warn "9router belum nyahut setelah 60 detik."
  warn "Cek log: docker logs 9router"
  echo
  docker logs 9router 2>&1 | tail -30
fi
