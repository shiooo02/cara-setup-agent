#!/usr/bin/env bash
# install.sh — installer utama buat Hermes + 9Router + Cloudflare tunnel.
# Tested di Ubuntu 22.04, 24.04, Debian 12.
#
# Pakai:  sudo bash install.sh
#
# Strategy: install semua binary dulu (sequential, ga ada service jalan),
# baru di akhir start service satu per satu. Ini biar VPS RAM kecil
# (1-2GB) ga ke-OOM-kill pas Hermes installer (uv install Python ~1GB)
# barengan sama 9router service yg lagi compile better-sqlite3 (~800MB).
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/lib.sh"

require_root

cat <<'BANNER'
========================================================
  Hermes + 9Router Installer
  (No NVIDIA - pakai OpenRouter / Groq / Gemini / dll)
========================================================
BANNER
echo

# ---------- 1. APT base packages ----------
step "Update apt + install base packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl ca-certificates gnupg git build-essential ufw \
  python3 python3-pip jq

# ---------- 1b. Pastikan ada cukup memori ----------
# Hermes installer (uv + pip install ~100 package Python) makan ~1GB RAM
# peak. 9router compile better-sqlite3 makan ~800MB. Kalo dijalanin
# barengan di VPS 1-2GB tanpa swap -> OOM-killer bunuh proses random.
# Minta total memory >= 4GB (RAM + swap).
step "Cek memori (RAM + swap)"
ensure_swap_available 4096 || die "Memori terlalu kecil + disk penuh. Resize VPS atau bersihin disk."

# ---------- 1c. Stop service lama yang lagi jalan ----------
# Kalo install.sh sebelumnya udah pernah jalan, mungkin 9router /
# hermes-gateway / 9router-tunnel masih running pake RAM. Stop dulu
# biar memory plong buat heavy installs.
step "Stop service yang lagi jalan (biar RAM plong)"
for svc in hermes-gateway hermes 9router-tunnel 9router; do
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    log "Stop $svc"
    systemctl stop "$svc" 2>/dev/null || true
  fi
done

# Kill stray processes juga (kalo gak ke-manage systemd)
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
# PHASE 1: Install semua binary (sequential, ga ada service running).
# Aman di RAM kecil karena cuma 1 heavy install jalan dalam satu waktu.
# ============================================================================

step "PHASE 1: Install binary"

# 4. 9Router (cuma install + register service, BELUM di-start)
bash "$SCRIPT_DIR/scripts/setup-9router.sh"

# 5. cloudflared binary
bash "$SCRIPT_DIR/scripts/setup-tunnel.sh"

# 6. Hermes (uv + Python + ~100 package - ini paling berat)
bash "$SCRIPT_DIR/scripts/setup-hermes.sh"

# ============================================================================
# PHASE 2: Start service satu per satu.
# 9router pertama kali start bakal compile better-sqlite3 (1-3 menit,
# ~800MB peak). Tunggu sampe selesai dulu sebelum start tunnel.
# ============================================================================

step "PHASE 2: Start 9router (first start = compile better-sqlite3, 1-3 menit)"
systemctl reset-failed 9router 2>/dev/null || true
systemctl restart 9router

log "Nunggu 9router ready di port ${NINER_PORT} (timeout 5 menit)..."
if wait_for_9router 300; then
  ok "9router up & running di ${NINER_BASE}"
else
  err "9router belum nyahut setelah 5 menit."
  echo
  echo "----- LOG 9ROUTER -----"
  journalctl -u 9router -n 30 --no-pager 2>/dev/null || true
  echo
  warn "Kalo ada 'Killed' di log = OOM. Cek 'free -h':"
  echo "    free -h"
  echo
  warn "Kalo total RAM+swap < 4GB, install swap lebih gede:"
  echo "    swapoff /swapfile; rm /swapfile"
  echo "    fallocate -l 6G /swapfile && chmod 600 /swapfile"
  echo "    mkswap /swapfile && swapon /swapfile"
  echo "    sudo bash install.sh    # rerun"
  exit 1
fi

step "Start 9router-tunnel (cloudflared)"
systemctl reset-failed 9router-tunnel 2>/dev/null || true
systemctl restart 9router-tunnel

step "Nunggu tunnel URL kebentuk..."
# Source setup-tunnel.sh buat dapet capture_tunnel_url() function
source "$SCRIPT_DIR/scripts/setup-tunnel.sh"
capture_tunnel_url || warn "Tunnel URL belum keluar — coba 'systemctl restart 9router-tunnel' lagi nanti"

# ---------- 7. Summary ----------
TUNNEL_URL=""
[[ -f "$HERMES_DIR/tunnel-url.txt" ]] && TUNNEL_URL=$(cat "$HERMES_DIR/tunnel-url.txt")

cat <<EOF

${C_GREEN}================ INSTALASI SELESAI ================${C_RESET}

  9Router (lokal)   : ${NINER_BASE}
  9Router (publik)  : ${TUNNEL_URL:-<belum tersedia, cek 'journalctl -u 9router-tunnel'>}
  Hermes config dir : $HERMES_DIR
  Hermes binary     : $(command -v hermes 2>/dev/null || echo '<not found, cek PATH>')

${C_BOLD}LANGKAH SELANJUTNYA:${C_RESET}

  1) Buka URL publik di atas di browser.
     Set password admin saat first login.

  2) Bikin API key 9router buat Hermes:
     Dashboard -> Settings -> API Keys -> "+ New Key"
     Copy key-nya (format: sk-xxxxxxxxxxxx).

  3) Tambah provider LLM (minimal 1, recommended 2+):
     ${C_BOLD}bash add-provider.sh${C_RESET}

  4) Set Telegram bot token + 9router API key + install gateway service:
     ${C_BOLD}bash configure-hermes.sh${C_RESET}

  5) Test bot di Telegram: kirim /start ke bot lo.

${C_BOLD}STATUS / LOG:${C_RESET}
  systemctl status 9router 9router-tunnel hermes-gateway
  journalctl -u hermes-gateway -f

EOF
