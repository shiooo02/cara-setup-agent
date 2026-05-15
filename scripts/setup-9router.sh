#!/usr/bin/env bash
# Install 9Router. Sengaja TIDAK auto-start service di sini —
# install.sh yang ngurusin start order, biar bisa stop dulu pas
# Hermes diinstall (Hermes installer makan ~1GB RAM, kalo barengan
# 9router yg jalan bisa OOM di VPS RAM kecil).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

require_root

step "Install 9Router (npm global)"
if [[ -x "$(command -v 9router)" ]]; then
  ok "9router binary udah ada"
else
  # Pake --maxsockets=1 biar npm ga fork banyak proses (hemat RAM
  # di VPS RAM kecil). --no-audit/--no-fund hemat network round-trip.
  npm config set maxsockets 1 2>/dev/null || true
  npm install -g 9router --no-audit --no-fund
  ok "9router terinstall"
fi

# Note: Sengaja SKIP `9router --version` check di sini.
# Versi 9router 0.4.x trigger `npm install better-sqlite3` di runtime
# pas command apapun dijalanin pertama kali — itu compile native code C++
# yg makan ~1.5GB RAM. Biarin systemd yg trigger pertama kali, dengan
# MemoryMax yg udah diset di service file biar OOM-killer bunuh 9router
# (bukan bash installer ini).

step "Install systemd service: 9router"
install -m 644 "$REPO_DIR/services/9router.service" /etc/systemd/system/9router.service
systemctl daemon-reload
systemctl enable 9router >/dev/null 2>&1
ok "Service 9router terdaftar (BELUM di-start, install.sh yg ngurusin)"
