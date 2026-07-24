# nginx forward proxy

> **Forward proxy HTTP/HTTPS enterprise** con nginx 1.30.4 + modulo
> `proxy_connect`. Compilato da sorgente, hardenizzato, audit-friendly.

[![License: FEL-1.1](https://img.shields.io/badge/License-FEL--1.1-blue.svg)](./LICENSE)
[![Version](https://img.shields.io/badge/version-1.1.1-green.svg)](./VERSION)
[![nginx](https://img.shields.io/badge/nginx-1.30.4-success.svg)](https://nginx.org/en/CHANGES-1.30)
[![Ubuntu 26.04](https://img.shields.io/badge/Ubuntu-26.04%20LTS-orange.svg)](https://releases.ubuntu.com/26.04/)
[![Last verified](https://img.shields.io/badge/last--verified-2026--07--24-brightgreen.svg)](./UPGRADE.md#appendice-a--verifica-end-to-end-2026-07-24)

---

## Cosa fa

```
Il tuo PC ──► nginx proxy (:3128) ──► Internet
  (LAN)          (questa guida)      (siti web)

Ogni richiesta via proxy viene loggata con:
  → IP del client (chi ha chiesto)
  → hostname destinazione (cosa ha chiesto)
  → IP risolto del server (dove è andata la connessione)
  → tempo impiegato
```

---

## 3 scenari

| Scenario | Tempo | Vai a |
|----------|-------|-------|
| 🆕 **Installare ex novo** | ~30 min | [`INSTALL.md`](./INSTALL.md) (12 step IKEA) |
| ⬆️ **Aggiornare un deploy esistente** | ~10 min | [`UPGRADE.md`](./UPGRADE.md) (verificato end-to-end) |
| 📖 **Reference / operatività** | on-demand | [`OPERATING_MANUAL.md`](./OPERATING_MANUAL.md) |

---

## Mappa della repo

| File | Cosa contiene | Quando lo usi |
|------|---------------|---------------|
| `README.md` | ✋ Sei qui. Indice e quick-start | Punto di ingresso |
| `INSTALL.md` | Tutorial 12 step (IKEA) | Fresh install |
| `UPGRADE.md` | Procedura upgrade produzione | Aggiornamento da v1.0 → v1.1 |
| `OPERATING_MANUAL.md` | Reference: log, config, operazioni comuni | Uso quotidiano |
| `CVE_MONITORING.md` | Catalogo CVE + fonti + frequenze check | Audit sicurezza |
| `SECURITY.md` | Policy + reporting vulnerabilità | Segnalare bug |
| `CHANGELOG.md` | Storia versioni (SemVer) | Cosa è cambiato |
| `VERSION` | Versione corrente (file singolo) | Per script |
| `LICENSE` | FEL-1.1 dual license | Note legali |
| `deploy.sh` | Installer automatico (esegue INSTALL.md) | Fresh install uno-shot |
| `check.sh` | Smoke test post-install | Verify funzionale |
| `conf/nginx-forward-proxy.conf` | Config nginx (template) | Manual install |
| `systemd/nginx.service` | Unit systemd (template) | Reference |

---

## Status

| Componente | Versione | Note |
|-----------|----------|------|
| nginx | **1.30.4** | Latest stable, 14+ CVE risolte |
| proxy_connect_module | `believe4832` fork | chobits upstream abbandonato da ago 2024 |
| Patch | `proxy_connect_rewrite_103004.patch` | Commit 2026-07-21 |
| OpenSSL | 3.5.5 (Ubuntu 26.04) | Statico dentro nginx |
| Sistema | Ubuntu 26.04 LTS (Resolute) | Kernel 7.0.0 |
| Ultima verifica E2E | 2026-07-24 | VM KVM dedicata, 9 step OK + rollback |

---

## Sicurezza in pillole

- **14+ CVE risolte** passando da 1.26.3 → 1.30.4 (tutte `critical`/`major`/`medium`/`low`
  che impattavano 1.26.3). Dettaglio: [`CHANGELOG.md`](./CHANGELOG.md) v1.1.0.
- **Nessun segreto in chiaro nei commit**: `.env` mai committato.
- **Audit log** di tutte le operazioni `/var/log/nginx/proxy_access.log`
  include `$connect_addr` (IP risolto CONNECT) per forensics.
- **Module fork verificato**: `believe4832` differisce da upstream di sole
  4 righe (imposta `cscf->allow_connect = 1`). Audit completo:
  [`INSTALL.md`](./INSTALL.md) §"Module source".

Il catalogo CVE continuo da monitorare è in [`CVE_MONITORING.md`](./CVE_MONITORING.md).

---

## Versioni supportate

| Versione | nginx | Module | Stato |
|----------|-------|--------|-------|
| **v1.1.x** | 1.30.4 | `believe4832` fork | ✅ Corrente |
| v1.0.x | 1.26.3 | `chobits` upstream | ⚠️ Legacy (14+ CVE) |

Per il modulo fork: perché usiamo `believe4832` invece dell'upstream
`chobits`, vedi dettagli in [`INSTALL.md`](./INSTALL.md) §"Module source"
(audit completo, diff di 4 righe, ritorno all'upstream quando disponibile).

---

## Architettura (1 minuto)

```
           ┌──── subnet autorizzata (es. 192.168.20.0/24) ───┐
           │                                                │
    client │                                                │ client
       │   │                                                │   │
       ▼   ▼                                                ▼   ▼
   ┌─────────────┐                                    ┌─────────────┐
   │ client 1    │                                    │ client N    │
   │ (curl/browser)                                  │ (Bespoke)   │
   └──────┬──────┘                                    └──────┬──────┘
          │ CONNECT example.com:443                          │
          ▼                                                 ▼
   ╔═══════════════════════════════════════════════════════════════╗
   ║   nginx 1.30.4 + ngx_http_proxy_connect_module (1.30.4)     ║
   ║   listen :3128, allow from SUBNET, deny all                ║
   ║   log_format forward_proxy (host, upstream, connect_addr)  ║
   ╚═══════════════════════════════════════════════════════════════╝
          │ HTTPS (CONNECT tunnel)
          ▼
   example.com:443 (HTTP upstream)
```

Componenti:
- **nginx 1.30.4** — statico, compilato da sorgente (vedi `INSTALL.md` step 5-6)
- **ngx_http_proxy_connect_module** — modulo fork, fornisce supporto CONNECT
  richiesto da nginx 1.30+ (allow_connect nativo)
- **ufw** — firewall, default deny, allow solo porta 3128 da subnet autorizzata
- **logrotate** — 90 giorni retention con compressione

---

## Quando NON usare questo proxy

- ❌ **Setup familiare / SOHO** → eccessivo, usa un COTS reverse proxy
- ❌ **Carico elevato (>5k req/s)** → valuta `swg-ats-trip` (Apache Traffic
  Server enterprise, in arrivo in questo workspace)
- ❌ **Multi-tenant con isolamenti forti** → richiede autenticazione e
  accounting che questo template non implementa
- ❌ **Reverse proxy (contenuti statici, API)** → non è il caso d'uso

Per il forward proxy enterprise con ATS, vedi
[swg-ats-trip](https://github.com/tripersonale/swg-ats-trip) (prossimamente
disponibile, sarà il sostituto di questo progetto).

---

## Contribuire

Issue e PR sono benvenute. Per modifiche al module source, prima
verifica che la patch funzioni pulita sul branch nginx target:

```bash
cd /tmp && wget https://nginx.org/download/nginx-1.30.4.tar.gz
tar xzf nginx-1.30.4.tar.gz && cd nginx-1.30.4
patch -p1 --dry-run < /path/to/proxy_connect_rewrite_103004.patch
```

Se applica pulita, procedi. Per qualsiasi cambiamento alle policy
(sicurezza, CVE monitoring, licensing), apri prima una issue per
discutere l'approccio.

---

## Licenza

FEL-1.1 dual license (PolyForm NC 1.0.0 + Additional Use Grant → AGPL v3+
dopo 5 anni). Dettaglio: [`LICENSE`](./LICENSE).

Per uso commerciale entro le soglie di esenzione (≤€25K SaaS, ≤€75K
dipendente, ≤€50K se 0 dipendenti — basta OR), nessun obbligo.
Per uso commerciale oltre soglia: contatto per accordo FEL.

---

## Riferimenti

- [nginx security advisories](https://nginx.org/en/security_advisories.html)
- [nginx 1.30 stable CHANGES](https://nginx.org/en/CHANGES-1.30)
- [ngx_http_proxy_connect_module — fork believe4832](https://github.com/believe4832/ngx_http_proxy_connect_module)
- [ngx_http_proxy_connect_module — upstream chobits](https://github.com/chobits/ngx_http_proxy_connect_module)
- [OpenSSL Security Advisories](https://www.openssl.org/news/secadv/)
- [Ubuntu Security Notices](https://ubuntu.com/security/notices)

---

*Versione repo: 1.1.1 — 2026-07-24*
*Documentazione in italiano per il workflow MVB / Tripersonale*
*Tutti i test eseguiti su VM KVM Ubuntu 26.04 LTS dedicata*
