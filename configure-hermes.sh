#!/usr/bin/env bash
# configure-hermes.sh — set Telegram bot token + 9router API key buat Hermes.
#
# Pakai:  bash configure-hermes.sh
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/lib.sh"

require_root
ensure_hermes_env

ENV_FILE="$HERMES_DIR/.env"

# Helper: baca value existing dari .env
get_existing() {
  grep -E "^${1}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d'=' -f2- || true
}

cat <<EOF

${C_BOLD}=== Konfigurasi Hermes (Telegram bot) ===${C_RESET}

Lo butuh 3 hal:
  1) Telegram bot token  — dari @BotFather di Telegram
  2) Telegram user ID    — chat sama @userinfobot, copy ID lo
  3) 9Router API key     — dari dashboard: Settings → API Keys → New

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
  ok "Owner ID di-save"
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

# ---------- Restart Hermes ----------
step "Restart Hermes service"
systemctl restart hermes
sleep 2
if systemctl is-active --quiet hermes; then
  ok "Hermes jalan!"
  echo
  echo "Test sekarang: kirim ${C_BOLD}/start${C_RESET} ke bot lo di Telegram."
else
  warn "Hermes ga jalan. Cek log:"
  echo "    journalctl -u hermes -n 30 --no-pager"
fi
