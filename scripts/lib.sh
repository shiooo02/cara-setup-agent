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
