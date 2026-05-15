#!/usr/bin/env bash
# Install cloudflared + setup quick tunnel buat 9router dashboard.
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

step "Install systemd service: 9router-tunnel"
install -m 644 "$REPO_DIR/services/9router-tunnel.service" /etc/systemd/system/9router-tunnel.service
systemctl daemon-reload
# Reset failed state kalau service ini sebelumnya restart-loop
systemctl reset-failed 9router-tunnel 2>/dev/null || true
systemctl enable 9router-tunnel >/dev/null 2>&1
systemctl restart 9router-tunnel

step "Nunggu tunnel URL kebentuk..."
mkdir -p "$HERMES_DIR"
TUNNEL_URL=""
for i in {1..30}; do
  sleep 2
  # Baca dari journalctl (lebih reliable daripada file log)
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
else
  warn "Tunnel URL belum kebentuk setelah 60 detik."
  warn "Cek: journalctl -u 9router-tunnel -n 30 --no-pager"
  warn "Kalau service restart-loop, biasanya UDP port 7844 di-blokir VPS."
  warn "Service ini udah pake --protocol http2 jadi mestinya OK, tapi cek log."
fi
