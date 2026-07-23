# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it
privately before disclosing it publicly. **Do not open a public issue.**

**Contact**: tripersonale@tripersonale.com (or open a GitHub issue with
`[SECURITY]` in the title if you cannot reach via email).

We will acknowledge receipt within 48 hours and aim to release a fix within
7 days. You will be credited for the discovery (unless you prefer anonymity).

## Scope

This project is a forward proxy. Vulnerabilities include, but are not limited to:

- Bypassing access controls
- Information leakage through logs
- Remote code execution through crafted CONNECT requests
- Memory corruption in the proxy_connect module

## Out of scope

- Unauthorized access due to misconfiguration (the admin is responsible for
  configuring `allow`/`deny` directives correctly)
- Weak TLS ciphers on proxied upstream connections (the proxy tunnels what
  the client negotiates)
- Security of the nginx binary itself (report to nginx.org or the
  ngx_http_proxy_connect_module maintainer)

## Supported versions

| Versione | nginx | Module | Stato | Note |
|----------|-------|--------|-------|------|
| **v1.1.x** | 1.30.4 | `believe4832` fork | ✅ Supportato | Risolve 14+ CVE della 1.26.3 |
| v1.0.x | 1.26.3 | `chobits` upstream | ⚠️ Legacy (EOL) | Solo security fix critici, vedi `UPGRADE.md` |

Per l'elenco completo delle CVE risolte nella 1.1.0, vedi [`CHANGELOG.md`](./CHANGELOG.md).
Per monitoring CVE continuo, vedi [`CVE_MONITORING.md`](./CVE_MONITORING.md).

## Good practices for deployers

See `OPERATING_MANUAL.md` for:
- Firewall configuration (Step 11)
- Access control directives (§2.3)
- Log rotation (§3.5)
- IP privacy considerations (§2.1)

## Vulnerability reporting for upstream deps

- **nginx**: https://nginx.org/en/security_advisories.html
- **ngx_http_proxy_connect_module** (fork): https://github.com/believe4832/ngx_http_proxy_connect_module/security/advisories/new
- **OpenSSL** (statico): https://www.openssl.org/news/secadv/
