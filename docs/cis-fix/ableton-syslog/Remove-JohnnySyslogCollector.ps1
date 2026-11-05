#Requires -RunAsAdministrator
$RuleName = 'Johnny CIS rsyslog TCP 514'
Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
Write-Host "Removed firewall rule (if present): $RuleName"
Write-Host "Stop any running Start-JohnnySyslogCollector.ps1 window with Ctrl-C."
Write-Host "Log files under C:\ProgramData\johnny-syslog are left in place."
