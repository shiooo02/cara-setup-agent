#!/usr/bin/env bash
# add-provider.sh — interaktif: pilih provider, paste API key, beres.
# Otomatis bikin "provider node" + "connection" di 9Router via API.
#
# Pakai:  bash add-provider.sh
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/lib.sh"

# ---------- Provider preset ----------
# Format: NAME|PREFIX|BASE_URL|TEST_MODEL|API_KEY_HINT
PROVIDERS=(
  "OpenRouter|openrouter|https://openrouter.ai/api/v1|deepseek/deepseek-chat-v3.1:free|sk-or-v1-..."
  "Groq|groq|https://api.groq.com/openai/v1|llama-3.3-70b-versatile|gsk_..."
  "Google Gemini|gemini|https://generativelanguage.googleapis.com/v1beta/openai|gemini-2.5-flash|AIza..."
  "Cerebras|cerebras|https://api.cerebras.ai/v1|llama-3.3-70b|csk-..."
  "Mistral|mistral|https://api.mistral.ai/v1|mistral-small-latest|..."
  "DeepSeek|deepseek|https://api.deepseek.com/v1|deepseek-chat|sk-..."
  "Custom OpenAI-compatible|||||"
)

print_menu() {
  echo
  echo "${C_BOLD}Pilih provider yang mau ditambahin:${C_RESET}"
  local i=1
  for p in "${PROVIDERS[@]}"; do
    IFS='|' read -r name prefix _ _ _ <<< "$p"
    if [[ -n "$prefix" ]]; then
      printf "  %d) %-25s (prefix: %s)\n" "$i" "$name" "$prefix"
    else
      printf "  %d) %s\n" "$i" "$name"
    fi
    ((i++))
  done
  echo "  q) Keluar"
}

# ---------- Cek 9router up dulu ----------
step "Cek 9Router"
if ! wait_for_9router 5; then
  die "9Router ga jalan di ${NINER_BASE}. Coba: systemctl restart 9router"
fi
ok "9Router responsive"

# ---------- Loop tambah provider ----------
while true; do
  print_menu
  choice=$(ask "Pilihan (1-${#PROVIDERS[@]} atau q)")

  if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
    break
  fi
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#PROVIDERS[@]} )); then
    warn "Pilihan ga valid"
    continue
  fi

  IFS='|' read -r NAME PREFIX BASE_URL TEST_MODEL HINT <<< "${PROVIDERS[$((choice-1))]}"

  # Custom — minta semua input manual
  if [[ -z "$PREFIX" ]]; then
    NAME=$(ask "Nama provider (bebas, contoh: 'My LLM')")
    PREFIX=$(ask "Prefix (huruf kecil, no spasi, contoh: 'mylm')")
    BASE_URL=$(ask "Base URL (contoh: https://api.example.com/v1)")
    TEST_MODEL=$(ask "Model ID buat test (contoh: gpt-4)")
    HINT="..."
  fi

  echo
  log "Provider:  $NAME"
  log "Prefix:    $PREFIX"
  log "Base URL:  $BASE_URL"

  # API key
  echo
  echo "Cara dapet API key: lihat docs/PROVIDERS.md"
  echo "Format key biasanya: $HINT"
  API_KEY=$(ask_secret "Paste API key")
  if [[ -z "$API_KEY" ]]; then
    warn "API key kosong, skip."
    continue
  fi

  # ---------- Validate key ----------
  step "Validasi API key ke ${NAME}..."
  validate_body=$(jq -nc \
    --arg url "$BASE_URL" \
    --arg key "$API_KEY" \
    --arg model "$TEST_MODEL" \
    '{baseUrl:$url, apiKey:$key, type:"openai-compatible", modelId:$model}')

  vresp=$(niner_api POST /api/provider-nodes/validate "$validate_body" || echo '{}')
  valid=$(echo "$vresp" | jq -r '.valid // false' 2>/dev/null || echo "false")

  if [[ "$valid" != "true" ]]; then
    warn "Validasi gagal. Response: $vresp"
    if ! confirm "Tetep lanjut bikin provider node? (kalau yakin keynya bener)"; then
      continue
    fi
  else
    ok "API key valid"
  fi

  # ---------- Bikin provider node ----------
  step "Bikin provider node di 9Router"
  node_body=$(jq -nc \
    --arg name "$NAME" \
    --arg prefix "$PREFIX" \
    --arg url "$BASE_URL" \
    '{type:"openai-compatible", apiType:"chat", name:$name, prefix:$prefix, baseUrl:$url}')

  nresp=$(niner_api POST /api/provider-nodes "$node_body")
  node_id=$(echo "$nresp" | jq -r '.node.id // .id // empty' 2>/dev/null)

  if [[ -z "$node_id" ]]; then
    # Mungkin udah ada — coba cari existing
    existing=$(niner_api GET /api/provider-nodes 2>/dev/null || echo '[]')
    node_id=$(echo "$existing" | jq -r --arg p "$PREFIX" \
      '.[] | select(.prefix==$p) | .id' 2>/dev/null | head -1)
    if [[ -z "$node_id" ]]; then
      err "Gagal bikin provider node. Response: $nresp"
      continue
    fi
    warn "Provider node udah exist (prefix=$PREFIX), reuse node_id=$node_id"
  else
    ok "Provider node dibuat: $node_id"
  fi

  # ---------- Bikin connection (attach API key) ----------
  step "Attach API key ke provider node"
  conn_body=$(jq -nc \
    --arg provider "$node_id" \
    --arg key "$API_KEY" \
    --arg name "$NAME" \
    '{provider:$provider, apiKey:$key, name:$name}')

  cresp=$(niner_api POST /api/providers "$conn_body")
  conn_id=$(echo "$cresp" | jq -r '.id // .connection.id // empty' 2>/dev/null)

  if [[ -n "$conn_id" ]]; then
    ok "Connection dibuat: $conn_id"
  else
    warn "Connection response: $cresp"
    warn "Coba cek manual di dashboard apakah keynya udah masuk."
  fi

  echo
  ok "${C_BOLD}Selesai tambah ${NAME}!${C_RESET}"
  echo "   Model bisa dipanggil pake prefix: ${PREFIX}/<model-id>"
  echo "   Contoh: ${PREFIX}/${TEST_MODEL}"
  echo

  if ! confirm "Tambah provider lain?"; then
    break
  fi
done

# ---------- Final tip ----------
cat <<EOF

${C_BOLD}NEXT STEP:${C_RESET}

  - Dashboard: $(cat "$HERMES_DIR/tunnel-url.txt" 2>/dev/null || echo "$NINER_BASE")
  - Buka tab ${C_BOLD}Combos${C_RESET} → edit ${C_BOLD}free_smart_fallback${C_RESET}
    → Add Model → pilih model dari provider yang baru lo tambahin.
  - Atau panggil model langsung pake prefix di Telegram:
      /model <prefix>/<model-id>

  Test provider:
    ${C_BOLD}bash test-provider.sh <prefix>${C_RESET}

EOF
