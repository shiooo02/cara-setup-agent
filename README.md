# Cara Setup Agent: Hermes + 9Router (Tanpa NVIDIA)

Setup otomatis buat Telegram agent (Hermes) yang dapet "otak" LLM dari banyak
provider gratis sekaligus, lewat satu router (9Router). Cuma butuh **2 perintah**
di VPS lo, sisanya tinggal paste API key.

> Per Mei 2026 NVIDIA NIM free tier udah gak available. Repo ini ngeganti
> NVIDIA pake kombo provider gratis: **OpenRouter, Groq, Google Gemini,
> Cerebras, Mistral**. Smart fallback bakal otomatis pindah model kalau
> salah satu kena rate-limit.

---

## Apa sih ini?

```
       Telegram (HP lo)
              │
              ▼
        Hermes (bot)
              │   ← API key 9router
              ▼
        9Router (port 20128)
       /     │      │     \
      ▼      ▼      ▼      ▼
  OpenRouter Groq Gemini Cerebras  ← API key tiap provider
```

- **Hermes** = bot Telegram yang bisa eksekusi shell, edit file, browse web.
- **9Router** = proxy yang gabung banyak provider LLM jadi 1 endpoint.
  Punya dashboard web buat kelola API key tinggal klik-klik.
- **install.sh** = nginstall Node + 9Router + Hermes + systemd + tunnel.
- **add-provider.sh** = nambahin provider baru ke 9Router (interaktif, gak perlu
  hafal URL/curl).

---

## Prasyarat

- VPS Linux (Ubuntu 22.04 / 24.04 / Debian 12), akses root atau sudo.
- RAM minimal 2GB.
- Telegram bot token dari [@BotFather](https://t.me/BotFather).
- Telegram user ID lo (chat sama [@userinfobot](https://t.me/userinfobot)).

---

## Instalasi (3 langkah)

### 1. Clone repo ini di VPS

```bash
git clone https://github.com/shiooo02/cara-setup-agent.git
cd cara-setup-agent
```

### 2. Jalanin installer

```bash
sudo bash install.sh
```

Installer bakal:
- Install Node.js 22 LTS
- Install 9Router globally (`npm i -g 9router`)
- Install cloudflared (buat tunnel publik)
- Install Hermes (Telegram bot)
- Bikin systemd service: `9router`, `hermes`, `9router-tunnel`
- Auto-start semuanya
- Print URL dashboard (cloudflare tunnel) di akhir

Di akhir installer lo bakal liat:
```
[OK] 9Router dashboard:  https://xxx-yyy.trycloudflare.com
[OK] Tunnel URL juga disimpan di:  /root/.hermes/tunnel-url.txt
[!]  LANGKAH SELANJUTNYA:
     1) Buka URL di atas di browser, set password admin
     2) Bikin API key 9router (Settings → API Keys → New)
     3) Jalanin: bash add-provider.sh
     4) Set TELEGRAM_BOT_TOKEN: bash configure-hermes.sh
```

### 3. Tambah API key provider (interaktif)

```bash
bash add-provider.sh
```

Lo bakal di-prompt:
```
Pilih provider:
  1) OpenRouter   (banyak model gratis)
  2) Groq         (paling cepet, free tier gede)
  3) Google Gemini (gemini-flash gratis)
  4) Cerebras     (Llama free, super cepet)
  5) Mistral      (free tier La Plateforme)
  6) DeepSeek     (murah banget, bukan free tapi worth)
  7) Custom OpenAI-compatible
> 1

API key OpenRouter (sk-or-v1-...): sk-or-v1-xxxxxxxx
[OK] Validasi key... valid
[OK] Provider 'OpenRouter' ditambahkan ke 9Router
[!] Tambah lagi? (y/n)
```

Ulang sebanyak provider yang lo punya (recommended minimal 2 biar fallback jalan).

Cara dapet API key tiap provider: lihat [docs/PROVIDERS.md](docs/PROVIDERS.md).

---

## Konfigurasi Hermes (Telegram bot)

```bash
bash configure-hermes.sh
```

Lo bakal di-prompt isi:
- Telegram bot token (dari @BotFather)
- Telegram owner ID (user ID lo)
- 9Router API key (dari dashboard 9router)

Otomatis di-save ke `/root/.hermes/.env`, terus jalanin `hermes gateway install`
yang bikin systemd service `hermes-gateway` + start.

Test: kirim `/start` ke bot lo di Telegram. Harus respond.

> Catatan: Hermes Agent dari Nous Research itu **Python package**, bukan npm.
> Installer resminya bikin perintah `hermes` global, dengan CLI buat manage
> gateway service-nya sendiri (`hermes gateway install/start/stop`).

---

## Cek status / log

```bash
# Status semua service
systemctl status 9router hermes-gateway 9router-tunnel

# Live log
journalctl -u 9router -f
journalctl -u hermes-gateway -f
journalctl -u 9router-tunnel -f

# URL tunnel (kalau lupa)
cat /root/.hermes/tunnel-url.txt
```

Lebih lengkap: [docs/COMMANDS.md](docs/COMMANDS.md).

---

## Kalau ada masalah

Lihat [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

Singkatnya:
| Masalah | Quick fix |
|---|---|
| Install gagal di tengah / service ga ada / restart-loop | `sudo bash fix.sh` |
| Dashboard ga keload | `systemctl restart 9router` |
| Bot ga respond | `journalctl -u hermes-gateway -n 50` cek error |
| API key kena reject | Test pake `bash test-provider.sh <prefix>` |
| Tunnel URL ilang | `systemctl restart 9router-tunnel && sleep 8 && cat /root/.hermes/tunnel-url.txt` |
| `9router-tunnel.service: status=9/KILL` (restart loop) | `sudo bash fix.sh` (pasang ulang pake `--protocol http2`) |

---

## Uninstall

```bash
sudo bash uninstall.sh
```

Bakal nanyain konfirmasi. Hapus service + file di `/root/.hermes` + `/root/.9router`.

---

## Biaya bulanan

| Item | Biaya |
|---|---|
| VPS (Tencent Lighthouse SGP / DO Basic) | $5–6 |
| 9Router | Gratis (open source) |
| Cloudflare tunnel | Gratis |
| OpenRouter free models | Gratis |
| Groq free tier | Gratis |
| Gemini free tier | Gratis |
| Telegram bot | Gratis |
| **Total** | **~$5–6/bulan** |

---

## Struktur repo

```
cara-setup-agent/
├── README.md                  ← lo lagi baca ini
├── install.sh                 ← installer utama
├── fix.sh                     ← repair install yang gagal di tengah jalan
├── add-provider.sh            ← tambah API key provider (interaktif)
├── configure-hermes.sh        ← isi token Telegram + API key 9router + install gateway
├── test-provider.sh           ← test provider tertentu
├── uninstall.sh
├── scripts/
│   ├── lib.sh                 ← helper (logging, get cli token)
│   ├── setup-9router.sh
│   ├── setup-hermes.sh        ← pake installer resmi Nous Research (Python)
│   └── setup-tunnel.sh        ← cloudflared --protocol http2 (anti restart-loop)
├── services/
│   ├── 9router.service
│   └── 9router-tunnel.service ← Hermes pake systemd unit-nya sendiri
├── templates/
│   ├── hermes.env.template
│   └── hermes-config.yaml.template
└── docs/
    ├── PROVIDERS.md           ← cara dapet API key tiap provider
    ├── COMMANDS.md            ← cheatsheet command
    └── TROUBLESHOOTING.md
```

---

## Credit

Tutorial original dari temen lo (yang ngajarin pake NVIDIA) tetap jadi basis.
Repo ini cuma:
1. Otomatisasi pake bash script
2. Ganti NVIDIA → provider gratis lain
3. Bikin add-provider interaktif (gak perlu hafal curl/JSON)
