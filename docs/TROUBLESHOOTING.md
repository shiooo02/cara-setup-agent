# Troubleshooting

Masalah-masalah umum + cara fix-nya.

> **TL;DR**: kalau install gagal di tengah jalan, langsung jalanin
> `sudo bash fix.sh` — itu yang paling sering nyelametin.

---

## Quick recovery

### Install gagal di tengah / ada service yang missing

Tanda-tandanya:
- `Failed to start hermes.service: Unit hermes.service not found`
- `9router-tunnel.service: Main process exited, code=killed, status=9/KILL`
- `cat: /root/.hermes/tunnel-url.txt: No such file or directory`
- restart counter ratusan kali (`restart counter is at 738`)

```bash
sudo bash fix.sh
```

`fix.sh` bakal:
1. Hapus systemd unit lama yang restart-loop / typo
2. Pasang ulang `9router-tunnel.service` versi baru (pake `--protocol http2`,
   anti UDP block)
3. Install Hermes pake **installer resmi Nous Research** (Python, bukan npm)
4. Bikin `tunnel-url.txt` lagi

Aman dijalanin walaupun install.sh udah selesai — idempotent.

---

## 9Router

### Dashboard ga ke-load di browser

```bash
systemctl status 9router
ss -tlnp | grep 20128
```

**Fix:**
- Service mati? `systemctl restart 9router`
- Port ga listening? `journalctl -u 9router -n 100`
- Firewall blokir? `ufw allow 20128/tcp`

### Tunnel URL ga muncul / cloudflared restart-loop

Gejala:
```
9router-tunnel.service: Main process exited, code=killed, status=9/KILL
restart counter is at 738.
```

**Penyebab paling umum**: VPS lo blokir UDP port 7844 (yang dipake QUIC).
Cloudflared coba pake QUIC dulu, gagal, di-kill, di-restart, gagal lagi → loop.

**Fix:**
```bash
sudo bash fix.sh
```

Atau manual:
```bash
# Edit unit file
sudo systemctl edit --full 9router-tunnel
# Ganti baris ExecStart, tambahin --protocol http2:
#   ExecStart=/usr/local/bin/cloudflared tunnel --url http://localhost:20128 \
#             --protocol http2 --no-autoupdate

sudo systemctl reset-failed 9router-tunnel
sudo systemctl daemon-reload
sudo systemctl restart 9router-tunnel
sleep 8
journalctl -u 9router-tunnel -n 30 --no-pager | grep trycloudflare.com
```

### Cek tunnel URL secara manual

```bash
journalctl -u 9router-tunnel --since "5 min ago" --no-pager \
  | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1
```

### Lupa password admin 9Router

```bash
cp /root/.9router/db.json /root/.9router/db.json.bak
nano /root/.9router/db.json
# (cari user object → set password kosong → restart)
systemctl restart 9router
# Buka dashboard → bakal minta set password lagi
```

---

## Provider / API key

### "API key unauthorized" pas validasi

1. Test API key langsung (bypass 9router):
   ```bash
   # OpenRouter
   curl https://openrouter.ai/api/v1/models -H "Authorization: Bearer sk-or-v1-..."
   # Groq
   curl https://api.groq.com/openai/v1/models -H "Authorization: Bearer gsk_..."
   # Gemini
   curl "https://generativelanguage.googleapis.com/v1beta/openai/models" \
     -H "Authorization: Bearer AIza..."
   ```
2. Kalau curl direct OK tapi 9router reject → restart 9router.
3. Kalau curl direct juga gagal → key salah / dirotasi.

### Validasi pass tapi chat completion 401

Biasanya base URL salah. Pastikan format:
- OpenRouter: `https://openrouter.ai/api/v1`
- Groq: `https://api.groq.com/openai/v1`
- Gemini: `https://generativelanguage.googleapis.com/v1beta/openai`
- Mistral: `https://api.mistral.ai/v1`

### 429 Rate Limit terus

Smart fallback otomatis switch ke model berikutnya — tapi kalau **semua**
provider kena, opsi:
1. Tunggu reset (per menit/jam/hari, beda-beda).
2. Tambah provider lain via `bash add-provider.sh`.

---

## Hermes (Telegram bot)

> **Catatan**: Hermes Agent itu Python (Nous Research). Service systemd-nya
> dibikin sama `hermes gateway install` — namanya `hermes-gateway`, bukan
> `hermes`. Kalau lo liat tutorial yang nyebut `hermes.service`, itu udah
> outdated.

### Bot ga respond di Telegram

```bash
# 1. Cek service
systemctl status hermes-gateway

# 2. Cek log
journalctl -u hermes-gateway -n 50 --no-pager
```

### `Unit hermes.service not found`

Service name-nya `hermes-gateway`, bukan `hermes`. Atau Hermes belum keinstall
sama sekali. Jalanin:
```bash
sudo bash fix.sh
bash configure-hermes.sh
```

### `command not found: hermes`

Installer Nous Research naro `hermes` di `/usr/local/bin/hermes`. Cek:
```bash
ls -la /usr/local/bin/hermes
which hermes
```

Kalau ga ada, `fix.sh` bakal install ulang.

### `Conflict: terminated by other getUpdates request`

Token Telegram lo dipake di tempat lain (atau ada 2 instance jalan).
```bash
systemctl stop hermes-gateway
ps aux | grep hermes
# kill manual kalau ada zombie
systemctl start hermes-gateway
```

### `ECONNREFUSED 127.0.0.1:20128`

9Router belum jalan.
```bash
systemctl restart 9router
sleep 3
systemctl restart hermes-gateway
```

### Bot respond, tapi "model not found"

Combo `free_smart_fallback` belum ada modelnya.
1. Buka dashboard 9router (`cat /root/.hermes/tunnel-url.txt`)
2. Tab **Combos** → `free_smart_fallback` → Add Model
3. Tambahin minimal 1 model dari provider yang lo punya

### Bot respond ke orang lain (security!)

```bash
grep TELEGRAM_ALLOWED_USERS /root/.hermes/.env
grep TELEGRAM_OWNER_ID /root/.hermes/.env
```

Pastikan ID lo benar (chat sama @userinfobot di Telegram).
Kalau salah:
```bash
bash configure-hermes.sh
```

---

## VPS / sistem

### Disk penuh

```bash
df -h
du -sh /var/log /root/.hermes /root/.9router
journalctl --vacuum-time=7d
apt-get clean
```

### Memory pressure

```bash
free -h
# Tambah swap kalau perlu:
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

### Service crash terus (Restart=always loop)

```bash
systemctl status <service-name>
journalctl -u <service-name> -n 100 --no-pager

# Stop temporary biar gak ngeloop sambil debug
systemctl stop <service-name>
systemctl reset-failed <service-name>
```

---

## Named Tunnel (URL permanen)

Quick tunnel URL-nya berubah tiap restart. Kalau capek, pake named tunnel.
Butuh akun Cloudflare + domain.

```bash
cloudflared tunnel login
cloudflared tunnel create 9router-prod
cloudflared tunnel route dns 9router-prod 9router.yourdomain.com

mkdir -p /etc/cloudflared
cat > /etc/cloudflared/config.yml <<EOF
tunnel: 9router-prod
credentials-file: /root/.cloudflared/<TUNNEL_ID>.json

ingress:
  - hostname: 9router.yourdomain.com
    service: http://localhost:20128
  - service: http_status:404
EOF

# Ganti quick tunnel dengan named tunnel
systemctl stop 9router-tunnel
systemctl disable 9router-tunnel

cloudflared service install
systemctl restart cloudflared
systemctl enable cloudflared
```

---

## Reset total (nuklir)

```bash
sudo bash uninstall.sh
# konfirmasi semua y

cd ~/cara-setup-agent
git pull
sudo bash install.sh
```

API key di provider tetap aman — gak ke-revoke. Tinggal paste lagi di
`bash add-provider.sh`.
