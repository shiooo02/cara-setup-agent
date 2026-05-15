#!/usr/bin/env bash
# Shared helper functions buat semua script di repo ini.
# Source dengan: source "$(dirname "$0")/scripts/lib.sh"

set -uo pipefail

# ---------- Logging (warna biar enak dibaca) ----------
if [[ -t 1 ]]; then
  C_RESET='\033[0m'
  C_RED='\033[0;31m'
  C_GREEN='\033[0;32m'
  C_YELLOW='\033[0;33m'
  C_BLUE='\033[0;34m'
  C_BOLD='\033[1m'
else
  C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_BOLD=''
fi

log()   { printf "${C_BLUE}[..]${C_RESET} %s\n" "$*"; }
ok()    { printf "${C_GREEN}[OK]${C_RESET} %s\n" "$*"; }
warn()  { printf "${C_YELLOW}[!]${C_RESET}  %s\n" "$*"; }
err()   { printf "${C_RED}[ERR]${C_RESET} %s\n" "$*" >&2; }
die()   { err "$*"; exit 1; }
step()  { printf "\n${C_BOLD}==>${C_RESET} ${C_BOLD}%s${C_RESET}\n" "$*"; }

# ---------- Common paths ----------
HERMES_DIR="${HERMES_DIR:-/root/.hermes}"
NINER_DIR="${NINER_DIR:-/root/.9router}"
NINER_PORT="${NINER_PORT:-20128}"
NINER_BASE="http://localhost:${NINER_PORT}"

# ---------- Permission check ----------
require_root() {
  if [[ $EUID -ne 0 ]]; then
    die "Script ini harus dijalanin sebagai root. Pakai: sudo bash $0"
  fi
}

# ---------- 9Router CLI token ----------
# Token deterministic dari machine ID, sama persis cara di tutorial original.
get_9router_cli_token() {
  if ! command -v node >/dev/null 2>&1; then
    die "Node.js belum keinstall. Jalanin install.sh dulu."
  fi

  # node-machine-id otomatis ke-bundle sama 9router (global install).
  # Kalau ga ada, install on-the-fly di tmp dir.
  local node_path
  node_path=$(npm root -g 2>/dev/null)
  if [[ -z "$node_path" ]] || [[ ! -d "$node_path/node-machine-id" ]]; then
    # Install di /tmp biar gak ngotorin global
    local tmp_modules="/tmp/.9r-cli-helper"
    mkdir -p "$tmp_modules"
    if [[ ! -d "$tmp_modules/node_modules/node-machine-id" ]]; then
      (cd "$tmp_modules" && npm install --silent --no-audit --no-fund \
        --prefix . node-machine-id >/dev/null 2>&1) || \
        die "Gagal install node-machine-id buat dapet CLI token"
    fi
    node_path="$tmp_modules/node_modules"
  fi

  NODE_PATH="$node_path" node -e '
const crypto = require("crypto");
const {machineIdSync} = require("node-machine-id");
const t = crypto.createHash("sha256")
  .update(machineIdSync() + "9r-cli-auth")
  .digest("hex").substring(0, 16);
process.stdout.write(t);
'
}

# ---------- 9Router API helper ----------
# Usage: niner_api METHOD PATH [JSON_BODY]
niner_api() {
  local method="$1" path="$2" body="${3:-}"
  local token
  token=$(get_9router_cli_token) || die "Gak bisa generate CLI token"

  if [[ -n "$body" ]]; then
    curl -sS -X "$method" "${NINER_BASE}${path}" \
      -H "x-9r-cli-token: $token" \
      -H "Content-Type: application/json" \
      -d "$body"
  else
    curl -sS -X "$method" "${NINER_BASE}${path}" \
      -H "x-9r-cli-token: $token"
  fi
}

# ---------- Wait sampai 9router siap ----------
wait_for_9router() {
  local max="${1:-30}"
  local i=0
  while (( i < max )); do
    if curl -fsS -m 2 "${NINER_BASE}/api/health" >/dev/null 2>&1 || \
       curl -fsS -m 2 "${NINER_BASE}/" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    ((i++))
  done
  return 1
}

# ---------- Cek file env, bikin kalau ga ada ----------
ensure_hermes_env() {
  mkdir -p "$HERMES_DIR"
  if [[ ! -f "$HERMES_DIR/.env" ]]; then
    touch "$HERMES_DIR/.env"
    chmod 600 "$HERMES_DIR/.env"
  fi
}

# Set/replace KEY=VALUE di file .env
# Pake awk biar value bebas karakter (& : / | dll) tanpa khawatir escape sed.
set_env_var() {
  local file="$1" key="$2" value="$3"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    local tmp
    tmp=$(mktemp)
    awk -v k="$key" -v v="$value" '
      BEGIN { done = 0 }
      $0 ~ "^"k"=" {
        if (!done) { print k"="v; done = 1 }
        next
      }
      { print }
      END { if (!done) print k"="v }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
  else
    echo "${key}=${value}" >> "$file"
  fi
  chmod 600 "$file"
}

# ---------- Prompt helper ----------
ask() {
  local prompt="$1" default="${2:-}" answer
  if [[ -n "$default" ]]; then
    read -rp "$prompt [$default]: " answer
    echo "${answer:-$default}"
  else
    read -rp "$prompt: " answer
    echo "$answer"
  fi
}

ask_secret() {
  local prompt="$1" answer
  read -rsp "$prompt: " answer
  echo >&2
  echo "$answer"
}

confirm() {
  local prompt="$1" answer
  read -rp "$prompt (y/n): " answer
  [[ "$answer" =~ ^[Yy] ]]
}

# ---------- Memory / swap helper ----------
# Cek total RAM (MB). Output cuma angka.
get_total_mem_mb() {
  awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo
}

# Cek total swap aktif (MB).
get_total_swap_mb() {
  awk '/SwapTotal/ {print int($2/1024)}' /proc/meminfo
}

# Pastiin total (RAM + swap) >= MIN_MB. Kalo kurang, bikin swapfile.
# Kepake biar `npm install better-sqlite3` (native C++ compile, ~1.5GB peak)
# pas 9router pertama kali start ga ke-OOM-kill di VPS RAM-rendah.
ensure_swap_available() {
  local need_mb="${1:-4096}"  # default minimum total memory: 4GB
  local ram swap total deficit
  ram=$(get_total_mem_mb)
  swap=$(get_total_swap_mb)
  total=$(( ram + swap ))

  log "RAM: ${ram} MB, swap: ${swap} MB, total: ${total} MB (need: ${need_mb} MB)"

  if (( total >= need_mb )); then
    ok "Memori cukup, ga butuh swap tambahan"
    return 0
  fi

  deficit=$(( need_mb - total ))
  # Bulatin ke 1024 MB terdekat di atas deficit, minimum 4096 (4GB).
  # Sengaja besar biar kalo install bareng (hermes uv + 9router compile)
  # kena 2GB peak masing-masing, ga ke-OOM.
  local swap_size_mb=4096
  while (( swap_size_mb < deficit + 1024 )); do
    swap_size_mb=$(( swap_size_mb + 1024 ))
  done

  warn "Memori kurang ${deficit} MB. Bikin swapfile ${swap_size_mb} MB di /swapfile..."

  if [[ -f /swapfile ]]; then
    log "/swapfile udah ada — coba aktifin"
    swapon /swapfile 2>/dev/null || true
    if (( $(get_total_swap_mb) >= swap )); then
      ok "Swap udah aktif: $(get_total_swap_mb) MB"
      return 0
    fi
  fi

  # Cek disk space dulu — paling enggak swap_size + 500MB free
  local free_mb
  free_mb=$(df -m / | awk 'NR==2 {print $4}')
  if (( free_mb < swap_size_mb + 500 )); then
    err "Disk free cuma ${free_mb} MB, butuh minimum $((swap_size_mb + 500)) MB."
    err "Hapus file gede dulu atau resize disk VPS."
    return 1
  fi

  # fallocate paling cepet (di ext4/xfs). Fallback ke dd kalo gagal.
  if ! fallocate -l "${swap_size_mb}M" /swapfile 2>/dev/null; then
    log "fallocate gagal, pake dd (lebih lambat)"
    dd if=/dev/zero of=/swapfile bs=1M count="$swap_size_mb" status=progress
  fi

  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile

  # Persist ke /etc/fstab biar tetep ada setelah reboot
  if ! grep -q '^/swapfile' /etc/fstab 2>/dev/null; then
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    ok "Swap auto-mount on boot ditambahin ke /etc/fstab"
  fi

  ok "Swap aktif: $(get_total_swap_mb) MB total"
}
