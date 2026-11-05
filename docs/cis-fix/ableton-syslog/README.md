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

This is a **temporary** acceptor for CIS 6.1.2.5 / omfwd. Long-term: rebuild Ableton as Ubuntu + Security Onion manager (parked), or replace with nxlog/syslog-ng service.
