# Security Checklist

## OWASP Top 10 (web)
Broken access control (IDOR, missing authz on endpoints, forced browsing) | Cryptographic failures (plaintext secrets, weak hashing, no TLS) | Injection (SQL/NoSQL/OS/LDAP/template, XSS) | Insecure design | Security misconfiguration (headers, CORS, verbose errors, default creds) | Vulnerable/outdated components | Identification and authentication failures (brute force, weak reset, session fixation) | Software and data integrity failures (unsigned updates, insecure deserialization, CI/CD trust) | Logging and monitoring failures | SSRF.

## OWASP API Top 10 highlights
BOLA, broken authentication, broken object property level authorization (mass assignment), unrestricted resource consumption (rate limits), broken function-level authz, unrestricted access to sensitive business flows, SSRF, misconfiguration, improper inventory (shadow/old API versions), unsafe consumption of third-party APIs.

## Quick controls
- Parameterized queries; output encoding; CSP; HttpOnly/Secure/SameSite cookies
- Password hashing: argon2id/bcrypt/scrypt; MFA; lockout/rate limiting
- Server-side authz on every request; deny by default
- Secrets in a vault/env, rotated; no secrets in logs
- Headers: HSTS, X-Content-Type-Options, frame-ancestors, Referrer-Policy, Permissions-Policy
- File uploads: type/size validation, storage outside web root, malware scan
- Pin dependencies, lockfiles, SBOM, signed artifacts, least-privilege CI tokens
