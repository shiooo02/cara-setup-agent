#!/usr/bin/env bash
# uninstall.sh — bersih-bersih semua install dari install.sh.
#
# Pakai:  sudo bash uninstall.sh
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/lib.sh"

require_root

cat <<'EOF'
================================================
  UNINSTALL: Hermes + 9Router + Tunnel
================================================

Yang bakal dihapus:
  - systemd services: hermes, 9router, 9router-tunnel
  - npm package: 9router (global), hermes-agent (di /root/.hermes)
  - direktori: /root/.hermes, /root/.9router (config + DB!)
  - binary: /usr/local/bin/cloudflared
  - log: /var/log/9router-tunnel.log

Yang TIDAK dihapus:
  - Node.js (kalau lo masih butuh)
  - Firewall rule (UFW)
  - API key di provider (lo harus revoke manual di tiap dashboard)

EOF

if ! confirm "Lanjut uninstall?"; then
  echo "Cancelled."
  exit 0
fi

step "Stop & disable systemd services"
for svc in hermes hermes-gateway 9router-tunnel 9router; do
  if systemctl list-unit-files | grep -q "^${svc}.service"; then
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
    rm -f "/etc/systemd/system/${svc}.service"
    ok "Service $svc dihapus"
  fi
done
systemctl daemon-reload

step "Hapus binary"
rm -f /usr/local/bin/cloudflared
rm -f /usr/local/bin/hermes

step "Hapus npm + Python packages"
npm uninstall -g 9router 2>/dev/null || true
rm -rf /usr/local/lib/hermes-agent 2>/dev/null || true

if confirm "Hapus juga /root/.hermes (KONFIG + .env + secret)?"; then
  rm -rf /root/.hermes
  ok "/root/.hermes dihapus"
fi
if confirm "Hapus juga /root/.9router (DATABASE + admin password + key)?"; then
  rm -rf /root/.9router
  ok "/root/.9router dihapus"
fi

rm -f /var/log/9router-tunnel.log

ok "Uninstall selesai."
