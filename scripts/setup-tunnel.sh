#!/usr/bin/env bash
# Install cloudflared binary + register systemd service.
# Sengaja TIDAK auto-start tunnel di sini - install.sh phase 2 yg
# ngurusin start order (setelah 9router siap).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

require_root

step "Install cloudflared"
if command -v cloudflared >/dev/null 2>&1; then
  ok "cloudflared udah keinstall: $(cloudflared --version 2>&1 | head -1)"
else
  arch=$(uname -m)
  case "$arch" in
    x86_64|amd64) bin="cloudflared-linux-amd64" ;;
    aarch64|arm64) bin="cloudflared-linux-arm64" ;;
    armv7l|armhf) bin="cloudflared-linux-arm" ;;
    *) die "Arsitektur ga didukung: $arch" ;;
  esac
  curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/${bin}" \
    -o /usr/local/bin/cloudflared
  chmod +x /usr/local/bin/cloudflared
  ok "cloudflared terinstall ($bin)"
fi

step "Register systemd service: 9router-tunnel"
install -m 644 "$REPO_DIR/services/9router-tunnel.service" /etc/systemd/system/9router-tunnel.service
systemctl daemon-reload
systemctl reset-failed 9router-tunnel 2>/dev/null || true
systemctl enable 9router-tunnel >/dev/null 2>&1
ok "Service 9router-tunnel terdaftar (BELUM di-start, install.sh yg ngurusin)"

# Helper function exposed buat install.sh phase 2 — capture tunnel URL
# dari journalctl setelah service up.
capture_tunnel_url() {
  mkdir -p "$HERMES_DIR"
  local TUNNEL_URL=""
  for i in {1..30}; do
    sleep 2
    TUNNEL_URL=$(journalctl -u 9router-tunnel --since "2 min ago" --no-pager 2>/dev/null \
      | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' \
      | tail -1 || true)
    if [[ -n "$TUNNEL_URL" ]]; then
      break
    fi
  done

  if [[ -n "$TUNNEL_URL" ]]; then
    echo "$TUNNEL_URL" > "$HERMES_DIR/tunnel-url.txt"
    ok "Tunnel URL: $TUNNEL_URL"
    ok "Disimpan di: $HERMES_DIR/tunnel-url.txt"
    return 0
  else
    warn "Tunnel URL belum kebentuk setelah 60 detik."
    warn "Cek: journalctl -u 9router-tunnel -n 30 --no-pager"
    return 1
  fi
}

# Kalo dipanggil langsung (bukan dari install.sh), start service + capture
# URL. Install.sh manggil setup-tunnel.sh tanpa flag, lalu manggil
# capture_tunnel_url() sendiri di phase 2.
if [[ "${1:-}" == "--start-now" ]]; then
  step "Start 9router-tunnel"
  systemctl restart 9router-tunnel
  step "Nunggu tunnel URL kebentuk..."
  capture_tunnel_url || true
fi
