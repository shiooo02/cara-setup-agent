# Cheatsheet Command

Semua command yang sering dipake setelah install. Copas aja.

---

## Service control

```bash
# Status
systemctl status 9router
systemctl status hermes
systemctl status 9router-tunnel

# Status semua sekaligus (1 perintah)
systemctl status 9router hermes 9router-tunnel --no-pager

# Restart
systemctl restart 9router
systemctl restart hermes
systemctl restart 9router-tunnel

# Stop sementara
systemctl stop hermes

# Start
systemctl start hermes

# Disable auto-start (kalau mau pause permanen)
systemctl disable hermes
```

---

## Liat log

```bash
# Live log (Ctrl+C buat stop)
journalctl -u 9router -f
journalctl -u hermes -f

# 50 baris terakhir
journalctl -u hermes -n 50 --no-pager

# Log error doang
journalctl -u hermes -p err -n 50

# Log dari 10 menit terakhir
journalctl -u hermes --since "10 min ago"

# Log tunnel (cloudflared)
tail -f /var/log/9router-tunnel.log
```

---

## Tunnel URL

```bash
# Ambil URL terakhir
cat /root/.hermes/tunnel-url.txt

# Tunnel URL berubah? Restart tunnel + ambil URL baru
systemctl restart 9router-tunnel
sleep 5
grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' /var/log/9router-tunnel.log | tail -1
```

---

## Tambah / hapus / test provider

```bash
# Tambah provider baru (interaktif)
bash add-provider.sh

# Test provider tertentu
bash test-provider.sh openrouter
bash test-provider.sh groq llama-3.3-70b-versatile

# List provider yang udah terdaftar
TOKEN=$(node -e '
const c=require("crypto"),{machineIdSync}=require("node-machine-id");
process.stdout.write(c.createHash("sha256").update(machineIdSync()+"9r-cli-auth").digest("hex").substring(0,16));
' --import 'data:text/javascript,import(process.env.NODE_PATH+"/node-machine-id")' 2>/dev/null)
curl -s -H "x-9r-cli-token: $TOKEN" http://localhost:20128/api/provider-nodes | jq

# Atau tinggal liat dari dashboard.
```

---

## Konfigurasi Hermes

```bash
# Update token Telegram / API key 9router (interaktif)
bash configure-hermes.sh

# Edit manual
nano /root/.hermes/.env
systemctl restart hermes

# Cek isi config (tanpa nampilin secret)
sed 's/=.*/=<hidden>/' /root/.hermes/.env
```

---

## Update

```bash
# Update 9Router ke versi terbaru
npm install -g 9router@latest
systemctl restart 9router

# Update Hermes
cd /root/.hermes
npm update hermes-agent
systemctl restart hermes

# Update repo install ini sendiri
cd ~/cara-setup-agent
git pull
```

---

## Backup

```bash
# Backup config + DB 9router
tar czf hermes-backup-$(date +%Y%m%d).tar.gz \
  /root/.hermes/.env \
  /root/.hermes/config.yaml \
  /root/.9router/

# Lokasi DB 9router yang penting
ls -la /root/.9router/
```

---

## Test endpoint langsung

```bash
# Cek 9router up
curl http://localhost:20128/

# Chat completion lewat 9router (ganti $KEY dengan API key 9router)
KEY="sk-xxxxxxxxxxxx"

curl -X POST http://localhost:20128/v1/chat/completions \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "free_smart_fallback",
    "messages": [{"role":"user","content":"halo"}],
    "max_tokens": 50
  }' | jq

# List model yang available
curl -H "Authorization: Bearer $KEY" \
  http://localhost:20128/v1/models | jq '.data[].id'
```

---

## Disk usage

```bash
# Cek size install
du -sh /root/.hermes /root/.9router

# Bersihin log lama (kalau /var/log penuh)
journalctl --vacuum-time=7d
truncate -s 0 /var/log/9router-tunnel.log
```

---

## Firewall

```bash
# Cek rule yang aktif
ufw status numbered

# Buka port baru (misal 8080)
ufw allow 8080/tcp

# Tutup port
ufw delete allow 20128/tcp   # tutup port 9router (kalau lo cuma mau lewat tunnel)
```

---

## Telegram bot management

```bash
# Restart bot (paling sering kepake)
systemctl restart hermes

# Liat error realtime saat ngirim pesan
journalctl -u hermes -f

# Stop bot biar gak respond (sambil debug)
systemctl stop hermes
```

---

## Troubleshooting cepat

```bash
# 1. Semua service hidup?
systemctl is-active 9router hermes 9router-tunnel

# 2. Port 20128 listening?
ss -tlnp | grep 20128

# 3. Tunnel jalan?
curl -I "$(cat /root/.hermes/tunnel-url.txt)"

# 4. .env lengkap?
grep -E '^(TELEGRAM_BOT_TOKEN|TELEGRAM_OWNER_ID|OPENAI_API_KEY|OPENAI_BASE_URL)=' /root/.hermes/.env \
  | awk -F= '{print $1, $2 ? "OK" : "EMPTY"}'
```
