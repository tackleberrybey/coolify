#!/usr/bin/env bash
set -euo pipefail

echo "=================================================="
echo " Coolify initial install"
echo "=================================================="

if [ "$(id -u)" -ne 0 ]; then
  echo "Bu script root olarak çalışmalı."
  echo "Örnek: sudo bash 01-install-coolify-initial.sh"
  exit 1
fi

echo
echo "=================================================="
echo "1) Installing required packages"
echo "=================================================="

apt-get update -y
apt-get install -y curl ca-certificates python3 ufw openssh-server

echo
echo "=================================================="
echo "2) Installing Coolify"
echo "=================================================="

curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash

echo
echo "=================================================="
echo "3) Hardening SSH"
echo "=================================================="

SSHD_CONFIG="/etc/ssh/sshd_config"
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak-$(date +%Y%m%d-%H%M%S)"

set_sshd_option() {
  local key="$1"
  local value="$2"

  if grep -Eq "^[#[:space:]]*${key}[[:space:]]+" "$SSHD_CONFIG"; then
    sed -i -E "s|^[#[:space:]]*${key}[[:space:]]+.*|${key} ${value}|" "$SSHD_CONFIG"
  else
    echo "${key} ${value}" >> "$SSHD_CONFIG"
  fi
}

set_sshd_option "PermitRootLogin" "without-password"
set_sshd_option "PubkeyAuthentication" "yes"
set_sshd_option "PasswordAuthentication" "no"

sshd -t
systemctl restart ssh || systemctl restart sshd

echo
echo "=================================================="
echo "4) Configuring UFW firewall"
echo "=================================================="

ufw --force reset
ufw default deny incoming
ufw default allow outgoing

ufw allow from 100.64.0.0/10 to any port 22 proto tcp
ufw allow from 10.0.1.0/24 to any port 22 proto tcp
ufw allow 80/tcp
ufw allow 443/tcp

# Geçici olarak açık.
# İlk Coolify setup ve domain tanımlama için gerekiyor.
ufw allow 8000/tcp

ufw --force enable

echo
echo "Current UFW rules:"
ufw status numbered

echo
echo "=================================================="
echo "5) Installing Tailscale"
echo "=================================================="

curl -fsSL https://tailscale.com/install.sh | sh

echo
echo "=================================================="
echo "6) Starting Tailscale login"
echo "=================================================="

echo "Tailscale login başlatılıyor."
echo "Eğer link çıkarsa, browser'da açıp giriş yap."
tailscale up

echo
echo "=================================================="
echo " Initial setup done"
echo "=================================================="

PUBLIC_IP="$(curl -4 -s ifconfig.me || true)"

echo
echo "Sonraki adımlar:"
echo
echo "1) Browser'da Coolify'a gir:"
echo "   http://${PUBLIC_IP}:8000"
echo
echo "2) Coolify ilk setup'ı tamamla."
echo
echo "3) Coolify içinde domain'i ayarla:"
echo "   Settings → Configuration → General → URL"
echo "   örnek: https://mycoolify.top"
echo
echo "4) DNS / Cloudflare / Zero Trust ayarlarını tamamla."
echo
echo "5) Domain ile dashboard açıldığını doğrula:"
echo "   https://mycoolify.top"
echo
echo "6) Sonra ikinci script'i çalıştır:"
echo "   02-lockdown-coolify-8000.sh"
echo
echo "ÖNEMLİ:"
echo "Bu aşamada 8000 portu geçici olarak public açık."
echo "Domain çalıştıktan sonra mutlaka ikinci script'i çalıştır."
