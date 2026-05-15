#!/usr/bin/env bash
# Install 9Router + setup systemd service.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

require_root

step "Install 9Router (npm global)"
if command -v 9router >/dev/null 2>&1; then
  ok "9router udah keinstall: $(9router --version 2>/dev/null || echo 'unknown')"
else
  npm install -g 9router
  ok "9router terinstall: $(9router --version 2>/dev/null || echo 'unknown')"
fi

step "Pre-warm 9router runtime (npm install better-sqlite3, sekali bayar)"
# 9router pertama kali start bakal nge-spawn `npm install better-sqlite3`
# yang butuh ~1.5GB RAM buat compile native code. Kalo dijalanin lewat
# systemd langsung, OOM killer sering action sebelum compile selesai.
# Jadi kita warm dulu manual (ada terminal feedback + cukup waktu).
mkdir -p "$NINER_DIR/runtime"
log "Ini bisa makan waktu 1-3 menit (kompilasi C++ better-sqlite3)..."
timeout 300 9router --version >/dev/null 2>&1 &
PREWARM_PID=$!

# Tunggu sampe runtime install selesai (better-sqlite3 ke-build)
WARMED=0
for i in {1..180}; do
  if [[ -d "$NINER_DIR/runtime/node_modules/better-sqlite3/build/Release" ]] \
     || [[ -d "$NINER_DIR/runtime/node_modules/better-sqlite3/lib/binding" ]]; then
    WARMED=1
    break
  fi
  sleep 1
done

# Stop pre-warm process
kill "$PREWARM_PID" 2>/dev/null || true
wait "$PREWARM_PID" 2>/dev/null || true

if (( WARMED == 1 )); then
  ok "Runtime 9router udah ke-build (better-sqlite3 ready)"
else
  warn "Pre-warm timeout, lanjut anyway — systemd bakal coba sendiri"
fi

step "Install systemd service: 9router"
install -m 644 "$REPO_DIR/services/9router.service" /etc/systemd/system/9router.service
systemctl daemon-reload
systemctl enable 9router >/dev/null 2>&1
systemctl restart 9router

log "Nunggu 9router ready di port ${NINER_PORT}..."
if wait_for_9router 60; then
  ok "9router up & running di ${NINER_BASE}"
else
  warn "9router belum nyahut setelah 60 detik."
  warn "Cek log: journalctl -u 9router -n 50 --no-pager"
  warn "Kalo ada 'Killed' di log = OOM. Tambah swap manual:"
  echo "    fallocate -l 4G /swapfile && chmod 600 /swapfile"
  echo "    mkswap /swapfile && swapon /swapfile"
  echo "    systemctl restart 9router"
fi
