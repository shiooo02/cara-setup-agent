# Cara Dapet API Key (Provider Gratis)

Per Mei 2026. Urutan dari yang **paling recommended** ke opsional.

> Tips: Tambahin minimal **2 provider** biar smart fallback di 9Router beneran
> kepake. Kalau 1 kena rate-limit, otomatis pindah ke yang lain.

---

## 1. OpenRouter (PALING RECOMMENDED)

**Kenapa:** Paling banyak model gratis (DeepSeek, Llama, Gemma, Mistral) dalam
satu API. Cukup 1 API key buat akses semua.

**Cara:**
1. Buka https://openrouter.ai
2. Sign up (Google login OK)
3. Klik avatar → **Keys**
4. **Create Key**, kasih nama bebas (misal "9router")
5. Copy key, formatnya `sk-or-v1-xxxxxxxx`
6. Di VPS jalanin `bash add-provider.sh` → pilih `1) OpenRouter` → paste key

**Model gratis populer (suffix `:free`):**
- `deepseek/deepseek-chat-v3.1:free` — best value
- `meta-llama/llama-3.3-70b-instruct:free`
- `google/gemma-3-27b-it:free`
- `qwen/qwen-2.5-72b-instruct:free`

Cek list lengkap: https://openrouter.ai/models?max_price=0

**Limit:** 50 req/hari free, 1000 req/hari kalau lo top-up minimal $10 sekali.

---

## 2. Groq (PALING CEPET)

**Kenapa:** Inference paling cepet di market (10-100x lebih cepet dari competitor).
Free tier-nya generous buat personal.

**Cara:**
1. Buka https://console.groq.com
2. Sign up
3. **API Keys** → **Create API Key**
4. Copy, formatnya `gsk_xxxxxxxx`
5. `bash add-provider.sh` → pilih `2) Groq`

**Model populer:**
- `llama-3.3-70b-versatile`
- `llama-3.1-8b-instant` — paling cepet
- `mixtral-8x7b-32768`
- `qwen-qwq-32b` — punya reasoning

**Limit:** ~30 req/menit, ~14400 req/hari (free tier).

---

## 3. Google Gemini

**Kenapa:** Gemini Flash gratis, context window 1M token, cocok buat task panjang.

**Cara:**
1. Buka https://aistudio.google.com
2. Sign in pake Google account
3. **Get API key** → **Create API key in new project**
4. Copy, formatnya `AIzaSyxxxxxxxx`
5. `bash add-provider.sh` → pilih `3) Google Gemini`

**Model populer:**
- `gemini-2.5-flash` — daily driver
- `gemini-2.5-pro` — yang paling pinter
- `gemini-2.0-flash-exp` — experimental, kadang gratis

**Limit:** 15 req/menit, 1500 req/hari (Flash).

---

## 4. Cerebras

**Kenapa:** Llama lewat custom hardware Cerebras = inference super cepet (>2000 tok/s).

**Cara:**
1. Buka https://cloud.cerebras.ai
2. Sign up
3. **API Keys** → **Create API Key**
4. Copy, formatnya `csk-xxxxxxxx`
5. `bash add-provider.sh` → pilih `4) Cerebras`

**Model populer:**
- `llama-3.3-70b`
- `llama-4-scout-17b-16e-instruct`
- `qwen-3-coder-480b` — gede banget, bagus buat coding

**Limit:** 30 req/menit, 14400 req/hari (free).

---

## 5. Mistral La Plateforme

**Kenapa:** Model Mistral langsung dari sumbernya. Free tier ada.

**Cara:**
1. Buka https://console.mistral.ai
2. Sign up + verify email
3. **API Keys** → **Create new key**
4. Copy
5. `bash add-provider.sh` → pilih `5) Mistral`

**Model populer:**
- `mistral-small-latest`
- `open-mistral-nemo`
- `codestral-latest` — buat coding

**Limit:** 1 req/detik free tier.

---

## 6. DeepSeek (BUKAN GRATIS, tapi murah)

**Kenapa:** $0.14 / 1M token input. Worth banget kalau lo butuh quality lebih dari free tier.

**Cara:**
1. Buka https://platform.deepseek.com
2. Sign up (butuh nomor HP buat verify)
3. **API Keys** → **Create**
4. Top-up minimal $2 (lewat card)
5. `bash add-provider.sh` → pilih `6) DeepSeek`

**Model:**
- `deepseek-chat` — V3, general purpose
- `deepseek-reasoner` — R1, punya thinking mode

---

## Rekomendasi setup

**Setup minimal (gratis total):**
1. OpenRouter
2. Groq

**Setup yang nyaman (gratis + 1 paid murah):**
1. OpenRouter
2. Groq
3. DeepSeek ($2 top-up = bisa pake berbulan-bulan)

**Setup paranoid (max redundancy):**
1. OpenRouter
2. Groq
3. Gemini
4. Cerebras

---

## Setelah API key kepasang

1. Buka 9Router dashboard (URL dari `cat /root/.hermes/tunnel-url.txt`)
2. Tab **Combos** → edit `free_smart_fallback`
3. **Add Model** → pilih model dari setiap provider yang lo punya
4. Urutkan dari **paling kuat & paling murah** di atas, fallback ke bawah

Contoh combo yang stabil:
```
1. groq/llama-3.3-70b-versatile           (cepet, free)
2. openrouter/deepseek/deepseek-chat-v3.1:free
3. cerebras/llama-3.3-70b                  (cadangan)
4. gemini/gemini-2.5-flash                 (cadangan terakhir)
```

Pas Hermes manggil `free_smart_fallback`, kalau Groq kena 429 → otomatis
pindah ke OpenRouter, dan seterusnya. Lo gak perlu ubah apa-apa di Hermes.
