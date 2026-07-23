# UPGRADE — Aggiornare un deploy esistente

Manuale rapido per aggiornare un proxy **già in produzione** dalla
versione 1.0.x (nginx 1.26.3) alla versione 1.1.x (nginx 1.30.4)
**senza perdita di dati e senza perdita di configurazione**.

> ⚠️ **Prima di iniziare**: leggi tutto. L'upgrade richiede ~10 minuti
> di downtime. Tutti i passaggi sono reversibili (rollback incluso).

---

## 0. Quando fare questo upgrade

| Scenario | Azione |
|----------|--------|
| Deploy fresco da zero | **Ignora questo file**. Segui direttamente `README.md` (installa già la 1.30.4) |
| Deploy esistente su 1.26.3 | **Procedi con questa guida** |
| Deploy esistente su 1.27.x/1.28.x | Procedi come 1.26.3, stessa procedura |
| Deploy esistente su 1.24.x o precedente | Prima passa a 1.26.3 con la vecchia guida, poi a 1.30.4 |

---

## 1. Cosa NON viene toccato (zero perdita di dati)

L'upgrade riguarda **solo il binario nginx**. Tutto il resto resta intatto:

| Asset | Path | Stato dopo upgrade |
|-------|------|-------------------|
| Configurazione | `/usr/local/nginx/conf/nginx.conf` | ✅ Invariata |
| Log accessi | `/var/log/nginx/proxy_access.log` | ✅ Preservato |
| Log errori | `/var/log/nginx/proxy_error.log` | ✅ Preservato |
| PID file | `/var/run/nginx.pid` | ✅ Ricreato al restart |
| Unit systemd | `/etc/systemd/system/nginx.service` | ✅ Invariata |
| Logrotate | `/etc/logrotate.d/nginx-proxy` | ✅ Invariato |
| Firewall UFW | regole 3128 + 22 | ✅ Invariate |

L'unico file sovrascritto è `/usr/local/nginx/sbin/nginx` (il binario).

---

## 2. Prerequisiti

```bash
# Verifica versione corrente (DEVE essere < 1.30.0)
/usr/local/nginx/sbin/nginx -V 2>&1 | head -1

# Verifica spazio disco (almeno 200 MB liberi in /tmp)
df -h /tmp

# Verifica che il proxy sia UP e记logghi
systemctl status nginx --no-pager
tail -5 /var/log/nginx/proxy_access.log
```

Se la versione attuale è già ≥ 1.30.0, **non serve upgrade**.

---

## 3. Backup di sicurezza (2 minuti)

```bash
# Backup binario corrente (per rollback rapido)
cp -a /usr/local/nginx/sbin/nginx /usr/local/nginx/sbin/nginx.1.26.3.bak

# Backup config (non verrà toccato, ma meglio averlo)
tar czf /root/nginx-config-backup-$(date +%Y%m%d).tar.gz \
    /usr/local/nginx/conf/ \
    /etc/systemd/system/nginx.service \
    /etc/logrotate.d/nginx-proxy

# Snapshot della VM se è virtualizzata (Proxmox, etc.)
# — opzionale ma fortemente consigliato per deploy production
```

---

## 4. Download sorgenti nuove (1 minuto)

```bash
mkdir -p /tmp/nginx-upgrade && cd /tmp/nginx-upgrade

# nginx 1.30.4 (ultima stable)
wget https://nginx.org/download/nginx-1.30.4.tar.gz
tar xzf nginx-1.30.4.tar.gz

# Module: fork believe4832 (chobits upstream non supporta 1.28+)
git clone https://github.com/believe4832/ngx_http_proxy_connect_module.git
```

> ℹ️ **Perché il fork?** Il module upstream `chobits/ngx_http_proxy_connect_module`
> è fermo ad agosto 2024 e non ha patch per nginx 1.28/1.29/1.30. Il fork
> `believe4832` ha pubblicato la patch `proxy_connect_rewrite_103004.patch`
> il 21 luglio 2026 con 4 righe di codice aggiuntive per impostare
> `cscf->allow_connect = 1` (richiesto da nginx 1.30+). Audit completo
> in `README.md` §"Module source".

---

## 5. Patch + Configure (1 minuto)

```bash
cd nginx-1.30.4

# Applica la patch per nginx 1.30.x
patch -p1 < ../ngx_http_proxy_connect_module/patch/proxy_connect_rewrite_103004.patch

# Configura con gli STESSI flag del deploy originale
# (verifica con: /usr/local/nginx/sbin/nginx -V 2>&1)
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

**Output atteso**: nessun hunk fallito, configure completa con
"creating objs/Makefile" alla fine.

Se la patch fallisce con `malformed patch`, stai usando la versione
sbagliata di nginx. Verifica di aver scaricato 1.30.4.

---

## 6. Compile + Install (3-5 minuti)

```bash
make -j"$(nproc)"
```

**Output atteso**: `make` termina senza errori, ultima riga tipo
`make[1]: Leaving directory '/tmp/nginx-upgrade/nginx-1.30.4'`.

```bash
# Test di sanity prima di installare
objs/nginx -V 2>&1 | head -3
# Deve mostrare: nginx version: nginx/1.30.4 + i moduli configurati

# STOP nginx (ora c'è downtime)
systemctl stop nginx

# Installa il nuovo binario (NON tocca config)
make install

# Verify binario nuovo
/usr/local/nginx/sbin/nginx -V 2>&1 | head -3
# Deve mostrare: nginx version: nginx/1.30.4
```

---

## 7. Test config + Restart (30 secondi)

```bash
# Test syntax (config invariata, deve passare pulita)
/usr/local/nginx/sbin/nginx -t

# Output atteso:
# nginx: the configuration file ... syntax is ok
# nginx: configuration file ... test is successful

# Restart
systemctl start nginx
systemctl status nginx --no-pager
```

Il PID riparte, i log continuano nello stesso file.

---

## 8. Verifica funzionale (1 minuto)

```bash
# Sostituisci SUBNET e IP con i valori del tuo deploy
PROXY_IP="192.168.89.139"   # IP del server proxy
SUBNET="192.168.89.0/24"     # Subnet autorizzata

# Test HTTP
curl -sv -x "http://${PROXY_IP}:3128" http://httpbin.org/ip 2>&1 | grep -E "200 OK|origin"

# Test HTTPS (CONNECT tunnel)
curl -sv -x "http://${PROXY_IP}:3128" https://httpbin.org/ip 2>&1 | grep -E "200 OK|origin"

# Test versione nello header Server
curl -sv -x "http://${PROXY_IP}:3128" http://httpbin.org/ip 2>&1 | grep "Server:"
# Non compare più "Server: nginx/1.26.3"
```

Tutti e tre i test devono passare. Se uno fallisce, vedi §9 (rollback).

---

## 9. Rollback (se qualcosa va male)

```bash
# STOP nuovo nginx
systemctl stop nginx

# Ripristina binario 1.26.3 dal backup
cp -a /usr/local/nginx/sbin/nginx.1.26.3.bak /usr/local/nginx/sbin/nginx

# Test syntax (la config è invariata, deve passare)
/usr/local/nginx/sbin/nginx -t

# Restart vecchia versione
systemctl start nginx

# Verify rollback
/usr/local/nginx/sbin/nginx -V 2>&1 | head -1
# Deve mostrare: nginx version: nginx/1.26.3
```

Dopo un rollback, segnala l'incidente aprendo una GitHub issue con:
- output di `nginx -V` prima e dopo
- log errori rilevanti (`/var/log/nginx/proxy_error.log`)
- comando esatto che ha fallito

---

## 10. Cleanup (post-upgrade verificato)

```bash
# Rimuovi sorgenti e oggetti temporanei
rm -rf /tmp/nginx-upgrade

# Opzionale: mantieni il backup binario 1.26.3 per 30 giorni come safety net
# (poi cancella con: rm /usr/local/nginx/sbin/nginx.1.26.3.bak)
ls -la /usr/local/nginx/sbin/nginx.1.26.3.bak
```

---

## 11. Aggiornare file di riferimento locali (opzionale)

Se hai un fork o un mirror di questa repo, dopo l'upgrade in produzione
aggiorna i riferimenti locali:

```bash
git -C /path/to/nginx-forward-proxy pull
cat /path/to/nginx-forward-proxy/VERSION
# Deve mostrare: 1.1.0
```

---

## Checklist finale

- [ ] `nginx -V` mostra `1.30.4`
- [ ] `systemctl status nginx` è `active (running)`
- [ ] Test HTTP via proxy OK
- [ ] Test HTTPS (CONNECT) via proxy OK
- [ ] Log accessi continuano a scrivere (`tail -f /var/log/nginx/proxy_access.log`)
- [ ] Nessun errore nuovo in `/var/log/nginx/proxy_error.log` nei 10 minuti successivi
- [ ] Backup binario 1.26.3 preservato (almeno 30 giorni)

---

## FAQ

**D: Devo riavviare o basta reload?**
R: Serve `restart` (stop + start). L'upgrade cambia il binario, non la
config. `reload` non ricarica il binario, solo la configurazione.

**D: Le connessioni attive vengono droppate?**
R: Sì, durante lo stop. Il downtime è tipicamente 5-10 secondi. I client
con retry automatico (curl, browser, la maggior parte degli HTTP client)
non se ne accorgono.

**D: La config 1.26.3 funziona su 1.30.4 senza modifiche?**
R: Sì. La sintassi nginx è retro-compatibile tra stabili. L'unica
differenza interna è `allow_connect` nativa, gestita
automaticamente dal module `believe4832`.

**D: Posso fare l'upgrade via CI/CD senza downtime?**
R: Sì, con due istanze dietro load balancer (blue-green). Per setup
single-instance, il downtime di 5-10 secondi è inevitabile.

**D: Quando posso decommissionare questo proxy?**
R: Quando `swg-ats-trip` (Apache Traffic Server enterprise) sarà in
produzione e avrà assorbito il traffico. Fino ad allora, questo proxy
resta il forward proxy di riferimento.

---

*Versione guida: 1.1.0 — 2026-07-22*
*Procedura testata su: Ubuntu 26.04 LTS, nginx 1.26.3 → 1.30.4*
