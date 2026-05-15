#!/usr/bin/env bash
# configure-hermes.sh — set Telegram bot token + 9router API key buat Hermes,
# terus install systemd service via `hermes gateway install`.
#
# Pakai:  bash configure-hermes.sh
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/lib.sh"

require_root
ensure_hermes_env

ENV_FILE="$HERMES_DIR/.env"

# Cek hermes ada
if ! command -v hermes >/dev/null 2>&1; then
  die "Hermes ga ada di PATH. Jalanin install.sh dulu."
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
  # Hermes pake TELEGRAM_ALLOWED_USERS buat allowlist
  set_env_var "$ENV_FILE" "TELEGRAM_ALLOWED_USERS" "$TG_OWNER"
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

# ---------- Install + start gateway service ----------
step "Install / restart Hermes gateway service"

# `hermes gateway install` bikin systemd unit otomatis
if systemctl list-unit-files 2>/dev/null | grep -q '^hermes'; then
  log "Hermes gateway service udah ada — restart aja"
  systemctl restart hermes-gateway 2>/dev/null \
    || systemctl restart hermes 2>/dev/null \
    || hermes gateway restart 2>/dev/null \
    || true
else
  log "Install Hermes gateway service via 'hermes gateway install'"
  hermes gateway install || warn "hermes gateway install gagal — coba manual"
  hermes gateway start 2>/dev/null || systemctl start hermes-gateway 2>/dev/null || true
fi

sleep 3

# Cari nama unit yang dipake
SVC=""
for s in hermes-gateway hermes; do
  if systemctl list-unit-files 2>/dev/null | grep -q "^${s}.service"; then
    SVC="$s"
    break
  fi
done

if [[ -n "$SVC" ]] && systemctl is-active --quiet "$SVC"; then
  ok "Hermes gateway jalan! (service: $SVC)"
  echo
  echo "Test sekarang: kirim ${C_BOLD}/start${C_RESET} ke bot lo di Telegram."
  echo "Liat log realtime: ${C_BOLD}journalctl -u $SVC -f${C_RESET}"
else
  warn "Hermes gateway belum aktif. Cek log:"
  echo "    journalctl -u hermes-gateway -n 30 --no-pager"
  echo "    journalctl -u hermes -n 30 --no-pager"
  echo "Atau jalanin foreground buat liat error langsung:"
  echo "    hermes gateway"
fi
