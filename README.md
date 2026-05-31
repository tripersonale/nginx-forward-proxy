# nginx forward proxy — Manuale di installazione

**Stile IKEA**: ogni step mostra il comando, l'output atteso, e come verificare che sia ok. Zero assunzioni.

---

## Cosa stai per costruire

```
Il tuo PC ──► nginx proxy (:3128) ──► Internet
  (LAN)          (questa guida)      (siti web)

Ogni richiesta che passa dal proxy viene LOGGATA con:
  → IP del client (chi ha chiesto)
  → hostname destinazione (cosa ha chiesto)
  → IP risolto del server (dove è andata la connessione)
  → tempo impiegato
```

---

## Prima di cominciare

### 🧰 Cosa ti serve

| Cosa | Dettaglio |
|------|-----------|
| Un computer con Ubuntu 26.04 | Fisico o virtuale (almeno 2 GB RAM, 10 GB disco) |
| Accesso a Internet | Per scaricare pacchetti e sorgenti |
| Tastiera e schermo | O SSH, va bene lo stesso |
| Essere **root** | Se non sai cosa significa: `sudo -i` e inserisci la password |

### ⏱️ Tempo totale

Circa **15-20 minuti** (dipende dalla velocità della CPU per la compilazione).

### 📖 Come leggere questa guida

| Simbolo | Significato |
|---------|-------------|
| 📋 | Comando da copiare e incollare |
| 📺 | Cosa DEVI vedere sullo schermo dopo aver eseguito il comando |
| ✅ | Come sapere che è andato tutto bene |
| ❌ | Cosa fare se vedi qualcosa di diverso (vai alla sezione Troubleshooting) |
| ⏱️ | Quanto tempo ci vuole |

---

## STEP 1 — Diventa root

⏱️ Tempo: **5 secondi**

### 📋 Comando

```bash
sudo -i
```

Inserisci la tua password quando richiesto.

### 📺 Output atteso

Il prompt del terminale cambia. Prima era tipo `tuo-utente@macchina:~$`, ora diventa:

```
root@macchina:~#
```

Il simbolo `#` invece di `$` conferma che sei root.

### ✅ Checkpoint

Scrivi `whoami` e premi Invio. Se appare `root`, sei a posto.

```
root@macchina:~# whoami
root
```

---

## STEP 2 — Installa gli ingredienti (dipendenze)

⏱️ Tempo: **2-3 minuti**

Tutto quello che serve per compilare nginx da zero.

### 📋 Comando

```bash
apt-get update
```

Poi (in un secondo comando):

```bash
apt-get install -y build-essential libpcre2-dev libssl-dev zlib1g-dev libcrypt-dev git wget curl ufw
```

### 📺 Output atteso

Dopo `apt-get update`, le ultime righe dicono:

```
Reading package lists... Done
```

Dopo `apt-get install`, l'ultima riga DEVE essere:

```
0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
```

(Se è la prima volta che installi questi pacchetti, vedrai `X newly installed` invece di `0` — è normale.)

### 🏷️ Cosa stai installando (non serve saperlo, ma se sei curioso)

| Pacchetto | A cosa serve |
|-----------|-------------|
| `build-essential` | Compilatore C (gcc) e tool per costruire software |
| `libpcre2-dev` | Libreria per le espressioni regolari (nginx la usa per i rewrite) |
| `libssl-dev` | OpenSSL, per le connessioni HTTPS |
| `zlib1g-dev` | Compressione (nginx la usa per comprimere le risposte) |
| `libcrypt-dev` | Funzioni di crittografia (su Ubuntu 26.04 è separato) |
| `git` | Per scaricare il modulo proxy_connect da GitHub |
| `wget` | Per scaricare nginx |
| `curl` | Per testare il proxy alla fine |
| `ufw` | Firewall |

### ✅ Checkpoint

```bash
gcc --version
```

Deve mostrare `gcc (Ubuntu 15.2.0...)`. Se vedi `command not found`, hai saltato `build-essential`. Torna indietro.

### ❌ Se fallisce

- `E: Unable to locate package libpcre3-dev` → Su Ubuntu 26.04 il pacchetto si chiama `libpcre2-dev`, non `libpcre3-dev`. Sei sicuro di aver copiato il comando giusto?
- `E: Could not get lock /var/lib/dpkg/lock-frontend` → C'è un altro processo che sta usando apt (tipicamente cloud-init che sta finendo l'installazione). Aspetta 2-3 minuti e riprova. Per verificare se è finito: `sudo fuser /var/lib/dpkg/lock-frontend` — se non produce output, sei libero di procedere.

---

## STEP 3 — Scarica nginx

⏱️ Tempo: **30 secondi**

### 📋 Comando

```bash
mkdir -p /tmp/nginx-build && cd /tmp/nginx-build
wget https://nginx.org/download/nginx-1.26.3.tar.gz
tar xzf nginx-1.26.3.tar.gz
```

### 📺 Output atteso

`wget` mostra una barra di progresso:

```
nginx-1.26.3.tar.gz  100%[===================>]   1.23M  --.-KB/s    in 0.1s
```

`tar` non produce output (nessuna notizia = buona notizia).

### ✅ Checkpoint

```bash
ls nginx-1.26.3/
```

Deve mostrare file come `configure`, `src`, `conf`, ecc. Se vedi `No such file or directory`, qualcosa è andato storto nel download o nell'estrazione.

---

## STEP 4 — Scarica il modulo proxy_connect

⏱️ Tempo: **10 secondi**

Questo modulo aggiunge a nginx il metodo CONNECT, indispensabile per il proxy HTTPS.

### 📋 Comando

```bash
git clone https://github.com/chobits/ngx_http_proxy_connect_module.git
```

### 📺 Output atteso

```
Cloning into 'ngx_http_proxy_connect_module'...
remote: Enumerating objects: XXX, done.
remote: Total XXX (delta 0), reused XXX (delta 0), pack-reused XXX
Receiving objects: 100% (XXX/XXX), done.
```

### ✅ Checkpoint

```bash
ls ngx_http_proxy_connect_module/patch/
```

Deve mostrare file che iniziano con `proxy_connect_rewrite_`. Se la cartella è vuota, il clone è fallito — controlla la connessione Internet.

---

## STEP 5 — Prepara e configura nginx

⏱️ Tempo: **30 secondi**

### 📋 Comandi (copiare TUTTO INSIEME)

```bash
cd nginx-1.26.3

patch -p1 < ../ngx_http_proxy_connect_module/patch/proxy_connect_rewrite_102101.patch

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

### 📺 Output atteso

`patch` produce:

```
patching file src/http/ngx_http_core_module.c
patching file src/http/ngx_http_parse.c
patching file src/http/ngx_http_request.c
patching file src/http/ngx_http_request.h
patching file src/http/ngx_http_variables.c
```

`./configure` produce molte righe di check. Le ultime DEVONO essere:

```
Configuration summary
  + using system PCRE2 library
  + using system OpenSSL library
  + using system zlib library

  nginx path prefix: "/usr/local/nginx"
  nginx binary file: "/usr/local/nginx/sbin/nginx"
```

### 🏷️ Cosa significa ogni flag

| Flag | Perché serve |
|------|-------------|
| `--prefix=` | Dove verrà installato nginx |
| `--with-http_ssl_module` | HTTPS sì/no. Senza questo, niente siti https. |
| `--add-module=../ngx_http_proxy_connect_module` | **IL PEZZO FONDAMENTALE** — il metodo CONNECT per proxy HTTPS |
| `--with-cc-opt='-Wno-error...'` | Necessario su Ubuntu 26.04 perché il compilatore è più severo |

### ✅ Checkpoint

```bash
ls objs/Makefile
```

Deve esistere. Se vedi `No such file or directory`, `./configure` è fallito.

### ❌ Se fallisce

- `patch: **** malformed patch` → stai usando la versione sbagliata di nginx. Questa guida funziona con nginx 1.26.3. Controlla di aver scaricato la versione giusta allo Step 3.
- `./configure: error: the HTTP rewrite module requires the PCRE library` → ti manca `libpcre2-dev`. Torna allo Step 2.
- `fatal error: crypt.h: No such file or directory` → ti manca `libcrypt-dev`. Torna allo Step 2.
- Se vedi altri errori, vai a §Troubleshooting in fondo alla guida.

---

## STEP 6 — Compila nginx

⏱️ Tempo: **2-5 minuti** (dipende dalla CPU)

### 📋 Comando

```bash
make -j$(nproc)
```

`$(nproc)` dice "usa tutti i core del processore". Su una macchina con 2 core, ci mette ~4 minuti. Con 4 core, ~2 minuti.

### 📺 Output atteso

L'output inizia con:

```
make -f objs/Makefile
make[1]: Entering directory '/root/build/nginx-1.26.3'
cc -c ... -o objs/src/core/nginx.o src/core/nginx.c
cc -c ... -o objs/src/core/ngx_log.o src/core/ngx_log.c
```

(segue una lunga lista di `cc -c ...` per ogni file sorgente)

Finisce con:

```
cc -o objs/nginx \
objs/src/core/nginx.o \
... (tanti file .o) ...
-lcrypt -lpcre2-8 -lssl -lcrypto -lz \
-Wl,-E
make[1]: Leaving directory '/root/build/nginx-1.26.3'
```

### ✅ Checkpoint

```bash
ls -la objs/nginx
```

Deve mostrare un file eseguibile (`-rwxr-xr-x`). Se il file non esiste, la compilazione è fallita.

### ❌ Se fallisce

- `make: *** [objs/src/http/v2/ngx_http_v2_filter_module.o] Error 1` → GCC 15 su Ubuntu 26.04 è più severo. Torna allo Step 5 e assicurati di aver incluso `--with-cc-opt='-Wno-error=unterminated-string-initialization'` nel comando `./configure`.
- `fatal error: crypt.h: No such file or directory` → `libcrypt-dev` non installato. `apt-get install -y libcrypt-dev` e poi rifai `make`.

---

## STEP 7 — Installa nginx

⏱️ Tempo: **10 secondi**

### 📋 Comando

```bash
make install
```

### 📺 Output atteso

Una serie di `test -d` e `cp`:

```
make -f objs/Makefile install
make[1]: Entering directory
test -d '/usr/local/nginx' || mkdir -p '/usr/local/nginx'
test -d '/usr/local/nginx/sbin' || mkdir -p '/usr/local/nginx/sbin'
cp objs/nginx '/usr/local/nginx/sbin/nginx'
test -d '/usr/local/nginx/conf' || mkdir -p '/usr/local/nginx/conf'
cp conf/koi-win '/usr/local/nginx/conf'
... (continua con altri file) ...
make[1]: Leaving directory
```

### ✅ Checkpoint

```bash
/usr/local/nginx/sbin/nginx -V
```

Deve mostrare (le righe importanti):

```
nginx version: nginx/1.26.3
built with OpenSSL 3.5.5 27 Jan 2026
TLS SNI support enabled
configure arguments: ... --add-module=../ngx_http_proxy_connect_module ...
```

Se vedi `nginx version: nginx/1.26.3` e `--add-module=../ngx_http_proxy_connect_module`, tutto ok.

### ❌ Se fallisce

- `/usr/local/nginx/sbin/nginx: No such file or directory` → `make install` non ha funzionato. Controlla l'output di `make install` per errori. Possibile causa: non sei root.

---

## STEP 8 — Crea la cartella dei log

⏱️ Tempo: **5 secondi**

### 📋 Comando

```bash
mkdir -p /var/log/nginx
chown nobody:nogroup /var/log/nginx
```

(Se il secondo comando dà errore `nogroup`: invalid group`, prova: `chown nobody:root /var/log/nginx`)

### 📺 Output atteso

Nessun output = tutto ok.

### ✅ Checkpoint

```bash
ls -ld /var/log/nginx
```

Deve mostrare:

```
drwxr-xr-x 2 nobody nogroup 4096 May 28 11:10 /var/log/nginx
```

---

## STEP 9 — Scrivi la configurazione

⏱️ Tempo: **30 secondi**

### 📋 Comando (copia TUTTO il blocco, da `cat` fino a `EOF` incluso)

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

    log_format forward_proxy '$remote_addr $remote_user [$time_local] '
                             '"$request" $status $body_bytes_sent '
                             '"$http_referer" "$http_user_agent" '
                             'host="$http_host" '
                             'upstream="$upstream_addr" '
                             'connect_addr="$connect_addr" '
                             'method="$request_method" '
                             'proto="$server_protocol" '
                             'rt=$request_time '
                             'uct=$upstream_connect_time '
                             'uht=$upstream_header_time';

    access_log  /var/log/nginx/proxy_access.log  forward_proxy buffer=32k flush=5s;

    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;
    keepalive_timeout  65;
    types_hash_max_size 2048;

    resolver 1.1.1.1 8.8.8.8 valid=300s ipv6=off;
    resolver_timeout 10s;

    server {
        listen 3128;
        server_name _;

        allow 192.168.89.0/24;
        deny all;

        proxy_connect;
        proxy_connect_allow            443 563;
        proxy_connect_connect_timeout  30s;
        proxy_connect_read_timeout     60s;
        proxy_connect_send_timeout     60s;

        location / {
            proxy_pass $scheme://$http_host$request_uri;
            proxy_set_header Host $http_host;
            proxy_buffering off;
            proxy_ssl_server_name on;

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

### 📺 Output atteso

Nessun output. Il comando `cat > file << 'EOF'` scrive tutto quello che c'è tra `<< 'EOF'` e `EOF` nel file. Se non vedi errori, ha funzionato.

### ⚠️ Importante

La riga `allow 192.168.89.0/24;` significa "permetti solo ai computer della rete 192.168.89.x". **Devi cambiarla** con la tua rete! Se non sai qual è la tua rete, salta questo warning per ora — limiterai l'accesso dopo.

### ✅ Checkpoint

```bash
/usr/local/nginx/sbin/nginx -t
```

Deve rispondere ESATTAMENTE:

```
nginx: the configuration file /usr/local/nginx/conf/nginx.conf syntax is ok
nginx: configuration file /usr/local/nginx/conf/nginx.conf test is successful
```

Se vedi `syntax is ok` e `test is successful`, la configurazione è valida.

### ❌ Se fallisce

- `nginx: [emerg] "proxy_connect" directive is not allowed here` → il modulo proxy_connect non è stato compilato. Torna allo Step 5 e verifica che `./configure` includa `--add-module=../ngx_http_proxy_connect_module`.
- `nginx: [emerg] unknown "nogroup" group` → cambia la prima riga del file in `user  nobody root;`. Riscrivi il file da `cat >` e riprova `nginx -t`.

---

## STEP 10 — Crea il servizio systemd

⏱️ Tempo: **30 secondi**

Questo fa sì che nginx parta automaticamente all'avvio del computer.

### 📋 Comando (copia TUTTO il blocco)

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

### 📺 Output atteso

Nessun output = ok.

### ✅ Checkpoint

```bash
cat /etc/systemd/system/nginx.service
```

Deve mostrare il contenuto del file che hai appena scritto. Se il file è vuoto, non hai copiato tutto.

---

## STEP 11 — Configura il firewall

⏱️ Tempo: **20 secondi**

### 📋 Comandi (uno alla volta)

```bash
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow from 192.168.89.0/24 to any port 22 proto tcp comment 'SSH'
ufw allow from 192.168.89.0/24 to any port 3128 proto tcp comment 'nginx proxy'
```

### 📺 Output atteso

```
Firewall is active and enabled on system startup
Default incoming policy changed to 'deny'
Default outgoing policy changed to 'allow'
Rule added
Rule added
```

### ⚠️ Importante

La subnet `192.168.89.0/24` negli ultimi due comandi DEVE corrispondere a quella nel file di configurazione (Step 9). Se usi una rete diversa, cambiala in entrambi i posti.

### ✅ Checkpoint

```bash
ufw status
```

Deve mostrare:

```
Status: active

To          Action      From
--          ------      ----
22/tcp      ALLOW       192.168.89.0/24    # SSH
3128/tcp    ALLOW       192.168.89.0/24    # nginx proxy
```

---

## STEP 12 — Avvia il servizio

⏱️ Tempo: **10 secondi**

### 📋 Comandi

```bash
systemctl daemon-reload
systemctl enable nginx
systemctl start nginx
```

### 📺 Output atteso

Dopo `systemctl enable nginx`:

```
Created symlink /etc/systemd/system/multi-user.target.wants/nginx.service → /etc/systemd/system/nginx.service.
```

Dopo `systemctl start nginx`: nessun output.

### ✅ Checkpoint

```bash
systemctl status nginx
```

Le prime righe DEVONO mostrare:

```
● nginx.service - nginx forward proxy con proxy_connect module
     Loaded: loaded (/etc/systemd/system/nginx.service; enabled; ...)
     Active: active (running) since ...
```

Le tre parole chiave sono: **loaded**, **enabled**, **active (running)**.

```bash
ss -tlnp | grep 3128
```

Deve mostrare:

```
LISTEN 0  511  0.0.0.0:3128  0.0.0.0:*  users:(("nginx",pid=...,fd=6))
```

La parola chiave è **LISTEN**. Significa che nginx è in ascolto sulla porta 3128.

### ❌ Se fallisce

- `systemctl: command not found` → sei su un sistema senza systemd? (molto raro). Contatta un amico sysadmin.
- `Active: failed` → la configurazione ha errori. Esegui `/usr/local/nginx/sbin/nginx -t` per vedere cosa non va.
- `nginx: [emerg] bind() to 0.0.0.0:3128 failed (98: Address already in use)` → la porta 3128 è già occupata. Controlla con `ss -tlnp | grep 3128` chi la sta usando.

---

## Test — Verifica che funzioni

Se sei arrivato fin qui, il proxy è installato. Ora verifichiamo che faccia il suo lavoro.

### Test 1: HTTP

```bash
curl -x http://localhost:3128 -v http://example.com
```

📺 Output atteso:

```
* Connected to localhost (127.0.0.1) port 3128
> GET http://example.com HTTP/1.1
> Host: example.com
...
< HTTP/1.1 200 OK
< Server: nginx/1.26.3
...
<!doctype html>...Example Domain...
```

Vedi `200 OK` e il contenuto HTML di example.com? ✅ Funziona.

### Test 2: HTTPS

```bash
curl -x http://localhost:3128 -v https://www.google.com
```

📺 Output atteso:

```
> CONNECT www.google.com:443 HTTP/1.1
...
< HTTP/1.1 200 Connection established
...
< HTTP/2 200
```

Vedi `200 Connection established`? ✅ Anche HTTPS funziona.

### Test 3: Blocco IP non autorizzato

```bash
curl -x http://127.0.0.1:3128 http://httpbin.org/ip
```

📺 Output atteso:

```
<html>
<head><title>403 Forbidden</title></head>
...
```

Vedi `403 Forbidden`? ✅ Il blocco funziona (127.0.0.1 non è nella tua LAN).

### Test 4: Controlla i log

```bash
tail -5 /var/log/nginx/proxy_access.log
```

📺 Output atteso (esempio):

```
192.168.89.x - [31/May/2026:...] "GET http://httpbin.org/ip HTTP/1.1" 200 45 ... host="httpbin.org" upstream="34.234.10.121:80" ... rt=0.549 uct=0.107
```

Il campo `upstream="34.234.10.121:80"` è l'IP risolto del server di destinazione. Questo è il motivo per cui abbiamo fatto tutto questo lavoro.

---

## 🧪 check.sh — Verifica automatica

Invece di fare i test a mano, esegui:

```bash
bash check.sh
```

Questo script verifica automaticamente:

- [x] nginx installato e raggiungibile
- [x] Configurazione valida (`nginx -t`)
- [x] Porta 3128 in ascolto
- [x] Proxy HTTP funzionante
- [x] Proxy HTTPS (CONNECT) funzionante
- [x] Blocco IP non autorizzati
- [x] Firewall UFW attivo
- [x] Servizio systemd attivo
- [x] Logrotate configurato (90 giorni retention)
- [x] Logging completo (sorgente, FQDN, IP risolto HTTP e HTTPS)

Ogni test mostra ✅ o ❌.

---

## Comandi quotidiani

```bash
# Riavvia dopo una modifica alla configurazione
systemctl restart nginx

# Vedi i log in diretta
tail -f /var/log/nginx/proxy_access.log

# Vedi gli errori
tail -f /var/log/nginx/proxy_error.log

# Conta i siti più visitati
grep -oP 'host="\K[^"]+' /var/log/nginx/proxy_access.log | sort | uniq -c | sort -rn | head

# Quanti accessi bloccati oggi?
grep ' 403 ' /var/log/nginx/proxy_access.log | wc -l
```

---

## Troubleshooting

### `connect() to [2a00:...]:443 failed (101: Network is unreachable)`

nginx sta provando a usare IPv6 ma il tuo server non ha IPv6.

📋 Soluzione: nel file `/usr/local/nginx/conf/nginx.conf`, aggiungi `ipv6=off` al resolver:

```
resolver 1.1.1.1 8.8.8.8 valid=300s ipv6=off;
```

Poi: `systemctl reload nginx`

### `patch: **** malformed patch at line X`

La patch non corrisponde alla versione di nginx.

📋 Soluzione: assicurati di aver scaricato **nginx 1.26.3** esattamente. Versioni diverse richiedono patch diverse. Controlla: https://github.com/chobits/ngx_http_proxy_connect_module#version-compatibility

### `make: *** [...] Error 1` (errore HTTP/2 module)

Su Ubuntu 26.04, GCC 15 è più severo.

📋 Soluzione: ri-esegui `./configure` con il flag aggiuntivo `--with-cc-opt='-Wno-error=unterminated-string-initialization'` (Step 5).

### `fatal error: crypt.h: No such file or directory`

📋 Soluzione: `apt-get install -y libcrypt-dev`, poi `make clean && make -j$(nproc) && make install`

### `E: Package 'libpcre3-dev' has no installation candidate`

Ubuntu 26.04 ha rimosso PCRE1.

📋 Soluzione: usa `libpcre2-dev` (è già nel comando allo Step 2. Se stai seguendo una guida vecchia, sostituisci `libpcre3-dev` con `libpcre2-dev`).

### `nginx: [emerg] unknown "nogroup" group`

Il gruppo `nogroup` non esiste sul tuo sistema.

📋 Soluzione: nel file di configurazione, cambia `user nobody nogroup;` in `user nobody root;`. Poi `nginx -t && systemctl reload nginx`.

### `htpasswd: command not found` (solo se usi l'auth)

📋 Soluzione: `apt-get install -y apache2-utils`

---

## Rimozione completa

Se vuoi disinstallare tutto:

```bash
systemctl stop nginx
systemctl disable nginx
rm -f /etc/systemd/system/nginx.service
rm -rf /usr/local/nginx
rm -rf /var/log/nginx
systemctl daemon-reload
```

---

*Istruzioni valide per: Ubuntu 26.04 LTS (Resolute Raccoon), nginx 1.26.3, ngx_http_proxy_connect_module.*
*Ultimo test: Maggio 2026.*
