# Batch 10 close — CIS L1 fix pass complete (2026-11-04 ~23:06 CT)

Historical once the next session starts. Current state: `docs/os-handoff.md` rev 68.

Corrected 2026-11-04 23:55 CT (handoff rev 68): Ableton reboot proof passed 2026-11-04 CT (JohnnySyslogCollector AtStartup came back; TCP 514 OK from Johnny). Step 7 is recorded applied in the handoff SBOM. Next is step 11, drafted, not applied. The sections below are the 2026-11-04 close as written.

## Outcome

- **Rules:** 1.4.1 PASS; 3.2.3 PASS; 3.2.7 PASS (manual); 6.1.2.5 PASS (manual).
- **CSV totals:** 225 PASS, 18 PASS (manual), 31 N/A, **0 FAIL** (274/274).
- **L1 fix batches 1–10:** closed. No batch-11 planned.

## Ableton collector

- Host `ABLETON_BOX` / `able@192.168.50.211`, OpenSSH port 22.
- Temporary TCP 514 listener: scheduled task `JohnnySyslogCollector` (SYSTEM/Highest, AtStartup +30s, restart every 1 min on failure).
- Script: `C:\ProgramData\johnny-syslog\Start-JohnnySyslogCollector.ps1`.
- Firewall: `Johnny CIS rsyslog TCP 514` from `192.168.50.152` only.
- Install helpers: `docs/cis-fix/ableton-syslog/` (`Install-JohnnySyslogTask.ps1`, start/remove scripts, README). Commit `bdfc2c6`.
- Not proven by a real Ableton reboot yet.

## Johnny drop-ins (mirrored under `etc/`)

| Path | sha256 |
|---|---|
| `/etc/rsyslog.d/60-johnny-remote.conf` | `ac40a9652d93419e5edf544203de54807cb45dbfa103d214f8bbcf5d55bb2da8` |
| `/etc/systemd/journald.conf.d/61-batch10-forward-syslog.conf` | `c4c875396276951b491e799e9cdb5a090b2ca82a754967c7f310888373e51c40` |
| `/etc/modprobe.d/johnny-cis-net.conf` | `595769a1322893b3b5567bb3049898f6fe280ebd7d55df1fb8315fd111f1edb7` |

## Fixes landed during apply

- `392e791` rsyslog `CanReload=no` → `reload || try-restart`
- `e1e66e0` `RSYSLOG-KEPT` also restarts (stale daemon after failed reload)

## Still open (not blocking tool install)

- Ableton reboot proof for the AtStartup task.
- Parked: Ableton Ubuntu / Security Onion rebuild.

## Accepted

- **ksmbd** risk entry: accepted, option A (AJ, 2026-11-04 America/Chicago): leave loadable. B and C were not chosen. No modprobe change.

## Next

**Step 7 tool install** (baseline before tools), then E810 capture (step 11). Level 2 – Server after the log volume exists.
