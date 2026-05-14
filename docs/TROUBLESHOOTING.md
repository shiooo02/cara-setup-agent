# Troubleshooting

Masalah-masalah umum + cara fix-nya. Kalau ada yang gak ke-cover, kasih issue
di repo atau cek `journalctl -u <service> -f` dulu.

---

## 9Router

### Dashboard ga ke-load di browser

**Cek:**
```bash
systemctl status 9router
ss -tlnp | grep 20128
```

**Fix:**
- Service mati? `systemctl restart 9router`
- Port ga listening? Cek log: `journalctl -u 9router -n 100`
- Firewall blokir? `ufw allow 20128/tcp` (kalau lo akses lewat IP, bukan tunnel)

### Tunnel URL ga muncul / 404

```bash
# Cek service
systemctl status 9router-tunnel

# Cek log
tail -50 /var/log/9router-tunnel.log

# Restart + tunggu URL baru
systemctl restart 9router-tunnel
sleep 8
grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' /var/log/9router-tunnel.log | tail -1
```

Kalau berkali-kali gagal, mungkin Cloudflare quick tunnel lagi rate-limit.
Tunggu 5–10 menit, atau pakai **named tunnel** (perlu Cloudflare account +
domain) — lihat bagian [Named Tunnel](#named-tunnel) di bawah.

### Lupa password admin 9Router

```bash
# Hapus DB user (HATI-HATI: provider config tetap aman, cuma user yg di-reset)
ls /root/.9router/
# Cari file db.json atau auth.json — backup dulu
cp /root/.9router/db.json /root/.9router/db.json.bak

# Edit / hapus user yang ada
# (cara persisnya tergantung versi 9router; check struct file dulu)
nano /root/.9router/db.json

# Restart
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
2. Kalau curl direct OK tapi 9router reject → restart 9router
   (`systemctl restart 9router`).
3. Kalau curl direct juga gagal → key salah / dirotasi / belum approved.

### Validasi pass tapi chat completion 401

Biasanya base URL salah. Pastikan format:
- OpenRouter: `https://openrouter.ai/api/v1` (TANPA trailing slash)
- Groq: `https://api.groq.com/openai/v1`
- Gemini: `https://generativelanguage.googleapis.com/v1beta/openai`
- Mistral: `https://api.mistral.ai/v1`

### 429 Rate Limit terus

Smart fallback otomatis switch ke model berikutnya — tapi kalau **semua**
provider kena, cuma ada 2 opsi:
1. Tunggu reset (biasanya per menit/jam/hari).
2. Tambah provider lain via `bash add-provider.sh`.

---

## Hermes (Telegram bot)

### Bot ga respond di Telegram

```bash
# 1. Cek service
systemctl status hermes

# 2. Cek log
journalctl -u hermes -n 50 --no-pager
```

**Error patterns yang umum:**

#### `TELEGRAM_BOT_TOKEN missing`
```bash
bash configure-hermes.sh
```

#### `Conflict: terminated by other getUpdates request`
Token Telegram lo dipake di tempat lain (atau ada 2 instance hermes jalan).
```bash
systemctl stop hermes
ps aux | grep hermes
# kill manual kalau ada zombie
systemctl start hermes
```

#### `ECONNREFUSED 127.0.0.1:20128`
9Router belum jalan.
```bash
systemctl restart 9router
sleep 3
systemctl restart hermes
```

#### `401 Unauthorized` saat panggil 9router
9router API key di Hermes salah/expired.
```bash
# Generate key baru di dashboard, terus:
bash configure-hermes.sh
```

#### Bot respond, tapi "model not found"
Combo `free_smart_fallback` belum ada modelnya.
1. Buka dashboard 9router
2. Tab **Combos** → `free_smart_fallback` → Add Model
3. Tambahin minimal 1 model dari provider yang lo punya

### Bot respond ke orang lain (security!)

```bash
# Cek owner ID
grep TELEGRAM_OWNER_ID /root/.hermes/.env
```

Pastikan ID lo benar (chat sama @userinfobot di Telegram).

```bash
# Update kalau salah
bash configure-hermes.sh
```

---

## VPS / sistem

### Disk penuh

```bash
# Cek
df -h
du -sh /var/log /root/.hermes /root/.9router

# Bersihin
journalctl --vacuum-time=7d
truncate -s 0 /var/log/9router-tunnel.log
apt-get clean
```

### Memory pressure

```bash
free -h
# Kalau swap ga ada / kecil:
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

### Service crash terus (Restart=always loop)

```bash
# Liat exit code + reason
systemctl status hermes
journalctl -u hermes -n 100 --no-pager

# Disable temporary
systemctl stop hermes
systemctl disable hermes

# Setelah fix:
systemctl enable --now hermes
```

---

## Named Tunnel (URL permanen)

Kalau lo capek URL random tiap restart, pake named tunnel. Butuh:
- Akun Cloudflare (gratis)
- Domain di Cloudflare (gratis kalau lo udah punya, atau beli ~$10/tahun)

```bash
# 1. Login Cloudflare
cloudflared tunnel login
# (buka URL yang muncul, pilih domain lo)

# 2. Bikin tunnel
cloudflared tunnel create 9router-prod
# Output: tunnel ID + path ke credentials json

# 3. Route DNS
cloudflared tunnel route dns 9router-prod 9router.yourdomain.com

# 4. Bikin config
mkdir -p /etc/cloudflared
cat > /etc/cloudflared/config.yml <<EOF
tunnel: 9router-prod
credentials-file: /root/.cloudflared/<TUNNEL_ID>.json

ingress:
  - hostname: 9router.yourdomain.com
    service: http://localhost:20128
  - service: http_status:404
EOF

# 5. Ganti systemd service
systemctl stop 9router-tunnel
systemctl disable 9router-tunnel

# Pakai cloudflared service install resmi
cloudflared service install
systemctl restart cloudflared
systemctl enable cloudflared

# Cek
systemctl status cloudflared
# Buka: https://9router.yourdomain.com
```

---

## Reset total (nuklir)

Kalau semua udah kacau dan lo cuma mau mulai dari awal:

```bash
sudo bash uninstall.sh
# konfirmasi semua y

# Pull update repo
cd ~/cara-setup-agent
git pull

# Install ulang
sudo bash install.sh
```

API key di provider (OpenRouter dll) tetap aman — gak ke-revoke. Tinggal
paste lagi di `bash add-provider.sh`.
