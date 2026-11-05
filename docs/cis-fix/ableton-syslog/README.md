# Temporary Johnny → ABLETON_BOX syslog (TCP 514)

ABLETON_BOX is still **Windows** (`OpenSSH_for_Windows_9.5`, RDP 3389). No SSH key/password from rock-box, so the collector is started by AJ on the box.

## Start (ABLETON_BOX, elevated PowerShell)

```powershell
# copy Start-JohnnySyslogCollector.ps1 onto the box, then:
Set-ExecutionPolicy -Scope Process Bypass
cd <folder-with-script>
.\Start-JohnnySyslogCollector.ps1
```

Expect `FIREWALL-OK` / `LISTEN-OK`. Leave the window open.

## Survive reboot (installed 2026-11-04)

Scheduled task `JohnnySyslogCollector` runs as SYSTEM (Highest) with an **AtStartup** trigger (30 s delay) and restarts every 1 min on failure. It runs the durable copy at `C:\ProgramData\johnny-syslog\Start-JohnnySyslogCollector.ps1`; the folder is writable only by SYSTEM and Administrators. The firewall rule persists on its own. Windows Firewall stays on.

Install or re-install (elevated PowerShell, or `ssh able@192.168.50.211`; copy both scripts to one folder first):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-JohnnySyslogTask.ps1
```

It does not stop a collector that is already running. Not yet proven by an actual reboot of ABLETON_BOX.

Check:

```powershell
Get-ScheduledTask JohnnySyslogCollector | Select-Object State -ExpandProperty Triggers
Get-NetTCPConnection -LocalPort 514 -State Listen
```

Stop for now (task stays, comes back at next boot):

```powershell
Stop-ScheduledTask JohnnySyslogCollector
```

Stop for good: run `.\Remove-JohnnySyslogCollector.ps1`.

## Verify (Johnny SSH)

```bash
timeout 5 bash -c 'echo >/dev/tcp/192.168.50.211/514' && echo PROBE-OK
sudo bash ~/cis-audit/batch-10.sh 2>&1 | tee ~/cis-audit/batch-10-out.txt
# expect past STOP-collector-514 → BATCH10-SSH-DONE (after GRUB/modules already done)
```

## Remove

```powershell
.\Remove-JohnnySyslogCollector.ps1
```

This stops and unregisters the task and removes the firewall rule. The folder `C:\ProgramData\johnny-syslog` and its logs stay.

This is a **temporary** acceptor for CIS 6.1.2.5 / omfwd. Long-term: rebuild Ableton as Ubuntu + Security Onion manager (parked), or replace with nxlog/syslog-ng service.
