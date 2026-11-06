# 2026-11-06 — step 7 tools re-verify and SBOM refresh

Seat: code-writer (Sonnet). Branch `claude/step7-reverify`, PR against `claude/practical-ritchie-4c6vvf`. rock-box edits only. Read-only SSH to Johnny as `aj` (`dpkg-query`, `getcap`, xattr read, `systemctl show`, `apt-mark showhold`, `apt list --upgradable`, log reads). No sudo, no apt, no config change, no `apt update`, nothing enabled or disabled. No AJ paste needed. Token `STEP7-VERIFY-DONE` is the SSH audit.

**Result.** 16 of 17 step 7 packages match the SBOM. One drift: `bind9-dnsutils` `1:9.20.24-1ubuntu0.4` → `1:9.20.24-1ubuntu0.5` (with `bind9-host`, `bind9-libs`; same 2026-11-05 06:48:18 UTC run upgraded `libmspack0t64` and `libpcre2-8-0`). `unattended-upgrades.log` lists those five packages, so **[Inference]** it was an unattended-upgrades run.

**State.** `aj` ∈ `wireshark` (108). `dumpcap` `cap_net_admin,cap_net_raw=eip`. `suricata` disabled, inactive, Result `success`. `iperf3` disabled, inactive. Holds `secureboot-db`, `shim-signed`.

**Edits.** `docs/os-handoff.md` (rev 93, SBOM row for `bind9-dnsutils`, notes row for suricata and dumpcap); `docs/tool-install/step-7-apt.md` (Re-verified section); this note; `docs/sessions/Johnny_Step7_Verify_Session_Log_2026-11-06.csv`. No script or `etc/` file changed. `SELF-TEST`: N/A.

**Method slip, for the record.** My first `dpkg-query` over SSH printed blank versions because the remote shell expanded `${Package}` inside double quotes. Re-run with a quoted heredoc. The numbers above come from the second run.

**Open.** Other SBOM rows (kernel, systemd, dracut, etc.) were not re-read; scope was step 7 tools. The footer "Versions as of rev 3 except where noted" still applies to them.
