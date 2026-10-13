# Quick-check commands (read-only)

## Linux
`systemctl --failed; ps aux --sort=-%cpu | head -10; ss -tulpn; ufw status; journalctl -p err -S -24h --no-pager | tail -50; apt list --upgradable 2>/dev/null | head; python3 --version; node -v`

## Windows (PowerShell)
`Get-Service | ? {$_.Status -eq 'Stopped' -and $_.StartType -eq 'Automatic'}; Get-Process | Sort CPU -desc | Select -First 10; Get-NetTCPConnection -State Listen; Get-NetFirewallProfile; Get-MpComputerStatus; Get-WinEvent -FilterHashtable @{LogName='System','Application';Level=1,2;StartTime=(Get-Date).AddDays(-1)} -MaxEvents 50`

## macOS
`launchctl list | awk '$2 != 0'; ps aux -r | head -10; lsof -iTCP -sTCP:LISTEN -n -P; /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate; csrutil status; spctl --status; softwareupdate -l; log show --last 24h --predicate 'messageType == error' | tail -50`
