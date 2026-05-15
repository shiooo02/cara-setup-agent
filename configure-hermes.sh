#!/usr/bin/env bash
# configure-hermes.sh — set Telegram bot token + 9router API key buat Hermes,
# terus install + start systemd service via `hermes gateway install`.
#
# Pakai:  bash configure-hermes.sh
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/lib.sh"

require_root

# Pastikan PATH ke-pickup hermes binary
export PATH="/usr/local/bin:/root/.local/bin:$PATH"

ensure_hermes_env
ENV_FILE="$HERMES_DIR/.env"

# ============================================================================
# Pre-flight checks
# ============================================================================
if ! command -v hermes >/dev/null 2>&1; then
  err "Binary 'hermes' ga ditemukan di PATH."
  err "Cek: which hermes; ls -la /usr/local/bin/hermes /root/.local/bin/hermes"
  err "Kalau memang ga ada, jalanin: sudo bash install.sh  (atau bash fix.sh)"
  exit 1
fi

# Helper: baca value existing dari .env
get_existing() {
  grep -E "^${1}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d'=' -f2- || true
}

cat <<EOF

${C_BOLD}=== Konfigurasi Hermes (Telegram bot) ===${C_RESET}

Lo butuh 3 hal:
  1) Telegram bot token  - dari @BotFather di Telegram
  2) Telegram user ID    - chat sama @userinfobot, copy ID lo
  3) 9Router API key     - dari dashboard: Settings -> API Keys -> New

Tekan ENTER kalau mau ke-skip nilai yang udah ada.

EOF

# ---------- Telegram bot token ----------
existing=$(get_existing TELEGRAM_BOT_TOKEN)
if [[ -n "$existing" ]]; then
  echo "Current TELEGRAM_BOT_TOKEN: ${existing:0:8}...${existing: -4}"
fi
TG_TOKEN=$(ask_secret "Telegram bot token (kosongin = skip)")
if [[ -n "$TG_TOKEN" ]]; then
  set_env_var "$ENV_FILE" "TELEGRAM_BOT_TOKEN" "$TG_TOKEN"
  ok "Token Telegram di-save"
fi

# ---------- Telegram owner ID ----------
existing=$(get_existing TELEGRAM_OWNER_ID)
if [[ -n "$existing" ]]; then
  echo "Current TELEGRAM_OWNER_ID: $existing"
fi
TG_OWNER=$(ask "Telegram owner ID (angka)" "$existing")
if [[ -n "$TG_OWNER" ]]; then
  set_env_var "$ENV_FILE" "TELEGRAM_OWNER_ID" "$TG_OWNER"
  set_env_var "$ENV_FILE" "TELEGRAM_ALLOWED_USERS" "$TG_OWNER"
  ok "Owner ID di-save (allowlist diset)"
fi

# ---------- 9Router API key ----------
existing=$(get_existing OPENAI_API_KEY)
if [[ -n "$existing" ]]; then
  echo "Current OPENAI_API_KEY: ${existing:0:6}...${existing: -4}"
fi
NINE_KEY=$(ask_secret "9Router API key (kosongin = skip)")
if [[ -n "$NINE_KEY" ]]; then
  set_env_var "$ENV_FILE" "OPENAI_API_KEY" "$NINE_KEY"
  ok "9Router key di-save"
fi

# ---------- Ensure base URL & default model ----------
set_env_var "$ENV_FILE" "OPENAI_BASE_URL" "http://localhost:${NINER_PORT}/v1"

if [[ -z "$(get_existing DEFAULT_MODEL)" ]]; then
  set_env_var "$ENV_FILE" "DEFAULT_MODEL" "free_smart_fallback"
fi

# ---------- Sanity check: minimal .env udah lengkap? ----------
MISSING=()
for k in TELEGRAM_BOT_TOKEN TELEGRAM_OWNER_ID OPENAI_API_KEY; do
  v=$(get_existing "$k")
  [[ -z "$v" ]] && MISSING+=("$k")
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  warn ".env masih ada yang kosong: ${MISSING[*]}"
  warn "Hermes mungkin ga jalan. Rerun script ini kalau lo udah punya semua."
  if ! confirm "Tetep lanjut install gateway service?"; then
    exit 0
  fi
fi

# ============================================================================
# Install / restart Hermes gateway service
# ============================================================================
step "Install Hermes gateway service via 'hermes gateway install'"

# Ini bakal bikin systemd unit otomatis (biasanya hermes-gateway.service).
# Kalau udah ada, command ini idempotent.
if hermes gateway install 2>&1 | tee /tmp/hermes-gateway-install.log; then
  ok "'hermes gateway install' selesai"
else
  warn "'hermes gateway install' return error. Output di /tmp/hermes-gateway-install.log"
fi

# Refresh systemd buat ke-detect unit baru
systemctl daemon-reload

# ============================================================================
# Auto-detect nama service yang Hermes bikin
# ============================================================================
step "Auto-detect nama systemd unit Hermes"

HERMES_SVC=""
for candidate in hermes-gateway hermes hermes.service hermes-bot; do
  if systemctl list-unit-files --no-pager 2>/dev/null | grep -qE "^${candidate}\\.service"; then
    HERMES_SVC="$candidate"
    break
  fi
done

if [[ -z "$HERMES_SVC" ]]; then
  warn "Belum ke-detect systemd unit Hermes."
  log "Coba list unit yang mengandung 'hermes':"
  systemctl list-unit-files --no-pager 2>/dev/null | grep -i hermes || echo "    (kosong)"
  echo
  warn "Coba jalanin manual: hermes gateway install"
  echo
  warn "Atau jalanin foreground biar liat error langsung:"
  echo "    hermes gateway"
  exit 1
fi

ok "Service Hermes: ${HERMES_SVC}.service"

# ============================================================================
# Start service
# ============================================================================
step "Start ${HERMES_SVC}"
systemctl reset-failed "$HERMES_SVC" 2>/dev/null || true
systemctl enable "$HERMES_SVC" >/dev/null 2>&1 || true
systemctl restart "$HERMES_SVC"

sleep 4

if systemctl is-active --quiet "$HERMES_SVC"; then
  ok "Hermes gateway jalan! (service: $HERMES_SVC)"
  echo
  echo "Test sekarang: kirim ${C_BOLD}/start${C_RESET} ke bot lo di Telegram."
  echo "Liat log realtime:  ${C_BOLD}journalctl -u $HERMES_SVC -f${C_RESET}"
else
  err "Hermes gateway ga jalan. Diagnostic:"
  echo
  echo "----- STATUS -----"
  systemctl status "$HERMES_SVC" --no-pager -l | head -20 || true
  echo
  echo "----- LOG (30 baris terakhir) -----"
  journalctl -u "$HERMES_SVC" -n 30 --no-pager || true
  echo
  warn "Coba run foreground manual buat liat error langsung:"
  echo "    hermes gateway"
  exit 1
fi

# ============================================================================
# Final tip soal SOUL.md
# ============================================================================
echo
cat <<EOF

${C_BOLD}=== Personalize Agent ===${C_RESET}

Persona agent (nama, gaya bicara, etc) ada di:
    ${C_BOLD}$HERMES_DIR/SOUL.md${C_RESET}

Default-nya 'Mahiru', bahasa Indonesia santai. Edit kapan aja:
    nano $HERMES_DIR/SOUL.md

File ini di-load tiap request — gak perlu restart service.
EOF
