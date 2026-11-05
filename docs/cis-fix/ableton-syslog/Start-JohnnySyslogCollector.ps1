#Requires -RunAsAdministrator
# ABLETON_BOX: TCP 514 syslog collector for Johnny CIS 6.1.2.5 (rsyslog omfwd).
# Scoped firewall: only 192.168.50.152 (Johnny). Does not disable Windows Firewall.
# Run in an elevated PowerShell on Ableton. Ctrl-C stops the listener (firewall rule stays).

$ErrorActionPreference = 'Stop'
$ListenPort = 514
$JohnnyCidr = '192.168.50.152'
$LogDir = 'C:\ProgramData\johnny-syslog'
$LogFile = Join-Path $LogDir 'johnny-forward.log'
$RuleName = 'Johnny CIS rsyslog TCP 514'

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$existing = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
if (-not $existing) {
  New-NetFirewallRule -DisplayName $RuleName `
    -Direction Inbound -Action Allow -Protocol TCP -LocalPort $ListenPort `
    -RemoteAddress $JohnnyCidr -Profile Any | Out-Null
  Write-Host "FIREWALL-OK $RuleName (allow TCP $ListenPort from $JohnnyCidr only)"
} else {
  Write-Host "FIREWALL-KEPT $RuleName"
}

$endpoint = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, $ListenPort)
$listener = [System.Net.Sockets.TcpListener]::new($endpoint)
try {
  $listener.Start()
} catch {
  Write-Host "STOP-bind: could not listen on TCP $ListenPort (need Admin; is another service using it?)"
  throw
}
Write-Host "LISTEN-OK 0.0.0.0:$ListenPort  writing -> $LogFile"
Write-Host "From Johnny: timeout 5 bash -c 'echo >/dev/tcp/192.168.50.211/514'  then re-run batch-10.sh"
Write-Host "Ctrl-C to stop listener (firewall rule remains)."

try {
  while ($true) {
    $client = $listener.AcceptTcpClient()
    $remote = $client.Client.RemoteEndPoint.ToString()
    $stamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK'
    Add-Content -Path $LogFile -Value "$stamp ACCEPT $remote"
    $stream = $client.GetStream()
    $reader = New-Object System.IO.StreamReader($stream)
    try {
      while ($client.Connected -and -not $reader.EndOfStream) {
        $line = $reader.ReadLine()
        if ($null -eq $line) { break }
        Add-Content -Path $LogFile -Value "$stamp $remote $line"
      }
    } catch {
      # client closed
    } finally {
      $reader.Dispose()
      $client.Close()
    }
  }
} finally {
  $listener.Stop()
  Write-Host 'LISTEN-STOPPED'
}
