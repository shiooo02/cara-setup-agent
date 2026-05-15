#!/usr/bin/env bash
# install.sh — installer utama buat Hermes + 9Router + Cloudflare tunnel.
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
  (No NVIDIA — pakai OpenRouter / Groq / Gemini / dll)
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
# 9router pertama kali start ngerun `npm install better-sqlite3` di
# /root/.9router/runtime yang kompilasi native code C++ (~1.5GB peak).
# VPS RAM 1GB tanpa swap dijamin ke-OOM-kill (signal 9). Bikin swap dulu.
step "Cek memori (RAM + swap)"
ensure_swap_available 3072 || die "Bisa-bisa OOM. Tambah RAM atau bersihin disk dulu."

# ---------- 2. Firewall ----------
step "Buka port firewall (UFW): 22, 80, 443, ${NINER_PORT}"
if command -v ufw >/dev/null 2>&1; then
  ufw allow 22/tcp >/dev/null || true
  ufw allow 80/tcp >/dev/null || true
  ufw allow 443/tcp >/dev/null || true
  ufw allow ${NINER_PORT}/tcp >/dev/null || true
  # Aktifkan ufw kalau belum aktif (force, biar gak interaktif)
  if ! ufw status | grep -q "Status: active"; then
    ufw --force enable >/dev/null
  fi
  ok "UFW aktif, port udah kebuka"
else
  warn "ufw ga ada — skip firewall config"
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

# ---------- 4. 9Router ----------
bash "$SCRIPT_DIR/scripts/setup-9router.sh"

# ---------- 5. Cloudflare tunnel ----------
bash "$SCRIPT_DIR/scripts/setup-tunnel.sh"

# ---------- 6. Hermes ----------
bash "$SCRIPT_DIR/scripts/setup-hermes.sh"

# ---------- 7. Summary ----------
TUNNEL_URL=""
[[ -f "$HERMES_DIR/tunnel-url.txt" ]] && TUNNEL_URL=$(cat "$HERMES_DIR/tunnel-url.txt")

cat <<EOF

${C_GREEN}================ INSTALASI SELESAI ================${C_RESET}

  9Router (lokal)   : ${NINER_BASE}
  9Router (publik)  : ${TUNNEL_URL:-<belum tersedia, cek log tunnel>}
  Hermes config dir : $HERMES_DIR
  Tunnel log        : /var/log/9router-tunnel.log

${C_BOLD}LANGKAH SELANJUTNYA:${C_RESET}

  1) Buka URL publik di atas di browser.
     Set password admin saat first login.

  2) Bikin API key 9router buat Hermes:
     Dashboard → Settings → API Keys → "+ New Key"
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
