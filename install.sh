#!/usr/bin/env bash
# install.sh - installer utama buat Hermes + 9Router (docker) + Cloudflare tunnel.
# Tested di Ubuntu 22.04, 24.04, Debian 12.
#
# Pakai:  sudo bash install.sh
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/lib.sh"

require_root

cat <<'BANNER'
========================================================
  Hermes + 9Router Installer
  9router via Docker (anti-OOM, anti-interactive-menu)
========================================================
BANNER
echo

# ---------- 1. APT base packages ----------
step "Update apt + install base packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl ca-certificates gnupg git build-essential ufw \
  python3 python3-pip jq

# ---------- 1b. Pastikan ada cukup memori (RAM + swap) ----------
# Hermes installer (uv + ~100 package Python) makan ~1GB RAM peak.
# Docker pull image 200MB, runtime 9router cuma ~150MB (no native compile).
# Total butuh minimum 3GB ramswap.
step "Cek memori (RAM + swap)"
ensure_swap_available 3072 || die "Memori terlalu kecil + disk penuh. Resize VPS atau bersihin disk."

# ---------- 1c. Stop service lama yang lagi jalan ----------
step "Stop service lama (kalo ada) biar RAM plong"
for svc in hermes-gateway hermes 9router-tunnel 9router; do
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    log "Stop $svc"
    systemctl stop "$svc" 2>/dev/null || true
  fi
done

# Kill stray processes
pkill -f '9router' 2>/dev/null || true
pkill -f 'cloudflared.*tunnel' 2>/dev/null || true
sleep 1

# ---------- 2. Firewall ----------
step "Buka port firewall (UFW): 22, 80, 443, ${NINER_PORT}"
if command -v ufw >/dev/null 2>&1; then
  ufw allow 22/tcp >/dev/null || true
  ufw allow 80/tcp >/dev/null || true
  ufw allow 443/tcp >/dev/null || true
  ufw allow ${NINER_PORT}/tcp >/dev/null || true
  if ! ufw status | grep -q "Status: active"; then
    ufw --force enable >/dev/null
  fi
  ok "UFW aktif, port udah kebuka"
else
  warn "ufw ga ada - skip firewall config"
fi

# ---------- 3. Node.js 22 ----------
# Masih dibutuhin buat: cloudflared (no), Hermes installer skill scripts (yes),
# ngeprep buat dev kalo lo mau pake CLI tool jaman now.
step "Install Node.js 22 LTS"
if command -v node >/dev/null 2>&1 && [[ "$(node -v)" =~ ^v(2[2-9]|[3-9][0-9]) ]]; then
  ok "Node.js udah ada: $(node -v)"
else
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
  ok "Node.js terinstall: $(node -v)"
fi
ok "npm: $(npm -v)"

# ============================================================================
# Install: 9router (docker), cloudflared, hermes
# ============================================================================

# 4. 9Router (docker container - langsung running di akhir script ini)
bash "$SCRIPT_DIR/scripts/setup-9router.sh"

# 5. cloudflared binary + tunnel service (BELUM di-start sampe 9router siap)
bash "$SCRIPT_DIR/scripts/setup-tunnel.sh"

# 6. Hermes Agent (uv + Python + ~100 package - ini paling berat)
bash "$SCRIPT_DIR/scripts/setup-hermes.sh"

# ============================================================================
# Start tunnel sekarang (9router udah jalan dari setup-9router.sh)
# ============================================================================

step "Verify 9router masih responsive"
if wait_for_9router 30; then
  ok "9router responsive di ${NINER_BASE}"
else
  err "9router ga nyahut. Cek: docker logs 9router"
  docker logs 9router 2>&1 | tail -20
  exit 1
fi

step "Start 9router-tunnel (cloudflared)"
systemctl reset-failed 9router-tunnel 2>/dev/null || true
systemctl restart 9router-tunnel

step "Nunggu tunnel URL kebentuk..."
source "$SCRIPT_DIR/scripts/setup-tunnel.sh"
capture_tunnel_url || warn "Tunnel URL belum keluar - coba 'systemctl restart 9router-tunnel' lagi nanti"

# ---------- 7. Summary ----------
TUNNEL_URL=""
[[ -f "$HERMES_DIR/tunnel-url.txt" ]] && TUNNEL_URL=$(cat "$HERMES_DIR/tunnel-url.txt")

cat <<EOF

================ INSTALASI SELESAI ================

  9Router (lokal)   : ${NINER_BASE}
  9Router (publik)  : ${TUNNEL_URL:-<belum tersedia, cek 'journalctl -u 9router-tunnel'>}
  9Router via       : Docker container 'decolua/9router:latest'
  Hermes config dir : $HERMES_DIR
  Hermes binary     : $(command -v hermes 2>/dev/null || echo '<not found, cek PATH>')

LANGKAH SELANJUTNYA:

  1) Buka URL publik di atas di browser.
     Set password admin saat first login. (Default INITIAL_PASSWORD: 123456)

  2) Bikin API key 9router buat Hermes:
     Dashboard -> Settings -> API Keys -> "+ New Key"
     Copy key-nya (format: sk-xxxxxxxxxxxx).

  3) Tambah provider LLM (minimal 1, recommended 2+):
     bash add-provider.sh

  4) Set Telegram bot token + 9router API key + install gateway service:
     bash configure-hermes.sh

  5) Test bot di Telegram: kirim /start ke bot lo.

STATUS / LOG:
  docker ps                                  # 9router status
  docker logs -f 9router                     # 9router log
  systemctl status 9router-tunnel hermes-gateway
  journalctl -u hermes-gateway -f

EOF
