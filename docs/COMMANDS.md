# Cheatsheet Command

Semua command yang sering dipake setelah install. Copas aja.

---

## Service control

> Service Hermes namanya `hermes-gateway` (dipasang sama `hermes gateway install`),
> bukan `hermes`.

```bash
# Status semua sekaligus
systemctl status 9router hermes-gateway 9router-tunnel --no-pager

# Restart
systemctl restart 9router
systemctl restart hermes-gateway
systemctl restart 9router-tunnel

# Stop sementara
systemctl stop hermes-gateway

# Start
systemctl start hermes-gateway

# Disable auto-start
systemctl disable hermes-gateway
```

---

## Liat log

```bash
# Live log (Ctrl+C buat stop)
journalctl -u 9router -f
journalctl -u hermes-gateway -f
journalctl -u 9router-tunnel -f

# 50 baris terakhir
journalctl -u hermes-gateway -n 50 --no-pager

# Log error doang
journalctl -u hermes-gateway -p err -n 50

# Log dari 10 menit terakhir
journalctl -u hermes-gateway --since "10 min ago"
```

---

## Tunnel URL

```bash
# Ambil URL terakhir (cara cepet)
cat /root/.hermes/tunnel-url.txt

# Ambil URL dari log (kalau file di atas missing)
journalctl -u 9router-tunnel --since "10 min ago" --no-pager \
  | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1

# Restart tunnel + ambil URL baru
systemctl restart 9router-tunnel
sleep 8
journalctl -u 9router-tunnel --since "1 min ago" --no-pager \
  | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1
```

---

## Tambah / hapus / test provider

```bash
# Tambah provider baru (interaktif)
bash add-provider.sh

# Test provider tertentu
bash test-provider.sh openrouter
bash test-provider.sh groq llama-3.3-70b-versatile
```

---

## Konfigurasi Hermes

```bash
# Update token Telegram / API key 9router (interaktif)
bash configure-hermes.sh

# Edit manual
nano /root/.hermes/.env
systemctl restart hermes-gateway

# Cek isi config (tanpa nampilin secret)
sed 's/=.*/=<hidden>/' /root/.hermes/.env

# Hermes CLI langsung
hermes setup           # wizard interaktif (alternative)
hermes gateway start
hermes gateway stop
hermes gateway restart
hermes config          # liat config aktif
hermes update          # update Hermes ke versi terbaru
```

---

## Update

```bash
# Update 9Router
npm install -g 9router@latest
systemctl restart 9router

# Update Hermes
hermes update

# Update repo install ini sendiri
cd ~/cara-setup-agent
git pull
```

---

## Backup

```bash
tar czf hermes-backup-$(date +%Y%m%d).tar.gz \
  /root/.hermes/.env \
  /root/.hermes/config.yaml \
  /root/.9router/

ls -la /root/.9router/
```

---

## Test endpoint langsung

```bash
# Cek 9router up
curl http://localhost:20128/

# Chat completion lewat 9router
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
curl -H "Authorization: Bearer $KEY" http://localhost:20128/v1/models \
  | jq '.data[].id'
```

---

## Disk usage

```bash
du -sh /root/.hermes /root/.9router /usr/local/lib/hermes-agent
journalctl --vacuum-time=7d
```

---

## Firewall

```bash
ufw status numbered
ufw allow 8080/tcp
ufw delete allow 20128/tcp
```

---

## Troubleshooting cepat

```bash
# 1. Semua service hidup?
systemctl is-active 9router hermes-gateway 9router-tunnel

# 2. Port 20128 listening?
ss -tlnp | grep 20128

# 3. Tunnel jalan?
curl -I "$(cat /root/.hermes/tunnel-url.txt)"

# 4. .env lengkap?
grep -E '^(TELEGRAM_BOT_TOKEN|TELEGRAM_OWNER_ID|OPENAI_API_KEY|OPENAI_BASE_URL)=' /root/.hermes/.env \
  | awk -F= '{print $1, ($2 ? "OK" : "EMPTY")}'

# 5. Repair full
sudo bash fix.sh
```
