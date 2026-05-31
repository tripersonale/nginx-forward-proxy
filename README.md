# nginx forward proxy — Guida passo-passo

Forward proxy con **nginx 1.26.3** su **Ubuntu 26.04 LTS** che logga l'IP di destinazione risolto.

## Cosa fa

- **HTTP forward proxy** — inoltra richieste HTTP standard
- **HTTPS forward proxy** — supporta il metodo CONNECT per il tunneling HTTPS
- **Logging completo** — registra IP client, host richiesto, IP destinazione risolto, metodo, tempi, user-agent
- **Sicurezza base** — accesso limitato alla subnet LAN, UFW attivo

## Architettura

```
Client (192.168.89.x) ──► nginx forward proxy (:3128) ──► Internet
                                │
                                └── log: upstream="3.234.10.121:80"
                                         host="httpbin.org"
                                         method="GET"
                                         rt=0.549
```

---

## Guida passo-passo (copia-e-incolla)

### Prerequisiti

- Macchina virtuale o fisica con **Ubuntu 26.04 LTS** installata
- Accesso root o `sudo`
- Connessione a Internet per scaricare sorgenti e pacchetti
- Almeno 2 GB RAM e 10 GB disco libero

### Step 1 — Diventa root

```bash
sudo -i
```

Tutti i comandi successivi vanno eseguiti come root. Il prompt diventa `root@hostname:~#`.

### Step 2 — Aggiorna i pacchetti e installa le dipendenze

```bash
apt-get update
apt-get install -y build-essential libpcre2-dev libssl-dev zlib1g-dev libcrypt-dev git wget curl ufw
```

Spiegazione delle dipendenze:
- `build-essential` → gcc, g++, make (compilatore C)
- `libpcre2-dev` → libreria PCRE2 per le espressioni regolari di nginx (Ubuntu 26.04 ha rimosso PCRE1, solo PCRE2 è disponibile)
- `libssl-dev` → OpenSSL per HTTPS/TLS
- `zlib1g-dev` → compressione gzip
- `libcrypt-dev` → funzioni di crypt() per auth (su Ubuntu 26.04 è pacchetto separato)
- `git` → per clonare il modulo proxy_connect
- `wget` → per scaricare nginx
- `curl` → per testare il proxy
- `ufw` → firewall

### Step 3 — Crea directory di lavoro e scarica nginx

```bash
mkdir -p /tmp/nginx-build && cd /tmp/nginx-build
wget https://nginx.org/download/nginx-1.26.3.tar.gz
tar xzf nginx-1.26.3.tar.gz
```

Perché nginx 1.26.3? È l'ultima versione stabile della serie 1.26. La versione 1.27 è più recente ma usa un patch diverso per il modulo proxy_connect. Se vuoi usare una versione diversa, verifica la compatibilità nella [tabella dei patch](https://github.com/chobits/ngx_http_proxy_connect_module#readme).

### Step 4 — Clona il modulo proxy_connect

```bash
git clone https://github.com/chobits/ngx_http_proxy_connect_module.git
```

Il modulo `ngx_http_proxy_connect_module` aggiunge il supporto al metodo CONNECT, necessario per il forward proxy HTTPS. Nginx vanilla non lo supporta. Senza questo modulo, puoi solo fare proxy HTTP.

### Step 5 — Applica la patch e configura nginx

```bash
cd nginx-1.26.3

# Applica la patch per la compatibilità tra nginx 1.26 e il modulo
# Il numero di patch (102101) corrisponde alla versione di nginx:
#   101800 → nginx 1.18,  102101 → nginx 1.26.1-1.26.3
patch -p1 < ../ngx_http_proxy_connect_module/patch/proxy_connect_rewrite_102101.patch

# Configura nginx con i moduli necessari
./configure \
    --prefix=/usr/local/nginx \
    --with-http_ssl_module \
    --add-module=../ngx_http_proxy_connect_module \
    --with-http_stub_status_module \
    --with-http_realip_module \
    --with-http_v2_module \
    --with-stream \
    --with-stream_ssl_module \
    --with-compat \
    --with-cc-opt='-Wno-error=unterminated-string-initialization'
```

Spiegazione di ogni flag di configure:

| Flag | Perché |
|------|--------|
| `--prefix=/usr/local/nginx` | Directory di installazione |
| `--with-http_ssl_module` | Supporto SSL/TLS per le connessioni HTTPS |
| `--add-module=../ngx_http_proxy_connect_module` | **CRITICO** — aggiunge il metodo CONNECT per proxy HTTPS |
| `--with-http_stub_status_module` | Pagina `/nginx_status` per monitoring (opzionale ma utile) |
| `--with-http_realip_module` | Passa l'IP reale del client nei header `X-Real-IP` |
| `--with-http_v2_module` | Supporto HTTP/2 |
| `--with-stream` | Modulo TCP/UDP proxy (opzionale, per proxy TCP generico) |
| `--with-stream_ssl_module` | SSL per il modulo stream |
| `--with-compat` | Compatibilità con moduli dinamici esterni |
| `--with-cc-opt='-Wno-error=unterminated-string-initialization'` | **NECESSARIO su Ubuntu 26.04** — GCC 15 tratta i warning di stringhe non terminate come errori. nginx 1.26.3 ha array di char non null-terminated che triggerano questo warning nel modulo HTTP/2. Senza questo flag, la compilazione fallisce. |

### Step 6 — Compila e installa

```bash
# Compila usando tutti i core disponibili (più veloce)
make -j$(nproc)

# Installa in /usr/local/nginx
make install
```

La compilazione dura 1-3 minuti su una macchina moderna.

Verifica che nginx sia installato correttamente:

```bash
/usr/local/nginx/sbin/nginx -V
```

L'output deve mostrare:
```
nginx version: nginx/1.26.3
...
configure arguments: ... --add-module=../ngx_http_proxy_connect_module ...
```

### Step 7 — Crea la directory dei log

```bash
mkdir -p /var/log/nginx
chown nobody:nogroup /var/log/nginx
```

Se `nogroup` non esiste sul tuo sistema, usa `chown nobody:root /var/log/nginx`.

### Step 8 — Scrivi la configurazione nginx

```bash
cat > /usr/local/nginx/conf/nginx.conf << 'EOF'
user  nobody nogroup;
worker_processes  auto;
error_log  /var/log/nginx/proxy_error.log  warn;
pid        /var/run/nginx.pid;

events {
    worker_connections  1024;
    multi_accept on;
    use epoll;
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    # === LOG FORMAT: registra IP destinazione risolto ===
    # $upstream_addr  → IP:porta del server di destinazione dopo risoluzione DNS
    #   $http_host    → hostname richiesto dal client (es. "httpbin.org")
    # $request        → prima riga della richiesta (GET / HTTP/1.1)
    # $status         → codice HTTP di risposta
    # $body_bytes_sent → dimensione risposta in byte
    # $request_time   → tempo totale richiesta in secondi
    # $upstream_connect_time → tempo impiegato per connettersi all'upstream
    # $upstream_header_time  → tempo per ricevere gli header dall'upstream
    log_format forward_proxy '$remote_addr $remote_user [$time_local] '
                             '"$request" $status $body_bytes_sent '
                             '"$http_referer" "$http_user_agent" '
                             'host="$http_host" '
                             'upstream="$upstream_addr" '
                             'method="$request_method" '
                             'proto="$server_protocol" '
                             'rt=$request_time '
                             'uct=$upstream_connect_time '
                             'uht=$upstream_header_time';

    # Scrive i log con buffer di 32KB o ogni 5 secondi
    access_log  /var/log/nginx/proxy_access.log  forward_proxy buffer=32k flush=5s;

    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;
    keepalive_timeout  65;
    types_hash_max_size 2048;

    # DNS resolver — usa solo IPv4 (ipv6=off) perché il server potrebbe non avere IPv6
    resolver 1.1.1.1 8.8.8.8 valid=300s ipv6=off;
    resolver_timeout 10s;

    server {
        listen 3128;
        server_name _;

        # Accesso limitato alla LAN
        allow 192.168.89.0/24;
        deny all;

        # === CONNECT per HTTPS ===
        # Abilita il metodo CONNECT per tunnelare HTTPS
        proxy_connect;
        proxy_connect_allow            443 563;
        proxy_connect_connect_timeout  30s;
        proxy_connect_read_timeout     60s;
        proxy_connect_send_timeout     60s;

        # === HTTP forward proxy ===
        location / {
            # Inoltra la richiesta al server di destinazione
            # $scheme = http/https, $http_host = host:port richiesto
            proxy_pass $scheme://$http_host$request_uri;
            proxy_set_header Host $http_host;
            proxy_buffering off;
            proxy_ssl_server_name on;  # SNI per HTTPS

            # Passa l'IP del client originale
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;

            proxy_connect_timeout 30s;
            proxy_read_timeout 60s;
            proxy_send_timeout 60s;
        }
    }
}
EOF
```

**Attenzione**: modifica `allow 192.168.89.0/24;` con la tua subnet LAN.

### Step 9 — Crea il servizio systemd

```bash
cat > /etc/systemd/system/nginx.service << 'EOF'
[Unit]
Description=nginx forward proxy con proxy_connect module
After=network.target

[Service]
Type=forking
PIDFile=/var/run/nginx.pid
ExecStartPre=/usr/local/nginx/sbin/nginx -t
ExecStart=/usr/local/nginx/sbin/nginx
ExecReload=/usr/local/nginx/sbin/nginx -s reload
ExecStop=/usr/local/nginx/sbin/nginx -s quit
PrivateTmp=true
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

Spiegazione:
- `Type=forking` → nginx fa fork del processo master e backgrounda
- `ExecStartPre` → testa la configurazione prima di avviare (se la configurazione è rotta, nginx non parte)
- `ExecReload` → ricarica la configurazione senza fermare le connessioni attive
- `PrivateTmp=true` → isola la directory `/tmp` del processo
- `Restart=on-failure` → riavvia automaticamente se nginx crasha

### Step 10 — Configura il firewall (UFW)

```bash
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow from 192.168.89.0/24 to any port 22 proto tcp comment 'SSH'
ufw allow from 192.168.89.0/24 to any port 3128 proto tcp comment 'nginx proxy'
```

**Attenzione**: modifica `192.168.89.0/24` con la tua subnet.

### Step 11 — Avvia nginx

```bash
systemctl daemon-reload
systemctl enable nginx
systemctl start nginx
systemctl status nginx
```

L'output deve mostrare `active (running)`.

### Step 12 — Verifica che la porta 3128 sia in ascolto

```bash
ss -tlnp | grep 3128
```

Deve mostrare:
```
LISTEN 0  511  0.0.0.0:3128  0.0.0.0:*  users:(("nginx",pid=...,fd=6))
```

---

## Test

Esegui i test da un client sulla stessa LAN.

### Test 1 — HTTP

```bash
curl -x http://<IP_PROXY>:3128 -v http://httpbin.org/ip
```

Risposta attesa: `HTTP 200` con il tuo IP pubblico in JSON.

### Test 2 — HTTPS (CONNECT)

```bash
curl -x http://<IP_PROXY>:3128 -v https://httpbin.org/ip
```

Risposta attesa: `HTTP 200`. Verifica nei log che appaia la riga `CONNECT httpbin.org:443`.

### Test 3 — Verifica i log

```bash
tail -f /var/log/nginx/proxy_access.log
```

Esempio di output:
```
192.168.89.55 - [28/May/2026:11:11:31 +0000] "GET http://httpbin.org/ip HTTP/1.1" 200 45 "-" "curl/8.5.0" host="httpbin.org" upstream="34.234.10.121:80" method="GET" proto="HTTP/1.1" rt=0.549 uct=0.107 uht=0.535
```

Campi importanti:
- `host="httpbin.org"` — il sito richiesto dal client
- `upstream="34.234.10.121:80"` — **l'IP risolto del server di destinazione** (questo è il campo che ti interessa)
- `method="GET"` — GET, POST, CONNECT
- `uct=0.107` — tempo di connessione DNS + TCP (latenza)
- `rt=0.549` — tempo totale richiesta

Per richieste HTTPS (CONNECT), `upstream` sarà `-` perché il tunnel TCP bypassa il layer HTTP di nginx. Tuttavia, l'`host` rimane visibile (es. `host="httpbin.org:443"`).

### Test 4 — Browser

Configura il proxy nel browser:
- **Tipo proxy**: HTTP
- **Server**: `<IP_PROXY>`
- **Porta**: `3128`

Naviga su qualsiasi sito. I log mostreranno tutte le connessioni con l'IP risolto (per HTTP) e l'hostname (per HTTPS).

---

## Comandi utili

```bash
# Riavvia nginx
systemctl restart nginx

# Ricarica configurazione senza downtime
systemctl reload nginx

# Vedi log in tempo reale
tail -f /var/log/nginx/proxy_access.log

# Conta richieste per host (top 10)
grep -oP 'host="\K[^"]+' /var/log/nginx/proxy_access.log | sort | uniq -c | sort -rn | head

# Conta richieste per IP client
awk '{print $1}' /var/log/nginx/proxy_access.log | sort | uniq -c | sort -rn | head

# Errori
tail -f /var/log/nginx/proxy_error.log

# Test configurazione
/usr/local/nginx/sbin/nginx -t
```

---

## Troubleshooting

### Errore: `connect() to [2a00:...]:443 failed (101: Network is unreachable)`

nginx risolve i nomi in IPv6 ma il server non ha connettività IPv6. Soluzione: aggiungi `ipv6=off` al resolver (`resolver 1.1.1.1 8.8.8.8 valid=300s ipv6=off;`).

### Errore: `no resolver defined to resolve ...`

Manca la direttiva `resolver` nel blocco `http`. Aggiungila (Step 8).

### Errore: `patch: **** malformed patch`

Stai usando una patch non compatibile con la versione di nginx. Controlla la [matrice di compatibilità](https://github.com/chobits/ngx_http_proxy_connect_module#version-compatibility).

### Errore: `make: *** [objs/src/http/v2/ngx_http_v2_filter_module.o] Error 1`

GCC 15 su Ubuntu 26.04 è più severo con i warning. Aggiungi `--with-cc-opt='-Wno-error=unterminated-string-initialization'` alla configurazione (Step 5).

### Errore: `fatal error: crypt.h: No such file or directory`

Su Ubuntu 26.04, `libcrypt-dev` non è più incluso in `build-essential`. Installa: `apt-get install -y libcrypt-dev`.

### Errore: `E: Package 'libpcre3-dev' has no installation candidate`

Ubuntu 26.04 ha rimosso PCRE1. Usa PCRE2: `apt-get install -y libpcre2-dev`.

---

## Rollback / Rimozione

```bash
systemctl stop nginx
systemctl disable nginx
rm -f /etc/systemd/system/nginx.service
rm -rf /usr/local/nginx
rm -rf /var/log/nginx
systemctl daemon-reload
```

---

## Deploy automatico

Uno script `deploy.sh` incluso in questo repository esegue automaticamente tutti gli step sopra. Uso:

```bash
chmod +x deploy.sh
sudo bash deploy.sh [SUBNET] [PORT]

# Esempio:
sudo bash deploy.sh 192.168.89.0/24 3128
```

---

## Riferimenti

- [nginx ufficiale](https://nginx.org/)
- [ngx_http_proxy_connect_module](https://github.com/chobits/ngx_http_proxy_connect_module)
- [nginx log module docs](https://nginx.org/en/docs/http/ngx_http_log_module.html)

---

*Testato su Ubuntu 26.04 LTS (Resolute Raccoon) con nginx 1.26.3 — Maggio 2026*
