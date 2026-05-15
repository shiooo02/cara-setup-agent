#!/usr/bin/env bash
# Install Hermes Agent (Nous Research) — pakai installer resminya.
# Hermes punya CLI sendiri (`hermes setup`, `hermes gateway install`)
# yang otomatis handle systemd service. Jadi kita TIDAK bikin
# hermes.service custom — cukup panggil `hermes gateway install` nanti.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

require_root

step "Cek apakah Hermes udah keinstall"
if command -v hermes >/dev/null 2>&1; then
  ok "Hermes udah ada: $(hermes --version 2>/dev/null || echo 'installed')"
  return 0 2>/dev/null || exit 0
fi

step "Install Hermes Agent (Nous Research, official installer)"
log "Ngambil installer resmi dari github.com/NousResearch/hermes-agent..."

# Flags yang dipake:
#   --skip-setup    = jangan jalanin wizard interaktif (kita pake configure-hermes.sh)
#   --skip-browser  = skip Playwright/Chromium (~500MB, opsional, bisa diinstall belakangan)
#
# Kalau lo butuh fitur browse web Hermes, edit baris ini hapus --skip-browser
# atau jalanin manual: cd /usr/local/lib/hermes-agent && npx playwright install --with-deps chromium
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh \
  | bash -s -- --skip-setup --skip-browser

# Installer resmi naro hermes di /usr/local/bin/hermes (root install, FHS layout)
# atau ~/.local/bin/hermes (non-root). Karena kita root, harusnya /usr/local/bin.
if command -v hermes >/dev/null 2>&1; then
  ok "Hermes terinstall: $(which hermes)"
else
  warn "Hermes installer selesai tapi 'hermes' ga di PATH."
  warn "Coba: source ~/.bashrc; which hermes"
fi

step "Bikin direktori data Hermes (kalau installer skip)"
mkdir -p "$HERMES_DIR"
chmod 700 "$HERMES_DIR"

# Pastiin .env ada
if [[ ! -f "$HERMES_DIR/.env" ]]; then
  install -m 600 "$REPO_DIR/templates/hermes.env.template" "$HERMES_DIR/.env"
  ok ".env template di-copy"
fi

ok "Hermes ready. Konfigurasi token via: bash configure-hermes.sh"
