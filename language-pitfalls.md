# Language-specific pitfalls

- **Python:** `eval/exec`, `pickle`/`yaml.load` on untrusted data, `subprocess(shell=True)`, mutable default args, bare `except`, `assert` for validation, unclosed files, `requests` without timeout/verify, Flask/Django `DEBUG=True`.
- **JavaScript/TypeScript:** prototype pollution, `eval`/`new Function`, `innerHTML`/XSS, unhandled promise rejections, `==` coercion, ReDoS, `child_process.exec` with input, vulnerable transitive deps, `any` abuse.
- **Java:** deserialization (`ObjectInputStream`), XXE in XML parsers, SQL string concat, resource leaks without try-with-resources, Log4Shell-class issues, null handling.
- **C#/.NET:** SQL concat, unsafe `BinaryFormatter`, missing `using`/`Dispose`, async deadlocks (`.Result`), weak crypto (MD5/SHA1).
- **Go:** ignored errors, goroutine leaks, data races, `InsecureSkipVerify`, unbounded reads.
- **PHP:** `include` with user input, `unserialize`, type juggling, SQL concat, `display_errors` on.
- **Ruby:** `eval`/`send` on input, mass assignment, `YAML.load`.
- **Bash/PowerShell:** unquoted variables, missing `set -euo pipefail`, `curl | sh`, `Invoke-Expression`, world-writable temp files, plaintext secrets.
- **All:** hardcoded secrets, missing input validation, lack of timeouts/retries, broad exception swallowing, unbounded resource use, missing tests for negative and boundary cases.
