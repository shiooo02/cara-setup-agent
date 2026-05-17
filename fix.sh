#!/usr/bin/env bash
# fix.sh - repair install yang gagal di tengah jalan.
#
# Pake ini kalau lo ngalamin salah satu dari ini:
#   - 9router-tunnel restart loop / status=9/KILL
#   - Container '9router' ga jalan / docker ga keinstall
#   - 'Failed to start hermes-gateway.service: Unit not found'
#   - tunnel-url.txt ga ada
#   - Bot ga respond karena config.yaml ga nunjuk ke 9router
#
# Pakai:  sudo bash fix.sh
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/lib.sh"

require_root

cat <<'BANNER'
================================================
  Repair Tool - Hermes + 9Router (docker) + Tunnel
================================================

Tool ini bakal:
  1) Stop & hapus service legacy (npm 9router yg restart-loop)
  2) Pasang ulang 9router via Docker (anti-OOM, anti-interactive-menu)
  3) Pasang ulang tunnel pake --protocol http2
  4) Install Hermes pake installer resmi (kalo belum ada)
  5) Pasang ulang config.yaml + SOUL.md + .env template

Aman buat dipake walaupun install.sh sebelumnya udah jalan (idempotent).

BANNER

if ! confirm "Lanjut?"; then
  echo "Cancel."
  exit 0
fi

# ---------- 0. Pastikan ada swap ----------
step "Cek memori (RAM + swap)"
ensure_swap_available 3072 || warn "Memori kurang, tetep lanjut."

# ---------- 1. Bersihin systemd unit lama (npm-based, restart-loop) ----------
step "Bersihin systemd unit lama"

for svc in 9router 9router-tunnel hermes hermes-gateway hermes-bot; do
  if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}.service"; then
    log "Stop & disable $svc"
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
    systemctl reset-failed "$svc" 2>/dev/null || true
  fi
done

rm -f /etc/systemd/system/9router.service       # legacy npm
rm -f /etc/systemd/system/9router-tunnel.service
rm -f /etc/systemd/system/hermes.service
systemctl daemon-reload

# Kill stray processes
pkill -f '9router' 2>/dev/null || true
pkill -f 'cloudflared.*tunnel' 2>/dev/null || true
sleep 1
ok "Service lama dibersihin"

# ---------- 2. Pasang 9router via Docker ----------
step "Pasang 9router via Docker (replace npm install)"
bash "$SCRIPT_DIR/scripts/setup-9router.sh"

if wait_for_9router 30; then
  ok "9router responsive di ${NINER_BASE}"
else
  err "9router ga nyahut. Cek: docker logs 9router"
  docker logs 9router 2>&1 | tail -20
  exit 1
fi

# ---------- 3. Pasang ulang tunnel ----------
step "Pasang ulang 9router-tunnel"
bash "$SCRIPT_DIR/scripts/setup-tunnel.sh"

systemctl reset-failed 9router-tunnel 2>/dev/null || true
systemctl restart 9router-tunnel
sleep 8

# Capture URL
source "$SCRIPT_DIR/scripts/setup-tunnel.sh"
capture_tunnel_url || warn "Tunnel URL belum keluar - rerun ' systemctl restart 9router-tunnel'"

# ---------- 4. Install Hermes Agent ----------
step "Install / verify Hermes Agent"
export PATH="/usr/local/bin:/root/.local/bin:$PATH"

if command -v hermes >/dev/null 2>&1; then
  ok "Hermes udah keinstall: $(which hermes)"
else
  if [[ -d "$HERMES_DIR/node_modules" ]]; then
    log "Bersihin sisa npm install lama di $HERMES_DIR"
    rm -rf "$HERMES_DIR/node_modules" "$HERMES_DIR/package.json" "$HERMES_DIR/package-lock.json"
  fi

  log "Download & jalanin installer resmi..."
  curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh \
    | bash -s -- --skip-setup --skip-browser

  export PATH="/usr/local/bin:/root/.local/bin:$PATH"

  if command -v hermes >/dev/null 2>&1; then
    ok "Hermes terinstall: $(which hermes)"
  else
    err "Hermes installer selesai tapi 'hermes' ga di PATH."
    err "Coba: source ~/.bashrc; logout-login; rerun: bash configure-hermes.sh"
    exit 1
  fi
fi

# ---------- 5. Pasang config + persona + env ----------
step "Pasang config.yaml + SOUL.md + .env (Hermes ke 9router)"
ensure_hermes_env

# .env
if [[ ! -s "$HERMES_DIR/.env" ]] || ! grep -q TELEGRAM_BOT_TOKEN "$HERMES_DIR/.env"; then
  install -m 600 "$SCRIPT_DIR/templates/hermes.env.template" "$HERMES_DIR/.env"
  ok ".env template dipasang"
fi

# config.yaml - INI YANG BIKIN BOT NYAMBUNG SAMA 9ROUTER
# Default config dari Hermes installer ngarahin ke OpenRouter, BUKAN 9router.
if [[ -f "$HERMES_DIR/config.yaml" ]]; then
  if ! grep -q 'localhost:20128' "$HERMES_DIR/config.yaml"; then
    log "config.yaml ada tapi ga nunjuk ke 9router - backup & replace"
    cp "$HERMES_DIR/config.yaml" "$HERMES_DIR/config.yaml.bak.$(date +%s)"
    install -m 600 "$SCRIPT_DIR/templates/hermes-config.yaml.template" "$HERMES_DIR/config.yaml"
    ok "config.yaml di-replace (provider=custom, base_url=9router)"
  else
    ok "config.yaml udah benar (sudah pointing ke 9router)"
  fi
else
  install -m 600 "$SCRIPT_DIR/templates/hermes-config.yaml.template" "$HERMES_DIR/config.yaml"
  ok "config.yaml dipasang"
fi

# SOUL.md
if [[ ! -f "$HERMES_DIR/SOUL.md" ]]; then
  install -m 644 "$SCRIPT_DIR/templates/SOUL.md.template" "$HERMES_DIR/SOUL.md"
  ok "SOUL.md (persona Mahiru) dipasang"
fi

# ---------- 6. Summary ----------
TUNNEL_URL=""
[[ -f "$HERMES_DIR/tunnel-url.txt" ]] && TUNNEL_URL=$(cat "$HERMES_DIR/tunnel-url.txt")

cat <<EOF

================ FIX SELESAI ================

  9Router (lokal)   : ${NINER_BASE} (via Docker container)
  9Router (publik)  : ${TUNNEL_URL:-<belum tersedia, cek docker logs 9router>}
  Hermes binary     : $(command -v hermes 2>/dev/null || echo '<not found>')
  Hermes config     : $HERMES_DIR/config.yaml
  Hermes persona    : $HERMES_DIR/SOUL.md

LANGKAH SELANJUTNYA:

  1) Buka URL publik di atas, set password admin
  2) Bikin API key 9router (Settings > API Keys > New)
  3) Tambah provider:        bash add-provider.sh
  4) Set token + start bot:  bash configure-hermes.sh

STATUS:
  docker ps                                    # 9router (docker)
  systemctl status 9router-tunnel hermes-gateway
  docker logs -f 9router                       # log 9router
  journalctl -u hermes-gateway -f              # log bot

EOF
