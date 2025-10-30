#!/bin/bash
set -e

# Обновляем систему и ставим зависимости
sudo apt-get update && sudo apt-get upgrade -y
sudo apt install -y curl unzip

# Включаем синхронизацию времени (V2Ray чувствителен к расхождению часов)
sudo timedatectl set-ntp true

# Скачиваем и устанавливаем последнюю версию V2Ray/Xray
curl -O https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh
sudo bash install-release.sh   # скрипт скачает и установит бинарники и systemd‑юнит

# Создаём конфигурацию V2Ray (протокол VLESS через WebSocket с TLS)
sudo tee /usr/local/etc/v2ray/config.json >/dev/null <<'EOF'
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log"
  },
  "inbounds": [
    {
      "port": 10000,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "YOUR-UUID-HERE",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/etc/ssl/certs/your_domain.crt",
              "keyFile": "/etc/ssl/private/your_domain.key"
            }
          ]
        },
        "wsSettings": {
          "path": "/ray"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

# Включаем автозапуск и перезапускаем службу
sudo systemctl enable v2ray
sudo systemctl restart v2ray

# Ставим Nginx и настраиваем обратный прокси на WebSocket‑порт V2Ray
sudo apt install -y nginx
sudo tee /etc/nginx/conf.d/v2ray.conf >/dev/null <<'EOF'
server {
    listen 80;
    server_name your_domain;

    location /ray {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
EOF
sudo nginx -t && sudo systemctl reload nginx

# Устанавливаем certbot и выпускаем TLS‑сертификат Let’s Encrypt (по желанию)
sudo apt install -y snapd
sudo snap install core --classic
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot
# Замените адрес электронной почты и домен на свои значения
sudo certbot --nginx --agree-tos --redirect --hsts --staple-ocsp \
  -d your_domain -m admin@your_domain

echo "Установка завершена. Теперь сервер принимает подключения v2raytun через VLESS/TLS/WS."
