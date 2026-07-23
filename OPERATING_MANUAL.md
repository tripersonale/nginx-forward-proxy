# OPERATING MANUAL — nginx forward proxy

Manuale operativo di riferimento. Dove stanno le cose, sintassi completa, come si modifica, esempi.

---

## 1. Dove sono le cose

```
/usr/local/nginx/sbin/nginx          ← Binario
/usr/local/nginx/conf/nginx.conf     ← Configurazione
/var/log/nginx/proxy_access.log      ← Log accessi (proxy)
/var/log/nginx/proxy_error.log       ← Log errori
/var/run/nginx.pid                   ← PID master process
/etc/systemd/system/nginx.service    ← Unit systemd
```

Comandi di servizio:

```bash
systemctl status nginx        # Stato
systemctl restart nginx       # Riavvia (interrompe connessioni)
systemctl reload nginx        # Ricarica config (senza downtime)
systemctl stop nginx          # Ferma
/usr/local/nginx/sbin/nginx -t # Test sintassi senza applicare
/usr/local/nginx/sbin/nginx -V # Versione e moduli compilati
```

---

## 2. Come si scrive — Sintassi di riferimento

### 2.1 Formato log

Definito nel blocco `http`:

```nginx
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
```

**Variabili disponibili** — tutto quello che puoi mettere nel log:

| Variabile | Cosa contiene | Esempio |
|-----------|--------------|---------|
| `$remote_addr` | IP del client | `192.168.89.55` |
| `$remote_user` | Utente autenticato (se auth_basic) | `-` |
| `$time_local` | Timestamp locale | `28/May/2026:11:11:31 +0000` |
| `$request` | Prima riga richiesta | `GET http://httpbin.org/ip HTTP/1.1` |
| `$status` | Codice HTTP risposta | `200`, `403`, `502` |
| `$body_bytes_sent` | Byte corpo risposta inviati | `45`, `4700` |
| `$http_referer` | Header Referer | `-` o `http://source.com` |
| `$http_user_agent` | Browser/curl user agent | `curl/8.5.0` |
| `$http_host` | **Hostname destinazione richiesto** | `httpbin.org` |
| `$upstream_addr` | **IP:porta risolto del server upstream (HTTP)** | `34.234.10.121:80` |
| `$connect_addr` | **IP:porta risolto per CONNECT (HTTPS)** | `140.82.121.3:443` |
| `$request_method` | GET, POST, CONNECT, HEAD | `CONNECT` |
| `$server_protocol` | Protocollo | `HTTP/1.1` |
| `$request_time` | Tempo totale richiesta (secondi) | `0.549` |
| `$upstream_connect_time` | Tempo connessione DNS+TCP upstream | `0.107` |
| `$upstream_header_time` | Tempo ricezione header upstream | `0.535` |
| `$request_length` | Dimensione richiesta (header+body) | `123` |
| `$bytes_sent` | Byte totali inviati al client | `500` |
| `$connection` | Numero progressivo connessione | `15` |
| `$server_addr` | IP del server proxy | `192.168.89.139` |
| `$server_port` | Porta del server proxy | `3128` |
| `$request_uri` | URI completo richiesto | `/ip` |
| `$scheme` | Schema della richiesta | `http` o `https` |
| `$ssl_cipher` | Cipher TLS (solo HTTPS) | `TLS_AES_256_GCM_SHA384` |
| `$ssl_protocol` | Versione TLS (solo HTTPS) | `TLSv1.3` |

**Perché** i due campi critici:
- `$upstream_addr`: per HTTP, mostra l'IP:porta dove nginx ha inoltrato la richiesta.
- `$connect_addr`: per HTTPS/CONNECT, mostra l'IP:porta risolto dal modulo proxy_connect prima del tunnel. **Disponibile solo dopo `proxy_connect;` nel blocco server.**

**Nota su CONNECT (HTTPS)**: per le richieste CONNECT, `$upstream_addr` è sempre `-` (il tunnel TCP non ha connessione HTTP upstream). `$connect_addr` invece contiene l'IP risolto (es. `140.82.121.3:443`).

> **🔒 Privacy e GDPR**: `$remote_addr` (IP client) e `$http_host` (hostname visitato) sono **dati personali**. Se operi in contesti soggetti a GDPR, NIS2 o D.Lgs 196, assicurati di: (1) base giuridica per il logging, (2) retention definita, (3) informare gli utenti che il traffico passa da un proxy che registra metadata.

### 2.2 Resolver DNS

```nginx
resolver <IP_DNS1> <IP_DNS2> ... valid=<secondi> ipv6=on|off;
resolver_timeout <secondi>;
```

**Esempi**:
```nginx
# Solo IPv4 (se la rete non ha IPv6)
resolver 1.1.1.1 8.8.8.8 valid=300s ipv6=off;

# Con IPv6 abilitato
resolver 1.1.1.1 8.8.8.8 valid=600s;

# DNS locale + pubblico come fallback
resolver 192.168.1.1 1.1.1.1 valid=300s;
```

**Perché `valid=300s`**: nginx tiene in cache i risultati DNS per 300 secondi. Dopo, se la richiesta arriva, ri-risolve. Bilancia performance (meno lookup DNS) con freschezza (massimo 5 min di cache stantia).

**Perché `ipv6=off`**: se il server non ha connettività IPv6, nginx proverebbe comunque a connettersi agli indirizzi IPv6 risolti e fallirebbe con `Network is unreachable`. Con `ipv6=off`, il resolver restituisce solo IPv4.

### 2.3 Controllo accessi (allow/deny)

```nginx
allow  <IP>;       # o subnet CIDR
deny   <IP>;       # o "all"
```

Le regole sono valutate **in ordine**. La prima che matcha decide.

**Esempi**:

```nginx
# Solo LAN — il caso base
allow  192.168.89.0/24;
deny   all;

# LAN + un IP specifico esterno
allow  192.168.89.0/24;
allow  203.0.113.42;
deny   all;

# Blocca un IP specifico dentro la LAN, permette il resto
deny   192.168.89.66;      # ← valutata prima!
allow  192.168.89.0/24;
deny   all;
```

**Perché l'ordine conta**: se scrivi `allow 192.168.89.0/24` e POI `deny 192.168.89.66`, il deny non verrà mai raggiunto perché `192.168.89.66` matcha già l'allow. Metti sempre i deny più specifici PRIMA degli allow più larghi.

**Log dei blocchi**: un IP bloccato riceve **403 Forbidden** e appare nel log con `$status` 403 e `rt=0.000` (nessuna latenza upstream, il blocco è istantaneo).

```
127.0.0.1 - [28/May/2026:11:27:13 +0000] "GET http://httpbin.org/ip HTTP/1.1" 403 ...
```

Nel error log appare:
```
access forbidden by rule, client: 127.0.0.1
```

### 2.4 proxy_connect (HTTPS)

```nginx
proxy_connect;                          # Attiva il modulo
proxy_connect_allow <porte>;            # Porte consentite per CONNECT
proxy_connect_connect_timeout <tempo>;  # Timeout connessione
proxy_connect_read_timeout <tempo>;     # Timeout lettura
proxy_connect_send_timeout <tempo>;     # Timeout scrittura
```

**Esempi**:

```nginx
# Solo HTTPS standard + NNTPS (563)
proxy_connect_allow 443 563;

# HTTPS + porte custom (test/dev)
proxy_connect_allow 443 8443 9443;

# Qualsiasi porta (⚠️ insicuro — permette tunnel verso qualsiasi servizio)
proxy_connect_allow all;
```

**Perché limitare le porte**: CONNECT è un tunnel TCP grezzo. Se permetti la porta 22, un client può fare SSH attraverso il proxy. Se permetti la porta 25, può inviare spam. Limitare a 443 garantisce che il tunnel venga usato solo per HTTPS.

### 2.5 proxy_pass (HTTP forward)

```nginx
proxy_pass $scheme://$http_host$request_uri;
proxy_set_header Host $http_host;
proxy_buffering on|off;
proxy_ssl_server_name on|off;
```

**Perché `proxy_pass` con variabili**: la sintassi speciale `$scheme://$http_host$request_uri` dice a nginx di costruire la URL di destinazione dinamicamente dal contenuto della richiesta del client. Questo è ciò che trasforma un reverse proxy in un forward proxy.

**Perché `proxy_ssl_server_name on`**: abilita SNI (Server Name Indication) verso l'upstream. Senza SNI, molti siti HTTPS moderni (ospitati su CDN con centinaia di domini sullo stesso IP) restituirebbero il certificato sbagliato o rifiuterebbero la connessione.

**Perché `proxy_buffering off`**: per un forward proxy, disabilitare il buffering significa che i dati fluiscono dal server di destinazione al client in tempo reale, senza accumularsi in memoria. Importante per streaming, download grandi, e per non consumare RAM del proxy.

---

## 3. Come si fa — Operazioni comuni

### 3.1 Cambiare la subnet autorizzata

Modifica queste due righe in `/usr/local/nginx/conf/nginx.conf`:

```nginx
# Nel blocco server { }
allow 192.168.1.0/24;    # ← cambia qui

# Nel firewall
ufw delete allow from 192.168.89.0/24 to any port 3128
ufw allow from 192.168.1.0/24 to any port 3128 proto tcp comment 'nginx proxy'
```

Poi:
```bash
nginx -t && systemctl reload nginx
```

**Perché sia nginx che UFW**: nginx applica il blocco a livello applicativo (HTTP 403). UFW lo applica a livello di rete (pacchetto scartato prima ancora di arrivare a nginx). Difesa in profondità.

### 3.2 Aggiungere più subnet

```nginx
allow 192.168.89.0/24;     # LAN principale
allow 10.0.0.0/24;         # VPN
allow 172.16.0.0/12;       # Ufficio remoto
deny all;                  # Tutto il resto bloccato
```

```bash
ufw allow from 10.0.0.0/24 to any port 3128 proto tcp comment 'proxy VPN'
ufw allow from 172.16.0.0/12 to any port 3128 proto tcp comment 'proxy ufficio'
nginx -t && systemctl reload nginx
```

### 3.3 Cambiare la porta di ascolto

In `/usr/local/nginx/conf/nginx.conf`:
```nginx
server {
    listen 8080;    # ← cambia da 3128 a 8080
```

```bash
ufw delete allow from 192.168.89.0/24 to any port 3128
ufw allow from 192.168.89.0/24 to any port 8080 proto tcp comment 'nginx proxy'
nginx -t && systemctl reload nginx
```

### 3.4 Aggiungere autenticazione (username/password)

```bash
# Installa htpasswd (viene da apache2-utils, non preinstallato)
apt-get install -y apache2-utils

# Crea file password (solo la prima volta con -c, dopo senza)
htpasswd -c /usr/local/nginx/conf/.htpasswd proxyuser
# Inserisci password due volte

# Per aggiungere altri utenti (SENZA -c, altrimenti sovrascrive il file)
htpasswd /usr/local/nginx/conf/.htpasswd altro-utente

# Aggiungi al blocco server { } in nginx.conf:
```

```nginx
server {
    listen 3128;

    auth_basic "Proxy authentication required";
    auth_basic_user_file /usr/local/nginx/conf/.htpasswd;

    allow 192.168.89.0/24;
    deny all;
    ...
}
```

```bash
nginx -t && systemctl reload nginx
```

Uso client:
```bash
curl -x http://proxyuser:password@192.168.89.139:3128 http://httpbin.org/ip
```

**Perché**: senza autenticazione, chiunque sulla LAN può usare il proxy. L'auth basic fornisce un layer minimo ma è in chiaro (base64). Per produzione seria, considera autenticazione tramite IP + TLS.

### 3.5 Ruotare i log (logrotate)

Crea `/etc/logrotate.d/nginx-proxy`:

```text
/var/log/nginx/proxy_access.log /var/log/nginx/proxy_error.log {
    daily
    rotate 90
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    postrotate
        [ -f /var/run/nginx.pid ] && kill -USR1 $(cat /var/run/nginx.pid)
    endscript
}
```

**Perché `kill -USR1`**: nginx riapre i file di log quando riceve il segnale USR1. Senza questo, continuerebbe a scrivere sul file vecchio (rinominato da logrotate).

### 3.6 Monitorare il proxy in tempo reale

```bash
# Richieste in arrivo
tail -f /var/log/nginx/proxy_access.log

# Solo errori
tail -f /var/log/nginx/proxy_error.log

# Statistiche: top 10 siti visitati
grep -oP 'host="\K[^"]+' /var/log/nginx/proxy_access.log | sort | uniq -c | sort -rn | head -10

# Statistiche: richieste per IP client
awk '{print $1}' /var/log/nginx/proxy_access.log | sort | uniq -c | sort -rn

# Quanti 403 (blocchi) oggi
grep " 403 " /var/log/nginx/proxy_access.log | wc -l

# Traffico totale in byte
awk '{sum += $10} END {print sum " bytes"}' /var/log/nginx/proxy_access.log
```

### 3.7 Vedere lo stato nginx

```bash
# Stato base
systemctl status nginx

# Connessioni attive
ss -tnp | grep nginx

# Processi
ps aux | grep nginx
```

### 3.8 Testare la configurazione prima di applicare

```bash
/usr/local/nginx/sbin/nginx -t
```

Se dice `syntax is ok` e `test is successful`, puoi fare `systemctl reload nginx`.
Se dà errore, NON fare reload finché l'errore non è risolto, altrimenti nginx smette di funzionare.

---

## 4. Esempi di sintassi — Leggere i log

### 4.1 Richiesta HTTP autorizzata

```
192.168.89.55 - [28/May/2026:11:11:31 +0000] "GET http://httpbin.org/ip HTTP/1.1" 200 45 "-" "curl/8.5.0" host="httpbin.org" upstream="34.234.10.121:80" method="GET" proto="HTTP/1.1" rt=0.549 uct=0.107 uht=0.535
```

| Campo | Valore | Significato |
|-------|--------|-------------|
| client | `192.168.89.55` | Chi ha fatto la richiesta |
| timestamp | `28/May/2026:11:11:31 +0000` | Quando |
| request | `GET http://httpbin.org/ip HTTP/1.1` | Cosa ha chiesto |
| status | `200` | OK |
| size | `45` byte | Risposta JSON: `{"origin": "x.x.x.x"}` |
| user_agent | `curl/8.5.0` | Chi/cosa ha fatto la richiesta |
| **host** | `httpbin.org` | **Hostname destinazione** |
| **upstream** | `34.234.10.121:80` | **IP:porta risolto** — qui è andata la connessione |
| method | `GET` | Metodo HTTP |
| proto | `HTTP/1.1` | Protocollo |
| rt | `0.549s` | Tempo totale (DNS + TCP + TLS + risposta) |
| uct | `0.107s` | Solo DNS + TCP verso upstream |
| uht | `0.535s` | Tempo per ricevere gli header di risposta |

### 4.2 Richiesta HTTPS (CONNECT) autorizzata

```
192.168.89.55 - [28/May/2026:11:11:50 +0000] "CONNECT github.com:443 HTTP/1.1" 200 587712 "-" "curl/8.5.0" host="github.com:443" upstream="-" connect_addr="140.82.121.3:443" method="CONNECT" proto="HTTP/1.1" rt=0.350 uct=- uht=-
```

| Campo | Valore | Significato |
|-------|--------|-------------|
| request | `CONNECT github.com:443` | Apertura tunnel |
| status | `200` | Tunnel stabilito |
| size | `587712` | Byte scambiati nel tunnel |
| **host** | `github.com:443` | **Hostname destinazione** |
| upstream | `-` | Normale per CONNECT (nessuna connessione HTTP upstream) |
| **connect_addr** | `140.82.121.3:443` | **IP:porta RISOLTO dal modulo proxy_connect** |
| rt | `0.350s` | Il tunnel è stato stabilito in 350ms |
| uct | `-` | Non applicabile per CONNECT |

### 4.3 Richiesta bloccata

```
127.0.0.1 - [28/May/2026:11:27:13 +0000] "GET http://httpbin.org/ip HTTP/1.1" 403 153 "-" "curl/8.18.0" host="httpbin.org" upstream="-" method="GET" proto="HTTP/1.1" rt=0.000 uct=- uht=-
```

| Campo | Valore | Significato |
|-------|--------|-------------|
| client | `127.0.0.1` | IP non autorizzato |
| status | `403` | **Forbidden** — bloccato da `allow/deny` |
| **upstream** | `-` | Mai connesso al server destinazione |
| rt | `0.000` | Risposta istantanea (blocco locale, nessuna latenza di rete) |
| uct/uht | `-` | Non applicabile |

L'error log corrispondente:
```
2026/05/28 11:27:13 [error] 13549#0: *15 access forbidden by rule, client: 127.0.0.1, server: _, request: "GET http://httpbin.org/ip HTTP/1.1", host: "httpbin.org"
```

### 4.4 Errore di connettività (esempio: IPv6 non disponibile)

```
192.168.89.55 - [28/May/2026:11:10:53 +0000] "CONNECT www.google.com:443 HTTP/1.1" 502 157 "-" "curl/8.5.0" host="www.google.com:443" upstream="-" method="CONNECT" proto="HTTP/1.1" rt=0.004 uct=- uht=-
```

| Campo | Valore | Significato |
|-------|--------|-------------|
| status | `502` | Bad Gateway — nginx non è riuscito a connettersi all'upstream |
| rt | `0.004s` | Il fallimento è stato quasi istantaneo |
| host | `www.google.com:443` | Destinazione visibile nonostante il fallimento |

Correlato error log:
```
connect() to [2a00:1450:4002:408::200e]:443 failed (101: Network is unreachable)
```

**Soluzione**: `resolver ... ipv6=off;`

---

## 5. Configurazioni alternative

### 5.1 Proxy con whitelist di domini

Permetti solo domini specifici:

```nginx
server {
    listen 3128;

    # Nega domini non autorizzati PRIMA di proxy_pass
    if ($http_host !~* ^(httpbin\.org|google\.com|github\.com)$) {
        return 403;
    }

    location / {
        proxy_pass $scheme://$http_host$request_uri;
        proxy_set_header Host $http_host;
        ...
    }
}
```

### 5.2 Proxy su più porte

```nginx
server {
    listen 3128;    # Standard
    listen 8080;    # Alternativa
    ...
}
```

### 5.3 Rate limiting

Limita il numero di richieste per IP:

```nginx
http {
    limit_req_zone $binary_remote_addr zone=proxy_limit:10m rate=30r/m;

    server {
        listen 3128;

        limit_req zone=proxy_limit burst=10 nodelay;
        ...
    }
}
```

**Perché**: `rate=30r/m` significa 30 richieste al minuto per IP. `burst=10` permette picchi di 10 richieste sopra il rate. Se un client supera il burst, riceve 503.

---

## 6. Checklist manutenzione periodica

> Per il monitoring CVE strutturato (nginx advisories, OpenSSL, module fork,
> Ubuntu USN), vedi [`CVE_MONITORING.md`](./CVE_MONITORING.md).
> Per l'upgrade del binario senza perdita dati, vedi [`UPGRADE.md`](./UPGRADE.md).

```bash
# Ogni giorno
tail -20 /var/log/nginx/proxy_error.log        # Errori recenti
grep ' 403 ' /var/log/nginx/proxy_access.log | tail -10  # Blocchi

# Ogni settimana
df -h /var/log                                  # Spazio disco
du -sh /var/log/nginx/                          # Dimensione log
systemctl status nginx                          # Servizio attivo
# + check nginx security advisories (https://nginx.org/en/security_advisories.html)

# Ogni mese
logrotate -f /etc/logrotate.d/nginx-proxy       # Forza rotazione log
/usr/local/nginx/sbin/nginx -t                  # Config ancora valida
apt-get update && apt-get upgrade               # Patch sicurezza OS
/usr/local/nginx/sbin/nginx -V 2>&1 | head -1   # Verifica versione nginx
ubuntu-security-status                          # CVE sui pacchetti Ubuntu
```

---

## 7. Riferimenti comandi rapidi

```bash
# Status
systemctl status nginx
ss -tlnp | grep 3128

# Ricarica
nginx -t && systemctl reload nginx

# Log
tail -f /var/log/nginx/proxy_access.log
tail -f /var/log/nginx/proxy_error.log

# Statistiche
awk '{print $1}' /var/log/nginx/proxy_access.log | sort | uniq -c | sort -rn     # Top client
grep ' 403 ' /var/log/nginx/proxy_access.log | wc -l                              # Blocchi
grep -oP 'host="\K[^"]+' /var/log/nginx/proxy_access.log | sort | uniq -c | sort -rn | head  # Top host

# Rotazione
logrotate -f /etc/logrotate.d/nginx-proxy

# Test
curl -x http://192.168.89.139:3128 http://httpbin.org/ip
curl -x http://192.168.89.139:3128 https://httpbin.org/ip
```

---

## 8. Errori comuni e soluzioni

### SSH lockout dopo `ufw --force enable`

**Sintomo**: dopo aver eseguito `ufw --force enable`, la connessione SSH cade e non si riesce più a entrare.

**Causa**: La subnet nelle regole UFW (Step 11 del README) non include l'IP da cui ti stai connettendo. UFW blocca il traffico in entrata e la tua nuova connessione SSH viene scartata.

**Esempio**: la guida usa `192.168.89.0/24` come subnet di esempio, ma la tua macchina è su `192.168.122.0/24`. UFW permette SSH solo da `192.168.89.0/24`, quindi la tua connessione da `192.168.122.1` viene bloccata.

**Soluzione preventiva** (consigliata):
Prima di eseguire `ufw --force enable`, verifica la tua subnet:
```bash
ip -o addr show | grep -v 127.0.0.1 | grep 'inet ' | awk '{print $4}'
```
Usa SOLO quella subnet nelle regole UFW, non quella della guida.

**Soluzione di recovery** (se già bloccato):
1. Accedi alla console fisica / virtuale della macchina (IPMI, iLO, VM console, Proxmox console)
2. `sudo ufw disable`
3. Verifica la subnet corretta
4. Riapplica le regole con la subnet giusta

### `gcc` output non corrisponde esattamente

**Sintomo**: il comando `gcc --version` mostra una versione leggermente diversa (es. `15.2.0-16ubuntu1` invece di `15.2.0`).

**Causa**: aggiornamenti di pacchetto. La guida è stata testata con una revisione specifica.

**Soluzione**: è normale. Finché vedi `gcc (Ubuntu 15.x.x...)` e il numero di versione inizia con `15`, sei a posto.

---

## 9. Limiti noti

| Limite | Impatto | Mitigazione |
|--------|---------|-------------|
| $connect_addr funziona solo se proxy_connect è dichiarato nel server block | HTTPS senza CONNECT non logga IP risolto | Assicurarsi che `proxy_connect;` sia presente (Step 9) |
| CONNECT supporta solo HTTP/1.x, non HTTP/2 | Connessioni HTTP/2 verso il proxy sono downgradate | Non mitigabile — limitazione del modulo |
| Auth basic in chiaro (base64) | Credenziali visibili a chi intercetta il traffico LAN | Usare solo su rete fidata; per produzione, aggiungere TLS al proxy |
| WebSocket non testato | Potrebbe non funzionare in tutti i casi | Aprire una issue su GitHub se necessario |
| Rate limiting non attivo per default | Un client può saturare il proxy | Seguire §5.3 per configurare `limit_req_zone` |
| Nessun monitoring/alerting | Non ci sono notifiche se il proxy smette di funzionare | Abbinare a strumenti esterni (Uptime Kuma, Prometheus + Blackbox Exporter) |
| Nessuna cifratura a riposo per i log | I log contengono IP in chiaro sul disco | Crittografia a livello di filesystem (LUKS) o retention aggressiva |
| $remote_addr loggato = dato personale GDPR | Necessaria base giuridica per il trattamento | Vedi nota privacy §2.1 |

---

*Manuale operativo — nginx forward proxy — Maggio 2026*
