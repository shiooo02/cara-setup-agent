# Cara Setup Agent: Hermes + 9Router (Tanpa NVIDIA)

Setup otomatis buat **Telegram agent** (Hermes) yang dapet "otak" LLM dari banyak
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
              │   ← API key 9router (config.yaml: provider=custom)
              ▼
        9Router (port 20128)
       /     │      │     \
      ▼      ▼      ▼      ▼
  OpenRouter Groq Gemini Cerebras  ← API key tiap provider
```

- **Hermes** = bot Telegram dari [Nous Research](https://github.com/NousResearch/hermes-agent),
  bisa eksekusi shell, edit file, browse web. Punya persona file (`SOUL.md`).
- **9Router** = proxy yang gabung banyak provider LLM jadi 1 endpoint.
  Punya dashboard web buat kelola API key tinggal klik-klik.
- **install.sh** = nginstall Node + 9Router + cloudflared + Hermes + systemd.
- **add-provider.sh** = nambahin provider baru ke 9Router (interaktif).
- **fix.sh** = repair install yang gagal di tengah jalan.
- **uninstall.sh** = bersih total (kill PID, hapus docker, hapus semua dir).

---

## Prasyarat

- VPS Linux (Ubuntu 22.04 / 24.04 / Debian 12), akses root atau sudo.
- RAM minimal 2GB.
- Telegram bot token dari [@BotFather](https://t.me/BotFather).
- Telegram user ID lo (chat sama [@userinfobot](https://t.me/userinfobot)).

---

## Install

### Step 1 — Clone repo (branch: stable)

```bash
git clone -b stable https://github.com/shiooo02/cara-setup-agent.git
cd cara-setup-agent
```

> Branch `stable` = versi terbaru yang udah teruji. Branch lain udah
> deprecated, bisa lo hapus (lihat [Cleanup branch lama](#cleanup-branch-lama-di-github)).

### Step 2 — Kalo VPS lo udah pernah ada install gagal, bersihin dulu

```bash
sudo DEEP_CLEAN=1 bash uninstall.sh
```

Ini bakal kill semua proses 9router/hermes/cloudflared, hapus container
docker, hapus binary global, hapus `/root/.hermes` + `/root/.9router`,
dst — bersih total.

Skip step ini kalo VPS lo masih kosong.

### Step 3 — Install fresh

```bash
sudo bash install.sh
```

Output akhir:

```
[OK] 9Router (lokal)   : http://localhost:20128
[OK] 9Router (publik)  : https://xxx-yyy.trycloudflare.com
[OK] Tunnel URL juga di /root/.hermes/tunnel-url.txt

LANGKAH SELANJUTNYA:
   1) Buka URL publik di browser, set password admin
   2) Bikin API key 9router (Settings > API Keys > New)
   3) bash add-provider.sh
   4) bash configure-hermes.sh
```

### Step 4 — Add minimal 1 provider LLM

```bash
bash add-provider.sh
```

Pilih provider yang lo punya API keynya. Recommended: **OpenRouter**
(banyak model gratis dengan format `:free` suffix). Cara dapet API key tiap
provider: lihat [docs/PROVIDERS.md](docs/PROVIDERS.md).

### Step 5 — Configure Hermes (Telegram bot)

```bash
bash configure-hermes.sh
```

Lo bakal di-prompt:
- Telegram bot token (dari @BotFather)
- Telegram user ID lo (chat sama @userinfobot)
- 9Router API key (dari dashboard 9router → Settings → API Keys → New)

Otomatis:
- Save ke `/root/.hermes/.env`
- Verify `/root/.hermes/config.yaml` udah nge-route ke 9router
- Run `hermes gateway install` (bikin systemd service)
- Start service

Test: kirim `/start` ke bot lo di Telegram. Harus respond.

> ⚠️ **Bug penting yang kebanyakan tutorial ga warning:** Default
> `config.yaml` dari Hermes installer ngarahin LLM call ke OpenRouter,
> BUKAN ke 9router. Tanpa fix ini, lo udah set semua tapi bot ga jalan
> (silent fail karena `hermes gateway install` sukses bikin service tapi
> service crash sebelum sempet nulis log). Repo ini otomatis pasang
> config.yaml yg bener (`provider: custom`, `base_url: 9router`).

---

## Personalize agent (SOUL.md)

Default-nya bot lo namanya **Mahiru**, ngomong Indonesia santai. Mau ganti
nama / gaya bicara? Edit:

```bash
nano /root/.hermes/SOUL.md
```

File ini di-load Hermes setiap kali respond, **gak perlu restart**. Contoh:

```markdown
## Siapa kamu

Nama kamu Aiko. Kamu asisten AI yang formal dan profesional.

## Cara komunikasi

- Pakai bahasa Indonesia formal.
- Selalu sebut user dengan "Anda".
- Jangan pake slang atau emoji.
```

Kosongin file ini (atau hapus) buat balik ke personality default Hermes.

---

## Cek status / log

```bash
# Status semua service
systemctl status 9router hermes-gateway 9router-tunnel

# Live log
journalctl -u 9router -f
journalctl -u hermes-gateway -f
journalctl -u 9router-tunnel -f

# URL tunnel (kalo lupa)
cat /root/.hermes/tunnel-url.txt
```

Lebih lengkap: [docs/COMMANDS.md](docs/COMMANDS.md).

---

## Kalau ada masalah

Lihat [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

| Masalah | Quick fix |
|---|---|
| Install gagal di tengah / ada bekasan | `sudo DEEP_CLEAN=1 bash uninstall.sh && sudo bash install.sh` |
| `setup-9router.sh: ... 95334 Killed` (signal 9) | OOM-killer. Tambah swap: `fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile` lalu rerun install |
| `journalctl -u hermes-gateway: -- No entries --` | Pastiin `bash configure-hermes.sh` udah dijalanin (bukan `install.sh` doang) |
| Bot ga respond | `journalctl -u hermes-gateway -n 50` |
| Bot dapet error 401 dari LLM | `cat /root/.hermes/config.yaml \| grep -E 'provider\|base_url'` — harus `custom` + `localhost:20128` |
| API key kena reject | `bash test-provider.sh <prefix>` |
| Tunnel URL ilang | `systemctl restart 9router-tunnel && sleep 8 && cat /root/.hermes/tunnel-url.txt` |
| `9router-tunnel: status=9/KILL` (restart loop) | `sudo bash fix.sh` (pasang ulang pake `--protocol http2`) |

---

## Uninstall

Bersih total — stop semua service, kill PID, hapus docker, hapus semua dir:

```bash
# Interaktif
sudo bash uninstall.sh

# Atau hapus paksa tanpa nanya
sudo DEEP_CLEAN=1 bash uninstall.sh
```

---

## Cleanup branch lama di GitHub

Repo lo punya 5 branch dari iterasi development. Tinggal pake `stable`. Hapus sisanya:

```bash
# Di laptop lo (bukan VPS), atau di VPS via gh CLI:
git push origin --delete fix-hermes-install-and-tunnel-loop
git push origin --delete v2-fixed
git push origin --delete v3-soul-and-aggressive-uninstall
git push origin --delete setup-hermes-9router-no-nvidia
```

Atau lewat web GitHub:
1. Buka https://github.com/shiooo02/cara-setup-agent/branches
2. Settings → General → Default branch → ubah ke `stable`
3. Balik ke /branches → klik tong sampah di tiap branch lain

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
├── uninstall.sh               ← bersih total (DEEP_CLEAN=1 buat skip prompt)
├── add-provider.sh            ← tambah API key provider (interaktif)
├── configure-hermes.sh        ← isi token Telegram + API key 9router + start
├── test-provider.sh           ← test provider tertentu
├── scripts/
│   ├── lib.sh                 ← helper (logging, get cli token)
│   ├── setup-9router.sh
│   ├── setup-hermes.sh        ← installer resmi Nous Research + pasang config.yaml
│   └── setup-tunnel.sh        ← cloudflared --protocol http2
├── services/
│   ├── 9router.service
│   └── 9router-tunnel.service ← Hermes pake systemd unit-nya sendiri (bikin sama 'hermes gateway install')
├── templates/
│   ├── hermes.env.template
│   ├── hermes-config.yaml.template ← provider=custom, base_url=9router
│   └── SOUL.md.template            ← persona "Mahiru" default
└── docs/
    ├── PROVIDERS.md           ← cara dapet API key tiap provider
    ├── COMMANDS.md            ← cheatsheet command
    └── TROUBLESHOOTING.md
```
