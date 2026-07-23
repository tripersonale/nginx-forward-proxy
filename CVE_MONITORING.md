# CVE Monitoring — Dipendenze sotto occhio

Elenco delle dipendenze software che compongono questo forward proxy,
con le fonti ufficiali da monitorare per CVE, frequenza di check
consigliata e azioni da intraprendere quando esce un advisory.

Pattern derivato da `swg-ats-trip/07_SECURITY/SECURITY_BASELINE.md`,
adattato al singolo servizio.

---

## Catalogo dipendenze

| # | Componente | Versione minima | Linkaggio | Source CVE ufficiale |
|---|-----------|-----------------|-----------|----------------------|
| 1 | **nginx** | 1.30.4 | Statico (compilato da sorgente) | https://nginx.org/en/security_advisories.html |
| 2 | **ngx_http_proxy_connect_module** (fork believe4832) | commit `support nginx-1.30.4` del 2026-07-21 | Statico (add-module) | https://github.com/believe4832/ngx_http_proxy_connect_module/security/advisories |
| 3 | **OpenSSL** | versione di sistema (apt) | Statico (compilato dentro nginx) | https://www.openssl.org/news/secadv/ e `ubuntu-security-status` |
| 4 | **PCRE2** | versione di sistema (apt) | Dinamico (.so) | https://github.com/PCRE2Project/pcre2/security + Ubuntu USN |
| 5 | **zlib** | versione di sistema (apt) | Dinamico (.so) | https://github.com/madler/zlib/security + Ubuntu USN |
| 6 | **libcrypt** | versione di sistema (apt) | Dinamico (.so) | Ubuntu USN |
| 7 | **Ubuntu base OS** | 26.04 LTS | Sistema operativo | https://ubuntu.com/security/notices |

---

## Fonti di monitoring (RSS / API / pagine da checkare)

### nginx (priorità MASSIMA)

- **Security advisories**: https://nginx.org/en/security_advisories.html
  - Questa è la pagina canonica. Tutte le CVE storiche sono qui.
  - **Check**: settimanale + on-demand quando nginx annuncia release.
- **CHANGES stable (1.30)**: https://nginx.org/en/CHANGES-1.30
  - Include sia fix di sicurezza che bugfix. Da leggere per capire cosa
    cambia in ogni release.
- **CHANGES mainline**: https://nginx.org/en/CHANGES
  - Anteprima di cosa arriverà nella prossima stable.
- **nginx-announce mailing list**: https://mailman.nginx.org/mailman/listinfo/nginx-announce
  - Sottoscrivere per ricevere email automatica su ogni security advisory.

### ngx_http_proxy_connect_module (priorità ALTA)

- **Repo fork**: https://github.com/believe4832/ngx_http_proxy_connect_module
  - Watch su GitHub per ricevere notifica di commit.
- **Repo upstream (chobits)**: https://github.com/chobits/ngx_http_proxy_connect_module
  - Watch anche qui: se il maintainer originale riprende attività,
    potremo tornare all'upstream.
- **Issue aperte su chobits**: https://github.com/chobits/ngx_http_proxy_connect_module/issues
  - Verificare se escono issue tipo "support nginx-1.32" che potrebbero
    segnalare il deprecamento del fork.

### OpenSSL (priorità ALTA)

- **Security advisories**: https://www.openssl.org/news/secadv/
  - RSS disponibile. Sottoscrivere.
- **Ubuntu Security Notice**: OpenSSL è pacchettizzato in Ubuntu,
  quindi `apt update && apt upgrade libssl3` risolve quasi tutte le CVE.
  - MA: nel nostro caso OpenSSL è **statico** dentro nginx, quindi
    `apt upgrade` NON basta. Serve ricompilare nginx.

### PCRE2 / zlib / libcrypt (priorità MEDIA)

- **Ubuntu Security Notices**: https://ubuntu.com/security/notices
  - Queste librerie sono linkate dinamicamente, quindi `apt upgrade`
    basta a fixarle senza ricompilare nginx.
- **PCRE2 GitHub security**: https://github.com/PCRE2Project/pcre2/security/advisories
- **zlib GitHub security**: https://github.com/madler/zlib/security/advisories

### Ubuntu base OS (priorità MEDIA)

- **Ubuntu Security Notices**: https://ubuntu.com/security/notices
  - Sottoscrivi RSS per Ubuntu 26.04.
- **unattended-upgrades**: se attivato (consigliato per deploy production),
  risolve automaticamente pacchetti di sistema.

---

## Frequenza di check consigliata

| Attività | Frequenza | Tempo stimato |
|----------|-----------|---------------|
| Check pagina nginx security advisories | Settimanale (lunedì) | 5 min |
| Sottoscrizione mailing list nginx-announce | Una tantum | 2 min |
| Watch GitHub repo believe4832 + chobits | Una tantum | 1 min |
| Check OpenSSL secadv | Settimanale | 3 min |
| `apt update && apt list --upgradable` | Giornaliero (cron o manual) | 1 min |
| `ubuntu-security-status` (su server production) | Mensile | 5 min |
| Audit completo: `nginx -V` vs `nginx.org` versioni | Trimestrale | 10 min |
| Test di penetration con Baluardo (se disponibile) | Semestrale | Variabile |

---

## Azioni quando esce una CVE

### Step 1: Triage (5 minuti)

1. **Verifica impatto**: la CVE colpisce la nostra versione?
   - Esempio: `CVE-2026-42533` "Vulnerable: 0.9.6-1.31.2" → 1.30.4 ✅ vulnerabile
   - Consulta la tabella nella pagina nginx security advisories.
2. **Valuta severity**: `major` / `medium` / `low`
3. **Verifica exploitability nel nostro contesto**:
   - Il forward proxy è esposto solo a subnet fidate (UFW allow).
   - Le CVE in HTTP/3 non ci impattano se non usiamo HTTP/3.
   - Le CVE in `ngx_http_dav_module` non ci impattano se non abilitiamo WebDAV.

### Step 2: Decisione

| Severity | Exploitabile nel nostro setup? | Azione |
|----------|------------------------------|--------|
| major | Sì | Upgrade entro 7 giorni (vedi `UPGRADE.md`) |
| major | No | Upgrade nel prossimo cycle (entro 30 giorni) |
| medium | Sì | Upgrade nel prossimo cycle (entro 30 giorni) |
| medium | No | Monitorare, upgrade al prossimo release |
| low | Qualsiasi | Upgrade al prossimo release (non urgente) |

### Step 3: Esecuzione

- Segui `UPGRADE.md` per bumpare nginx
- Aggiorna `CHANGELOG.md` e `VERSION`
- Tag git (`git tag vX.Y.Z`) + push tag
- Notifica nel session log / change tracker

### Step 4: Post-upgrade

- Verifica `nginx -V` mostra la nuova versione
- Test funzionale (curl HTTP + HTTPS via proxy)
- Smoke test 24h (monitor log errori)
- Chiudi la CVE nella tracking list interna

---

## Logging delle azioni di security

Ogni azione di monitoring/upgrade va registrata in
`/var/log/nginx/security-actions.log` (creare se non esiste):

```bash
sudo touch /var/log/nginx/security-actions.log
sudo chmod 600 /var/log/nginx/security-actions.log
```

Formato (1 riga per azione):

```
2026-07-22T15:00Z | UPGRADE | nginx 1.26.3 → 1.30.4 | CVE-2026-42533,42945,42055 | operator: TRiP
2026-07-29T09:00Z | CHECK   | nginx advisories: no new CVE | n/a | operator: cron
2026-08-05T09:00Z | CHECK   | OpenSSL secadv: 1 new (CVE-XXXX, non impatta setup) | n/a | operator: TRiP
```

---

## Decommissioning previsto

Questo forward proxy nginx è destinato a essere **sostituito** da
`swg-ats-trip` (Apache Traffic Server enterprise, in
`02_LAVORATORE/ICT/OS2/swg-ats-trip/`) quando quest'ultimo sarà
production-ready.

Fino ad allora, **resta il forward proxy di riferimento** e va mantenuto
aggiornato secondo questa checklist.

Quando `swg-ats-trip` assorbirà il traffico:
1. Marcare questo repo come `DEPRECATED` nel README
2. Ultimo tag di release (`v2.0.0-deprecated`)
3. Mantenere repo in sola lettura per riferimento storico
4. Rimuovere snapshot/firewall/VM del proxy nginx

---

## Riferimenti esterni

- **nginx**: https://nginx.org/en/security_advisories.html
- **OpenSSL**: https://www.openssl.org/news/secadv/
- **Ubuntu Security**: https://ubuntu.com/security/notices
- **NVD (National Vulnerability Database)**: https://nvd.nist.gov/
- **MITRE CVE**: https://cve.mitre.org/
- **ISO 27001 Annex A.12.6**: Technical vulnerability management
- **CIS Benchmark nginx**: https://www.cisecurity.org/benchmark/nginx

---

*Versione: 1.0 — 2026-07-22*
*Prossima revisione: 2026-10-22 (o al primo advisory nginx major)*
