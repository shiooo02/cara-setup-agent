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

step "Install systemd service: 9router"
install -m 644 "$REPO_DIR/services/9router.service" /etc/systemd/system/9router.service
systemctl daemon-reload
systemctl enable 9router >/dev/null 2>&1
systemctl restart 9router

log "Nunggu 9router ready di port ${NINER_PORT}..."
if wait_for_9router 30; then
  ok "9router up & running di ${NINER_BASE}"
else
  warn "9router belum nyahut. Cek: journalctl -u 9router -n 50"
fi
