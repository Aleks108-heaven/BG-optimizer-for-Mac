# API Test Case Template and Examples

Per endpoint, cover: 200/201/204 happy path | 400 invalid body | 401 no, expired or tampered token | 403 wrong role | 404 unknown ID | 405 wrong method | 409 duplicate or conflict | 413 oversized body | 415 wrong content-type | 422 semantic error | 429 rate limit | 5xx dependency failure.

Check on every response: status code, body matches the schema, error bodies have one consistent shape (for example RFC 9457 problem details), no stack traces, internal paths or secrets, `Content-Type` matches the body, security headers present, latency within budget.

Also per endpoint: list endpoints at pagination limits (0, 1, max, max+1, negative), retries of POST/PUT/DELETE (idempotency), two parallel identical requests (races), dependency outage mapped to 502/503/504 rather than a generic 500.

Example: POST /api/users (Pri: H high, M medium, L low)
| ID | Pri | Case | Input | Expected |
|---|---|---|---|---|
| U-01 | H | Valid | name 'Ann', email valid | 201, id returned, schema valid |
| U-02 | H | Missing email | no email | 400, error names the field |
| U-03 | M | Name boundary | 0, 1, 50, 51 chars | 400, 201, 201, 400 |
| U-04 | H | Duplicate email | existing email | 409 |
| U-05 | H | Duplicate, different case | `ANN@x.com` when `ann@x.com` exists | 409 (uniqueness is case-insensitive) |
| U-06 | M | Email format | `a@b`, ` a@b.co ` (spaces), 255 chars | 400, 201 trimmed, 400 |
| U-07 | M | Unicode | name 'Zoë 李雷 😀' | 201, returned unchanged |
| U-08 | H | Injection | name `'; DROP TABLE users--` | no 5xx; value stored and returned escaped; table still exists |
| U-09 | H | Mass assignment | body includes `"role":"admin"` | field ignored or 400; created user is not admin |
| U-10 | H | IDOR | GET /users/{otherUserId} as user A | 403 or 404; pick one and use it everywhere (404 does not reveal that the ID exists) |
| U-11 | H | Token problems | none, expired, wrong signature | 401 each; valid token with wrong role: 403 |
| U-12 | M | Wrong content-type | `text/plain` body | 415 |
| U-13 | M | Malformed JSON | `{"name":` | 400, not 500 |
| U-14 | M | Oversized body | 10 MB | 413 |
| U-15 | M | Race | two simultaneous POSTs, same new email | exactly one 201 and one 409 |
| U-16 | M | Rate limit | burst above the limit | 429 with `Retry-After` |
| U-17 | L | Wrong method | DELETE /api/users | 405 with an `Allow` header |
| U-18 | H | Data exposure | any user response or error | no password hash, token or stack trace in the body |
