#!/usr/bin/env bash
# fix.sh — repair install yang gagal di tengah jalan.
#
# Pake ini kalau lo ngalamin salah satu dari ini:
#   - 9router-tunnel restart loop (Main process exited code=killed status=9)
#   - "Failed to start hermes.service: Unit hermes.service not found"
#   - tunnel-url.txt ga ada
#   - hermes ga keinstall karena dulu pake nama package npm yg salah
#
# Pakai:  sudo bash fix.sh
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/lib.sh"

require_root

cat <<'BANNER'
================================================
  Repair Tool — Hermes + 9Router + Tunnel
================================================

Tool ini bakal:
  1) Stop & hapus service lama yang bermasalah
  2) Install ulang Hermes pake installer resmi (Python, bukan npm)
  3) Pasang systemd unit baru buat tunnel (--protocol http2, anti restart-loop)
  4) Bikin tunnel-url.txt + verify dashboard jalan

Aman buat dipake walaupun install.sh sebelumnya udah jalan.

BANNER

if ! confirm "Lanjut?"; then
  echo "Cancel."
  exit 0
fi

# ---------- 1. Bersihin service lama yang bermasalah ----------
step "Bersihin systemd service lama"

# Stop service yg restart-loop (yang lo alami: 9router-tunnel 738x restart)
for svc in hermes hermes-gateway 9router-tunnel; do
  if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}.service"; then
    log "Stop & disable $svc"
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
    systemctl reset-failed "$svc" 2>/dev/null || true
  fi
done

# Hapus unit file lama (yang dipasang install.sh sebelumnya)
rm -f /etc/systemd/system/hermes.service
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

# ---------- 3. Pasang ulang tunnel service (versi yang udah di-fix) ----------
step "Pasang ulang 9router-tunnel (versi http2, anti restart-loop)"
bash "$SCRIPT_DIR/scripts/setup-tunnel.sh"

# ---------- 4. Install Hermes Agent (Python, official) ----------
step "Install Hermes Agent (official Nous Research installer)"

if command -v hermes >/dev/null 2>&1; then
  ok "Hermes udah keinstall: $(which hermes)"
else
  # Bersihin sisa dari install.sh sebelumnya yang ga jadi
  if [[ -d "$HERMES_DIR/node_modules" ]]; then
    log "Bersihin sisa npm install lama di $HERMES_DIR"
    rm -rf "$HERMES_DIR/node_modules" "$HERMES_DIR/package.json" "$HERMES_DIR/package-lock.json"
  fi

  log "Download & jalanin installer resmi..."
  curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh \
    | bash -s -- --skip-setup --skip-browser

  if ! command -v hermes >/dev/null 2>&1; then
    # Coba sourcing PATH update
    export PATH="/usr/local/bin:/root/.local/bin:$PATH"
  fi

  if command -v hermes >/dev/null 2>&1; then
    ok "Hermes terinstall: $(which hermes)"
  else
    err "Hermes installer selesai tapi 'hermes' belum di PATH."
    err "Coba: source ~/.bashrc atau logout-login lagi, terus rerun: bash configure-hermes.sh"
    exit 1
  fi
fi

# ---------- 5. Pastikan .env Hermes ada ----------
step "Pastikan .env Hermes ada"
ensure_hermes_env
if [[ ! -s "$HERMES_DIR/.env" ]] || ! grep -q TELEGRAM_BOT_TOKEN "$HERMES_DIR/.env"; then
  install -m 600 "$SCRIPT_DIR/templates/hermes.env.template" "$HERMES_DIR/.env"
  ok ".env template dipasang"
fi

# ---------- 5b. Pastikan SOUL.md (persona) ada ----------
if [[ ! -f "$HERMES_DIR/SOUL.md" ]]; then
  install -m 644 "$SCRIPT_DIR/templates/SOUL.md.template" "$HERMES_DIR/SOUL.md"
  ok "SOUL.md (persona Mahiru) dipasang di $HERMES_DIR/SOUL.md"
fi

# ---------- 6. Summary ----------
TUNNEL_URL=""
[[ -f "$HERMES_DIR/tunnel-url.txt" ]] && TUNNEL_URL=$(cat "$HERMES_DIR/tunnel-url.txt")

cat <<EOF

${C_GREEN}================ FIX SELESAI ================${C_RESET}

  9Router (lokal)   : ${NINER_BASE}
  9Router (publik)  : ${TUNNEL_URL:-<belum tersedia, cek 'journalctl -u 9router-tunnel'>}
  Hermes binary     : $(command -v hermes 2>/dev/null || echo '<not found>')

${C_BOLD}LANGKAH SELANJUTNYA:${C_RESET}

  1) Buka URL publik di atas → set password admin (kalau belum)
  2) Bikin API key 9router (Settings → API Keys → New)
  3) Tambah provider:
     ${C_BOLD}bash add-provider.sh${C_RESET}
  4) Set token Telegram + 9router key + install gateway service:
     ${C_BOLD}bash configure-hermes.sh${C_RESET}

${C_BOLD}STATUS:${C_RESET}
  systemctl status 9router 9router-tunnel
  journalctl -u 9router-tunnel -n 20 --no-pager

EOF
