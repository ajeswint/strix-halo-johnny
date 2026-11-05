#Requires -RunAsAdministrator
# ABLETON_BOX: make the Johnny syslog collector survive reboot.
# Copies Start-JohnnySyslogCollector.ps1 (from this script's folder) to C:\ProgramData\johnny-syslog\,
# locks that folder to SYSTEM + Administrators, and (re)registers scheduled task JohnnySyslogCollector
# as SYSTEM/Highest with an AtStartup trigger and restart-on-failure.
# Does not stop a collector that is already running, and does not touch Windows Firewall.

$ErrorActionPreference = 'Stop'
$TaskName = 'JohnnySyslogCollector'
$Dir = 'C:\ProgramData\johnny-syslog'
$Script = Join-Path $Dir 'Start-JohnnySyslogCollector.ps1'
$Source = Join-Path $PSScriptRoot 'Start-JohnnySyslogCollector.ps1'

New-Item -ItemType Directory -Force -Path $Dir | Out-Null
Copy-Item -Path $Source -Destination $Script -Force

# SYSTEM runs this script, so only SYSTEM/Administrators may write here.
& icacls.exe $Dir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw "icacls failed ($LASTEXITCODE)" }
Write-Host "SCRIPT-OK $Script"

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$Script`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$trigger.Delay = 'PT30S'
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) `
  -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
  -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "TASK-OK $TaskName (AtStartup +30s, SYSTEM/Highest, restart every 1 min on failure)"
