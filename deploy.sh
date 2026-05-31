#!/bin/bash
# deploy.sh — Installa nginx forward proxy con ngx_http_proxy_connect_module
# Target: Ubuntu 26.04 LTS (Resolute)
# Uso: sudo bash deploy.sh [SUBNET] [PORT]
# Default: subnet=192.168.89.0/24, port=3128
#
# Dipendenze: git, wget, ca-certificates (installate dallo script)
# Variabili richieste: nessuna
# Rollback: sudo systemctl stop nginx && sudo rm -rf /usr/local/nginx /etc/systemd/system/nginx.service

set -euo pipefail

SUBNET="${1:-192.168.89.0/24}"
PORT="${2:-3128}"
NGINX_VERSION="1.26.3"
NGINX_DIR="/usr/local/nginx"
LOG_DIR="/var/log/nginx"
PID_FILE="/var/run/nginx.pid"

echo "========================================"
echo " nginx forward proxy deploy"
echo " Target: nginx $NGINX_VERSION + proxy_connect_module"
echo " Subnet: $SUBNET"
echo " Port:   $PORT"
echo "========================================"
echo ""

# ---------- Step 1: Dependencies ----------
echo "[1/8] Install system dependencies..."
apt-get update -qq
apt-get install -y -qq build-essential libpcre2-dev libssl-dev zlib1g-dev libcrypt-dev git wget curl ufw

# ---------- Step 2: Download nginx source ----------
echo "[2/8] Download nginx $NGINX_VERSION source..."
mkdir -p /tmp/nginx-build && cd /tmp/nginx-build
wget -q "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" -O nginx.tar.gz
tar xzf nginx.tar.gz

# ---------- Step 3: Clone proxy_connect module ----------
echo "[3/8] Clone ngx_http_proxy_connect_module..."
git clone -q https://github.com/chobits/ngx_http_proxy_connect_module.git

# ---------- Step 4: Patch and configure ----------
echo "[4/8] Patch and configure nginx..."
cd "nginx-${NGINX_VERSION}"

# Applica la patch per la versione corretta di nginx
patch -p1 < ../ngx_http_proxy_connect_module/patch/proxy_connect_rewrite_102101.patch

# Configura nginx con:
#   - proxy_connect_module per CONNECT/HTTPS
#   - http_v2_module per HTTP/2
#   - stream_ssl_module per TCP proxy SSL (opzionale)
#   - with-cc-opt serve per GCC 15 (Ubuntu 26.04) — evita build failure su string literals
./configure \
    --prefix="$NGINX_DIR" \
    --with-http_ssl_module \
    --add-module=../ngx_http_proxy_connect_module \
    --with-http_stub_status_module \
    --with-http_realip_module \
    --with-http_v2_module \
    --with-stream \
    --with-stream_ssl_module \
    --with-compat \
    --with-cc-opt='-Wno-error=unterminated-string-initialization'

# ---------- Step 5: Compile and install ----------
echo "[5/8] Compile nginx (this may take 2-3 minutes)..."
make -j"$(nproc)"

echo "[6/8] Install nginx..."
make install

# ---------- Step 6: Create log directory ----------
echo "[7/8] Configure log directory..."
mkdir -p "$LOG_DIR"
chown nobody:nogroup "$LOG_DIR" 2>/dev/null || chown nobody:root "$LOG_DIR"

# ---------- Step 7: Write nginx.conf ----------
echo "[8/8] Write nginx config, systemd unit, and firewall..."

cat > "${NGINX_DIR}/conf/nginx.conf" << NGINX_EOF
user  nobody nogroup;
worker_processes  auto;
error_log  ${LOG_DIR}/proxy_error.log  warn;
pid        ${PID_FILE};

events {
    worker_connections  1024;
    multi_accept on;
    use epoll;
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    log_format forward_proxy '\$remote_addr \$remote_user [\$time_local] '
                             '"\$request" \$status \$body_bytes_sent '
                             '"\$http_referer" "\$http_user_agent" '
                             'host="\$http_host" '
                             'upstream="\$upstream_addr" '
                             'connect_addr="\$connect_addr" '
                             'method="\$request_method" '
                             'proto="\$server_protocol" '
                             'rt=\$request_time '
                             'uct=\$upstream_connect_time '
                             'uht=\$upstream_header_time';

    access_log  ${LOG_DIR}/proxy_access.log  forward_proxy buffer=32k flush=5s;

    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;
    keepalive_timeout  65;
    types_hash_max_size 2048;

    resolver 1.1.1.1 8.8.8.8 valid=300s ipv6=off;
    resolver_timeout 10s;

    server {
        listen ${PORT};
        server_name _;

        allow ${SUBNET};
        deny all;

        proxy_connect;
        proxy_connect_allow            443 563;
        proxy_connect_connect_timeout  30s;
        proxy_connect_read_timeout     60s;
        proxy_connect_send_timeout     60s;

        location / {
            proxy_pass \$scheme://\$http_host\$request_uri;
            proxy_set_header Host \$http_host;
            proxy_buffering off;
            proxy_ssl_server_name on;

            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;

            proxy_connect_timeout 30s;
            proxy_read_timeout 60s;
            proxy_send_timeout 60s;
        }
    }
}
NGINX_EOF

# Systemd unit
cat > /etc/systemd/system/nginx.service << SERVICE_EOF
[Unit]
Description=nginx forward proxy con proxy_connect module
After=network.target

[Service]
Type=forking
PIDFile=${PID_FILE}
ExecStartPre=${NGINX_DIR}/sbin/nginx -t
ExecStart=${NGINX_DIR}/sbin/nginx
ExecReload=${NGINX_DIR}/sbin/nginx -s reload
ExecStop=${NGINX_DIR}/sbin/nginx -s quit
PrivateTmp=true
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# UFW firewall
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow from "${SUBNET}" to any port 22 proto tcp comment 'SSH'
ufw allow from "${SUBNET}" to any port "${PORT}" proto tcp comment 'nginx forward proxy'

# ---------- Start service ----------
systemctl daemon-reload
systemctl enable nginx
systemctl restart nginx

echo ""
echo "========================================"
echo " DEPLOY COMPLETED SUCCESSFULLY"
echo "========================================"
echo " Proxy: http://$(hostname -I | awk '{print $1}'):${PORT}"
echo ""
echo " Test HTTP:  curl -x http://IP:${PORT} http://httpbin.org/ip"
echo " Test HTTPS: curl -x http://IP:${PORT} https://httpbin.org/ip"
echo ""
echo " Logs: tail -f ${LOG_DIR}/proxy_access.log"
echo " Status: systemctl status nginx"
echo ""
echo " Log format fields:"
echo "   upstream  = IP:porta RISOLTA del server destinazione"
echo "   host      = hostname richiesto dal client"
echo "   uct       = tempo connessione upstream (latenza DNS+TCP)"
echo "   rt        = tempo totale richiesta"
echo "========================================"
