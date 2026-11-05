#Requires -RunAsAdministrator
$RuleName = 'Johnny CIS rsyslog TCP 514'
$TaskName = 'JohnnySyslogCollector'
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
  Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
  Write-Host "Stopped and removed scheduled task: $TaskName"
}
Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
Write-Host "Removed firewall rule (if present): $RuleName"
Write-Host "If a manual Start-JohnnySyslogCollector.ps1 window is open, stop it with Ctrl-C."
Write-Host "Log files and the script under C:\ProgramData\johnny-syslog are left in place."
