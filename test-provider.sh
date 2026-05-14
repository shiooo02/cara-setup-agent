#!/usr/bin/env bash
# test-provider.sh — test apakah provider tertentu di 9Router berfungsi.
#
# Pakai:  bash test-provider.sh <prefix> [model-id]
# Contoh: bash test-provider.sh openrouter
#         bash test-provider.sh groq llama-3.3-70b-versatile
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/lib.sh"

PREFIX="${1:-}"
MODEL="${2:-}"

if [[ -z "$PREFIX" ]]; then
  err "Usage: bash test-provider.sh <prefix> [model-id]"
  echo
  echo "Provider yang terdaftar di 9Router:"
  niner_api GET /api/provider-nodes 2>/dev/null \
    | jq -r '.[] | "  - \(.prefix)\t(\(.name))"' 2>/dev/null \
    || echo "  (gagal ambil list — cek 9router up)"
  exit 1
fi

# Default test models per prefix
declare -A DEFAULT_MODELS=(
  [openrouter]="deepseek/deepseek-chat-v3.1:free"
  [groq]="llama-3.3-70b-versatile"
  [gemini]="gemini-2.5-flash"
  [cerebras]="llama-3.3-70b"
  [mistral]="mistral-small-latest"
  [deepseek]="deepseek-chat"
)
[[ -z "$MODEL" ]] && MODEL="${DEFAULT_MODELS[$PREFIX]:-}"
if [[ -z "$MODEL" ]]; then
  die "Model ID kosong. Specify pake: bash test-provider.sh $PREFIX <model-id>"
fi

# Ambil 9router API key dari .env (kalau ada)
NINE_KEY=""
if [[ -f "$HERMES_DIR/.env" ]]; then
  NINE_KEY=$(grep '^OPENAI_API_KEY=' "$HERMES_DIR/.env" | cut -d'=' -f2- | head -1)
fi

if [[ -z "$NINE_KEY" ]]; then
  NINE_KEY=$(ask_secret "9Router API key (dari dashboard)")
fi

step "Test ${PREFIX}/${MODEL}"
echo "Endpoint: ${NINER_BASE}/v1/chat/completions"
echo "Model:    ${PREFIX}/${MODEL}"
echo

resp=$(curl -sS -X POST "${NINER_BASE}/v1/chat/completions" \
  -H "Authorization: Bearer ${NINE_KEY}" \
  -H "Content-Type: application/json" \
  -d "$(jq -nc --arg m "${PREFIX}/${MODEL}" \
    '{model:$m, messages:[{role:"user",content:"ping (reply 1 word)"}], max_tokens:20}')")

echo "Response:"
echo "$resp" | jq . 2>/dev/null || echo "$resp"
echo

content=$(echo "$resp" | jq -r '.choices[0].message.content // empty' 2>/dev/null || true)
if [[ -n "$content" ]]; then
  ok "Provider WORKING. Reply: $content"
else
  err "Ga dapet response valid. Cek error di atas."
fi
