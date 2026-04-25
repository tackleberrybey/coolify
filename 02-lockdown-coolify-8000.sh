#!/usr/bin/env bash
set -euo pipefail

echo "=================================================="
echo " Coolify 8000 lockdown"
echo "=================================================="

if [ "$(id -u)" -ne 0 ]; then
  echo "Bu script root olarak çalışmalı."
  echo "Örnek: sudo bash 02-lockdown-coolify-8000.sh"
  exit 1
fi

COOLIFY_DIR="/data/coolify/source"

if [ ! -d "$COOLIFY_DIR" ]; then
  echo "HATA: $COOLIFY_DIR bulunamadı."
  echo "Coolify kurulu değil gibi görünüyor."
  exit 1
fi

cd "$COOLIFY_DIR"

if [ ! -f docker-compose.prod.yml ]; then
  echo "HATA: docker-compose.prod.yml bulunamadı."
  exit 1
fi

echo
echo "=================================================="
echo "1) Backing up docker-compose.prod.yml"
echo "=================================================="

cp docker-compose.prod.yml "docker-compose.prod.yml.bak-$(date +%Y%m%d-%H%M%S)"

echo
echo "=================================================="
echo "2) Binding Coolify 8000 to Docker internal IP only"
echo "=================================================="

python3 <<'PY'
from pathlib import Path

path = Path("docker-compose.prod.yml")
text = path.read_text().splitlines()

out = []
i = 0
in_coolify = False
changed = False

while i < len(text):
    line = text[i]
    stripped = line.strip()

    if line.startswith("  coolify:"):
        in_coolify = True
        out.append(line)
        i += 1
        continue

    if in_coolify and line.startswith("  ") and not line.startswith("    ") and stripped.endswith(":") and not line.startswith("  coolify:"):
        in_coolify = False

    if in_coolify and line.startswith("    ports:"):
        out.append("    ports:")
        out.append('      - "10.0.0.1:8000:8080"')
        changed = True
        i += 1

        while i < len(text):
            nxt = text[i]
            if nxt.startswith("      ") or nxt.strip() == "":
                i += 1
                continue
            break
        continue

    out.append(line)
    i += 1

if not changed:
    final = []
    inserted = False
    in_coolify = False

    for line in out:
        if line.startswith("  coolify:"):
            in_coolify = True
            final.append(line)
            continue

        if in_coolify and line.startswith("  ") and not line.startswith("    ") and line.strip().endswith(":"):
            if not inserted:
                final.append("    ports:")
                final.append('      - "10.0.0.1:8000:8080"')
                inserted = True
            in_coolify = False

        if in_coolify and line.startswith("    expose:") and not inserted:
            final.append("    ports:")
            final.append('      - "10.0.0.1:8000:8080"')
            inserted = True

        final.append(line)

    out = final

path.write_text("\n".join(out) + "\n")
PY

echo
echo "=================================================="
echo "3) Recreating Coolify container"
echo "=================================================="

docker compose \
  -f docker-compose.yml \
  -f docker-compose.prod.yml \
  up -d --force-recreate coolify

sleep 15

echo
echo "=================================================="
echo "4) Updating UFW rules"
echo "=================================================="

# Eski public 8000 kuralını kaldırmaya çalış.
# Kural yoksa hata vermesin diye true kullanıyoruz.
ufw delete allow 8000/tcp || true

# Docker iç ağı için izin.
ufw allow in on docker0 from 10.0.0.0/24 to any port 8000 proto tcp
ufw reload

echo
echo "Current UFW rules:"
ufw status numbered

echo
echo "=================================================="
echo "5) Checking port binding"
echo "=================================================="

PORT_CHECK="$(ss -ltnp | grep ':8000' || true)"
echo "$PORT_CHECK"

if echo "$PORT_CHECK" | grep -q "10.0.0.1:8000"; then
  echo "OK: 8000 sadece Docker internal IP üzerinde açık."
else
  echo "UYARI: 10.0.0.1:8000 görünmüyor. Manuel kontrol gerekebilir."
fi

if echo "$PORT_CHECK" | grep -q "0.0.0.0:8000"; then
  echo "UYARI: 8000 public olarak açık görünüyor. Bu istenmeyen durum."
fi

if echo "$PORT_CHECK" | grep -q "\[::\]:8000"; then
  echo "UYARI: 8000 IPv6 public olarak açık görünüyor. Bu istenmeyen durum."
fi

echo
echo "=================================================="
echo "6) Checking internal Coolify access"
echo "=================================================="

curl -I --max-time 10 http://10.0.0.1:8000 || true

echo
echo "=================================================="
echo "7) Checking public 8000 access"
echo "=================================================="

PUBLIC_IP="$(curl -4 -s ifconfig.me || true)"
echo "Public IP: $PUBLIC_IP"

if [ -n "$PUBLIC_IP" ]; then
  curl -I --connect-timeout 5 "http://${PUBLIC_IP}:8000" || echo "OK: public 8000 kapalı veya erişilemiyor."
else
  echo "Public IP alınamadı, public 8000 testi atlandı."
fi

echo
echo "=================================================="
echo "8) Checking Sentinel logs"
echo "=================================================="

sleep 10
docker logs --since 3m coolify-sentinel | grep -Ei 'Pushing|Error|deadline|refused|health|version' || true

echo
echo "=================================================="
echo " Lockdown done"
echo "=================================================="

echo
echo "Doğru 8000 çıktısı şöyle olmalı:"
echo "10.0.0.1:8000"
echo
echo "Şunlar görünmemeli:"
echo "0.0.0.0:8000"
echo "[::]:8000"
