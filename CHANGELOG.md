# Changelog

Tutte le modifiche notevoli di questo progetto saranno documentate in questo file.

Il formato è basato su [Keep a Changelog](https://keepachangelog.com/it/1.1.0/),
e questo progetto aderisce a [Semantic Versioning](https://semver.org/lang/it/spec/v2.0.0.html).

## [1.1.1] — 2026-07-24

### Fixed
- `UPGRADE.md` §3: comando `tar` con `$(date)` in subshell SSH+sudo non
  creava il file di backup. Fix: assegnare `BACKUP_DATE=$(date ...)`
  nella shell locale prima di `sudo tar`.

### Changed
- `UPGRADE.md` FAQ: downtime realistico aggiornato da "5-10s" a
  "~12s" (misurato in test end-to-end su VM KVM 4 vCPU/SSD).

### Added
- `UPGRADE.md` Appendice A: report verifica end-to-end su VM KVM dedicata
  (Ubuntu 26.04 LTS, kernel 7.0.0). Tutti gli step da 1 a 9 verificati
  con esito positivo, incluso rollback.

## [1.1.0] — 2026-07-22

### Security
- **nginx bumpato da 1.26.3 a 1.30.4** (ultima stable). Risolve tutte le CVE
  accumulate dalla 1.26.3 a oggi, incluse:
  - `CVE-2026-42533` (major) — buffer overflow in `map` + regex
  - `CVE-2026-9256` — buffer overflow in `ngx_http_rewrite_module`
  - `CVE-2026-42055` — buffer overflow in `ngx_http_proxy_v2_module` / `ngx_http_grpc_module`
  - `CVE-2026-42945` — buffer overflow in `ngx_http_rewrite_module`
  - `CVE-2026-42946` — overread in `ngx_http_scgi_module` / `ngx_http_uwsgi_module`
  - `CVE-2026-40701` — use-after-free in resolver OCSP
  - `CVE-2026-1642` — SSL upstream injection (critica per forward proxy)
  - `CVE-2026-27654/27784/32647/27651/28753/28755` — DAV/mp4/mail/stream
  - `CVE-2026-48142`/`42934` — overread in `ngx_http_charset_module`
  - `CVE-2026-60005`/`56434` — memory disclosure slice / UAF ssi
  Elenco completo: https://nginx.org/en/security_advisories.html

### Changed
- **Module source**: `chobits/ngx_http_proxy_connect_module` sostituito con
  il fork `believe4832/ngx_http_proxy_connect_module`. Motivo: chobits
  upstream è fermo ad agosto 2024 e non supporta nginx 1.28+. Il fork
  aggiunge solo 4 righe al `.c` per impostare `cscf->allow_connect = 1`
  (direttiva nativa introdotta in nginx 1.30 per accettare CONNECT).
  Patch adottata: `proxy_connect_rewrite_103004.patch` (commit
  `support nginx-1.30.4` del 2026-07-21). Vedi README §"Module source".

### Added
- `UPGRADE.md` — manuale rapido per aggiornare un deploy esistente
  (1.26.3 → 1.30.4) senza perdita di dati
- `CVE_MONITORING.md` — elenco repo e librerie da monitorare per CVE,
  con source ufficiali, frequenza di check e azioni consigliate
- `CHANGELOG.md` — questo file
- `VERSION` — file singolo con numero versione corrente
- README: nuova sezione "Module source" con rationale cambio fork
- README: nuova sezione "Versioni supportate"

### Documentation
- `README.md`: aggiornate tutte le occorrenze 1.26.3 → 1.30.4,
  URL module, nome patch, troubleshooting patch malformed, tabella
  dipendenze, footer data
- `deploy.sh`: aggiornata variabile `NGINX_VERSION`, URL clone, nome patch
- `conf/nginx-forward-proxy.conf`: aggiornato commento versione
- `SECURITY.md`: aggiunte versioni supportate v1.0.x (legacy) e v1.1.x

## [1.0.0] — 2026-05-28

### Added
- Initial release
- nginx 1.26.3 + `chobits/ngx_http_proxy_connect_module`
- README IKEA-style (12 step), OPERATING_MANUAL, deploy.sh, check.sh
- LICENSE FEL-1.1 (PolyForm NC + AUG → AGPL v3+ dopo 5 anni)
- SECURITY.md, GDPR notes, logrotate 90gg

### Known issues (risolti in 1.1.0)
- nginx 1.26.3 vulnerabile a 14+ CVE (vedi sopra)
- chobits module non compatibile con nginx 1.28+

[1.1.0]: https://github.com/tripersonale/nginx-forward-proxy/releases/tag/v1.1.0
[1.0.0]: https://github.com/tripersonale/nginx-forward-proxy/releases/tag/v1.0.0
