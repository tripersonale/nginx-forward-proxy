#!/bin/bash
# check.sh — Verifica automatica installazione nginx forward proxy
# Esegui dopo aver completato l'installazione (README.md Step 1-12)
# Uso: bash check.sh [PROXY_IP] [PROXY_PORT]
#      Se ometti PROXY_IP, usa localhost (funziona solo se localhost è autorizzato)
#
# Esempio: bash check.sh 192.168.89.140 3128

set -euo pipefail
NGINX_BIN="/usr/local/nginx/sbin/nginx"
PROXY_HOST="${1:-localhost}"
PROXY_PORT="${2:-3128}"
PASS=0
FAIL=0

green() { echo -e "\033[32m✅ $1\033[0m"; }
red()   { echo -e "\033[31m❌ $1\033[0m"; }
info()  { echo -e "\033[36m   $1\033[0m"; }

echo "========================================"
echo " nginx forward proxy — check"
echo " Target: ${PROXY_HOST}:${PROXY_PORT}"
echo "========================================"
echo ""

# --- 1. nginx binary ---
echo -n "[1] nginx binary... "
if [ -x "$NGINX_BIN" ]; then
    green "found ($($NGINX_BIN -v 2>&1))"
    PASS=$((PASS + 1))
else
    red "NOT FOUND at $NGINX_BIN"
    FAIL=$((FAIL + 1))
fi

# --- 2. config valid (needs sudo) ---
echo -n "[2] nginx config... "
if OUT=$(sudo "$NGINX_BIN" -t 2>&1); then
    green "valid"
    PASS=$((PASS + 1))
else
    red "INVALID"
    info "$OUT"
    FAIL=$((FAIL + 1))
fi

# --- 3. port listening ---
echo -n "[3] Port ${PROXY_PORT}... "
if ss -tlnp 2>/dev/null | grep -q ":${PROXY_PORT} "; then
    green "LISTEN"
    PASS=$((PASS + 1))
elif netstat -tlnp 2>/dev/null | grep -q ":${PROXY_PORT} "; then
    green "LISTEN"
    PASS=$((PASS + 1))
else
    red "NOT LISTENING"
    FAIL=$((FAIL + 1))
fi

# --- 4. systemd active ---
echo -n "[4] systemd service... "
if systemctl is-active --quiet nginx 2>/dev/null; then
    green "active"
    PASS=$((PASS + 1))
else
    red "NOT ACTIVE"
    FAIL=$((FAIL + 1))
fi

# --- 5. UFW active (needs sudo) ---
echo -n "[5] UFW firewall... "
if command -v ufw &>/dev/null && sudo ufw status 2>/dev/null | grep -q "Status: active"; then
    green "active"
    PASS=$((PASS + 1))
else
    red "NOT ACTIVE (ok if you manage firewall elsewhere)"
    FAIL=$((FAIL + 1))
fi

# --- 6. HTTP proxy (usa example.com, più affidabile di httpbin) ---
echo -n "[6] HTTP proxy... "
if OUT=$(curl -x "http://${PROXY_HOST}:${PROXY_PORT}" -s -o /dev/null -w "%{http_code}" --connect-timeout 10 http://example.com 2>/dev/null); then
    if [ "$OUT" = "200" ]; then
        green "HTTP 200"
        PASS=$((PASS + 1))
    else
        red "HTTP $OUT (expected 200)"
        FAIL=$((FAIL + 1))
    fi
else
    red "CONNECTION FAILED"
    FAIL=$((FAIL + 1))
fi

# --- 7. HTTPS proxy (CONNECT, usa google.com) ---
echo -n "[7] HTTPS CONNECT... "
if OUT=$(curl -x "http://${PROXY_HOST}:${PROXY_PORT}" -s -o /dev/null -w "%{http_code}" --connect-timeout 10 https://www.google.com 2>/dev/null); then
    if [ "$OUT" = "200" ]; then
        green "HTTPS 200"
        PASS=$((PASS + 1))
    else
        red "HTTPS $OUT (expected 200)"
        FAIL=$((FAIL + 1))
    fi
else
    red "CONNECTION FAILED"
    FAIL=$((FAIL + 1))
fi

# --- 8. Block unauthorized (127.0.0.1 non è nella LAN) ---
echo -n "[8] Block unauthorized... "
if OUT=$(curl -x "http://127.0.0.1:${PROXY_PORT}" -s -o /dev/null -w "%{http_code}" --connect-timeout 3 http://example.com 2>/dev/null); then
    if [ "$OUT" = "403" ]; then
        green "403 (blocked by nginx)"
        PASS=$((PASS + 1))
    elif [ "$OUT" = "000" ]; then
        green "000 (blocked by firewall)"
        PASS=$((PASS + 1))
    else
        red "HTTP $OUT (expected 403 or 000)"
        FAIL=$((FAIL + 1))
    fi
else
    green "TCP blocked (firewall)"
    PASS=$((PASS + 1))
fi

# --- 9. Log file ---
echo -n "[9] Access log... "
if [ -f /var/log/nginx/proxy_access.log ]; then
    LINES=$(wc -l < /var/log/nginx/proxy_access.log)
    green "exists (${LINES} lines)"
    PASS=$((PASS + 1))
else
    red "NOT FOUND at /var/log/nginx/proxy_access.log"
    FAIL=$((FAIL + 1))
fi

# --- 10. Log contains upstream_addr ---
echo -n "[10] Log has upstream IP... "
if [ -f /var/log/nginx/proxy_access.log ]; then
    if grep -q 'upstream="[0-9]' /var/log/nginx/proxy_access.log 2>/dev/null; then
        green "IP destination resolved and logged"
        PASS=$((PASS + 1))
    else
        info "no HTTP upstream entries yet — run 'curl -x ... http://example.com' first"
        FAIL=$((FAIL + 1))
    fi
else
    red "LOG MISSING"
    FAIL=$((FAIL + 1))
fi

# --- Summary ---
echo ""
echo "========================================"
echo " RESULTS: ${PASS} passed, ${FAIL} failed"
echo "========================================"

if [ "$FAIL" -eq 0 ]; then
    green "ALL CHECKS PASSED — proxy is working!"
    echo ""
    echo "  curl -x http://${PROXY_HOST}:${PROXY_PORT} http://example.com"
    echo "  tail -f /var/log/nginx/proxy_access.log"
    exit 0
else
    red "${FAIL} check(s) failed — review the errors above"
    exit 1
fi
