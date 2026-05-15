#!/usr/bin/env bash
# fix.sh — repair install yang gagal di tengah jalan.
#
# Pake ini kalau lo ngalamin salah satu dari ini:
#   - 9router-tunnel restart loop (Main process exited code=killed status=9)
#   - "Failed to start hermes-gateway.service: Unit not found"
#   - tunnel-url.txt ga ada
#   - hermes ga keinstall, atau install ga lengkap
#   - bot ga respond karena config.yaml ga nunjuk ke 9router
#
# Pakai:  sudo bash fix.sh
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/lib.sh"

require_root

cat <<'BANNER'
================================================
  Repair Tool - Hermes + 9Router + Tunnel
================================================

Tool ini bakal:
  1) Stop & hapus service lama yang bermasalah
  2) Pasang ulang tunnel pake --protocol http2 (anti restart-loop)
  3) Install Hermes pake installer resmi (kalo belum ada)
  4) Pasang ulang config.yaml + SOUL.md + .env template
  5) Bikin tunnel-url.txt + verify dashboard jalan

Aman buat dipake walaupun install.sh sebelumnya udah jalan (idempotent).

BANNER

if ! confirm "Lanjut?"; then
  echo "Cancel."
  exit 0
fi

# ---------- 0. Pastikan ada swap (anti OOM-kill di VPS RAM kecil) ----------
step "Cek memori (RAM + swap)"
ensure_swap_available 3072 || warn "Memori kurang, install bisa OOM-kill. Lanjut anyway."

# ---------- 1. Bersihin service lama yang bermasalah ----------
step "Bersihin systemd service lama (restart-loop / typo nama)"

for svc in hermes hermes-gateway hermes-bot 9router-tunnel; do
  if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}.service"; then
    log "Stop & disable $svc"
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
    systemctl reset-failed "$svc" 2>/dev/null || true
  fi
done

rm -f /etc/systemd/system/hermes.service        # legacy
rm -f /etc/systemd/system/9router-tunnel.service
systemctl daemon-reload
ok "Service lama dibersihin"

# ---------- 2. Pastikan 9router masih jalan ----------
step "Cek 9Router"
if ! systemctl is-active --quiet 9router; then
  warn "9router ga aktif, coba restart"
  systemctl restart 9router
  sleep 3
fi

if wait_for_9router 15; then
  ok "9Router responsive di ${NINER_BASE}"
else
  err "9Router ga nyahut. Cek: journalctl -u 9router -n 50"
  exit 1
fi

# ---------- 3. Pasang ulang tunnel service (versi http2) ----------
step "Pasang ulang 9router-tunnel (versi http2, anti restart-loop)"
bash "$SCRIPT_DIR/scripts/setup-tunnel.sh"

# ---------- 4. Install Hermes Agent ----------
step "Install / verify Hermes Agent"

# Pastiin PATH ke-pickup
export PATH="/usr/local/bin:/root/.local/bin:$PATH"

if command -v hermes >/dev/null 2>&1; then
  ok "Hermes udah keinstall: $(which hermes)"
else
  # Bersihin sisa npm install lama (legacy bug dari early version repo)
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

# config.yaml — INI YANG BIKIN BOT NYAMBUNG SAMA 9ROUTER
# Default config dari Hermes installer ngarahin ke OpenRouter, BUKAN 9router.
# Replace selalu (kecuali user udah customize) supaya provider=custom +
# base_url=9router jelas di-set.
if [[ -f "$HERMES_DIR/config.yaml" ]]; then
  if ! grep -q 'localhost:20128' "$HERMES_DIR/config.yaml"; then
    log "config.yaml ada tapi ga nunjuk ke 9router — backup & replace"
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

${C_GREEN}================ FIX SELESAI ================${C_RESET}

  9Router (lokal)   : ${NINER_BASE}
  9Router (publik)  : ${TUNNEL_URL:-<belum tersedia, cek 'journalctl -u 9router-tunnel -n 30'>}
  Hermes binary     : $(command -v hermes 2>/dev/null || echo '<not found>')
  Hermes config     : $HERMES_DIR/config.yaml
  Hermes persona    : $HERMES_DIR/SOUL.md

${C_BOLD}LANGKAH SELANJUTNYA:${C_RESET}

  1) Buka URL publik di atas, set password admin (kalo belum)
  2) Bikin API key 9router (Settings > API Keys > New)
  3) Tambah provider:
     ${C_BOLD}bash add-provider.sh${C_RESET}
  4) Set token Telegram + 9router key + install gateway service:
     ${C_BOLD}bash configure-hermes.sh${C_RESET}

${C_BOLD}STATUS:${C_RESET}
  systemctl status 9router 9router-tunnel
  journalctl -u 9router-tunnel -n 20 --no-pager

EOF
