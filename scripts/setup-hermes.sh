#!/usr/bin/env bash
# Install Hermes (Telegram bot) + setup systemd service.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

require_root

step "Bikin direktori Hermes"
mkdir -p "$HERMES_DIR"
chmod 700 "$HERMES_DIR"

step "Install Hermes Agent (npm)"
# Hermes biasanya dipakai sebagai package npm. Kita install di $HERMES_DIR
# supaya gampang upgrade dan ga ngotorin global namespace lain.
cd "$HERMES_DIR"
if [[ ! -f package.json ]]; then
  cat > package.json <<'EOF'
{
  "name": "hermes-runtime",
  "version": "1.0.0",
  "private": true,
  "description": "Hermes agent runtime container",
  "dependencies": {}
}
EOF
fi

# Install (kalau belum ada atau lo mau update)
if [[ ! -d node_modules/hermes-agent ]]; then
  npm install hermes-agent --no-audit --no-fund
  ok "hermes-agent terinstall"
else
  ok "hermes-agent udah ada (skip install)"
fi

step "Bikin .env template (kalau belum ada)"
if [[ ! -f "$HERMES_DIR/.env" ]]; then
  install -m 600 "$REPO_DIR/templates/hermes.env.template" "$HERMES_DIR/.env"
  ok ".env template di-copy ke $HERMES_DIR/.env"
  warn "INGAT: edit dulu $HERMES_DIR/.env atau jalanin: bash configure-hermes.sh"
else
  ok ".env udah ada (skip)"
fi

step "Bikin config.yaml (kalau belum ada)"
if [[ ! -f "$HERMES_DIR/config.yaml" ]]; then
  install -m 600 "$REPO_DIR/templates/hermes-config.yaml.template" "$HERMES_DIR/config.yaml"
  ok "config.yaml di-copy"
else
  ok "config.yaml udah ada (skip)"
fi

step "Install systemd service: hermes"
install -m 644 "$REPO_DIR/services/hermes.service" /etc/systemd/system/hermes.service
systemctl daemon-reload
systemctl enable hermes >/dev/null 2>&1
# Sengaja ga auto-restart hermes di sini — user belum isi token Telegram.
ok "Service hermes terdaftar (belum di-start; isi .env dulu)"
