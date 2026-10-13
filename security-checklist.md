# Security checklist (map findings to these)

Platform notes: **mac** = macOS, **lin** = Linux, **win** = Windows. Items without a tag apply everywhere.

1. **Patching:** OS and app updates pending; EOL OS/runtimes; known CVEs for installed versions (cross-check with vendor advisories, NVD, `osv-scanner`). mac: `softwareupdate -l`.
2. **Network exposure:** services listening on 0.0.0.0 that should be local; unexpected ports; unauthenticated admin interfaces (databases, Docker API, Redis, Jupyter). mac: Sharing settings (Remote Login, Screen Sharing, File Sharing).
3. **Authentication:** default or empty credentials, password SSH, root login, shared accounts. mac: automatic login on, no password after screen lock, shared admin account.
4. **Privilege:** broad sudo rights, services running as root/SYSTEM unnecessarily. lin/mac: SUID/SGID oddities, writable service binaries or paths, `NOPASSWD` in sudoers. mac: unexpected helpers in `/Library/PrivilegedHelperTools`. win: unquoted service paths.
5. **Persistence:** unfamiliar entries that run at login or boot, new `authorized_keys`. mac: LaunchAgents/LaunchDaemons, Login Items and Background Items (`sfltool dumpbtm`), cron. lin: cron, systemd timers. win: scheduled tasks, Run keys.
6. **Integrity:** unsigned, ad-hoc signed or unusual-location binaries; hash mismatches vs the package manager. mac: `codesign --verify --deep --strict`, `spctl -a -vv`. lin: `debsums`, `rpm -V`. win: `Get-AuthenticodeSignature`, `sfc /verifyonly`.
7. **Protection controls:** firewall, AV/EDR, disk encryption. mac: SIP (`csrutil status`), Gatekeeper (`spctl --status`), FileVault (`fdesetup status`), Apple silicon startup security. lin: AppArmor/SELinux, Secure Boot. win: BitLocker, Defender.
8. **Secrets:** plaintext credentials in env, configs, `.env` files, shell history, git history (report location only, mask values).
9. **Logging:** auditing enabled, log rotation, tamper exposure.
10. **Supply chain:** unpinned dependencies, missing lockfiles, untrusted repos/PPAs/taps, typosquatted packages, installers that pipe `curl` into a shell, unsigned or un-notarized downloads.
11. **Privacy permissions (mac):** Full Disk Access, Accessibility, Screen Recording and Input Monitoring granted to apps that do not need them (System Settings > Privacy & Security).
12. **Backups and recovery:** backups exist, are encrypted, and a restore has been tested.

Reporting a finding: checklist item number, severity (Critical / High / Medium / Low / Info), evidence (the command and its real output, secrets masked), confidence (Confirmed / Suspected / Not tested), and the fix.

Indicators are not proof: always weigh alternative benign explanations and state confidence.
