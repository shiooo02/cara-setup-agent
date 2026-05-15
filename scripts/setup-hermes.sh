#!/usr/bin/env bash
# Install Hermes Agent (Nous Research) — pakai installer resmi.
# Hermes punya CLI sendiri (`hermes setup`, `hermes gateway install`)
# yang otomatis handle systemd service.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

require_root

step "Cek apakah Hermes udah keinstall"
if command -v hermes >/dev/null 2>&1; then
  ok "Hermes udah ada: $(which hermes)"
else
  step "Install Hermes Agent (Nous Research, official installer)"
  log "Ngambil installer resmi dari github.com/NousResearch/hermes-agent..."

  # Flags:
  #   --skip-setup    = jangan jalanin wizard interaktif
  #   --skip-browser  = skip Playwright/Chromium (~500MB, opsional)
  curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh \
    | bash -s -- --skip-setup --skip-browser

  # Refresh PATH (installer naro di /usr/local/bin atau /root/.local/bin)
  export PATH="/usr/local/bin:/root/.local/bin:$PATH"

  if command -v hermes >/dev/null 2>&1; then
    ok "Hermes terinstall: $(which hermes)"
  else
    warn "Hermes installer selesai tapi 'hermes' belum ke-detect di PATH."
    warn "Coba: source ~/.bashrc; which hermes"
  fi
fi

step "Bikin direktori data Hermes"
mkdir -p "$HERMES_DIR"
chmod 700 "$HERMES_DIR"

# .env dari template
if [[ ! -f "$HERMES_DIR/.env" ]]; then
  install -m 600 "$REPO_DIR/templates/hermes.env.template" "$HERMES_DIR/.env"
  ok ".env template di-copy"
fi

# config.yaml — INI YANG PALING PENTING.
# Default config dari Hermes installer ngarahin ke OpenRouter/Anthropic, BUKAN
# 9router. Tanpa replace ini, `hermes gateway install` jalan tapi `hermes`
# coba connect ke endpoint yg salah → bot ga nyambung sama 9router.
if [[ ! -f "$HERMES_DIR/config.yaml" ]]; then
  install -m 600 "$REPO_DIR/templates/hermes-config.yaml.template" "$HERMES_DIR/config.yaml"
  ok "config.yaml di-copy (provider=custom, base_url=9router)"
else
  warn "config.yaml udah ada — skip biar customisasi lo gak ke-overwrite."
  warn "Kalo bot ga nyambung, backup terus replace pake template:"
  echo "    cp $HERMES_DIR/config.yaml $HERMES_DIR/config.yaml.bak"
  echo "    cp $REPO_DIR/templates/hermes-config.yaml.template $HERMES_DIR/config.yaml"
fi

# SOUL.md (persona) — Hermes bakal load file ini tiap respond
if [[ ! -f "$HERMES_DIR/SOUL.md" ]]; then
  install -m 644 "$REPO_DIR/templates/SOUL.md.template" "$HERMES_DIR/SOUL.md"
  ok "SOUL.md (persona Mahiru) di-copy ke $HERMES_DIR/SOUL.md"
  log "Edit kapan aja — Hermes auto-reload tanpa restart."
fi

ok "Hermes ready. Konfigurasi token via: bash configure-hermes.sh"
