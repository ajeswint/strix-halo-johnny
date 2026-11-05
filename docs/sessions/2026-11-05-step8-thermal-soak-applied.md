# Step 8 — thermal soak (applied)

Applied 2026-11-05 on Johnny. Handoff rev 79. AJ ran the paste. This closeout does not change Johnny's live config. Capture tuning was compared and left as it was. No secrets are in this note.

## Result

`STEP8-DONE`. `STRESS-RC 0`. `STRESS-ELAPSED-SEC 1800`. `dispatching hogs: 24 cpu`. `SOAK-SUMMARIES 180`. `SOAK-ROWS 4500`. `TUNING-UNCHANGED`. `TOOLS-PRESENT`. `PKGS-ADDED-NONE`.

Paste `2026-11-05T17:11:19Z` (~11:11 CT). Soak start `2026-11-05T17:12:22Z` (~11:12 CT). The stress command's end is that start plus 1800 seconds, about `2026-11-05T17:42:22Z` (~11:42 CT). The summary has no separate end stamp.

Idle max: CoreTmp 44, PkgTmp 44, PkgWatt 9.23, CorWatt 2.40, Busy% 0.08, CoreThr 0, PKG_% 0.00.

Soak max: CoreTmp 92, PkgTmp 92, PkgWatt 121.06, CorWatt 114.03, Busy% 99.76, CoreThr 4484, PKG_% 6.76, GFXWatt 0.00, RAM_% 0.00.

`NOTE-throttled`. `NOTE-throttle-sysfs-changed`. `NOTE-no-throttle-journal`. No temperature or power limit was set. The notes are not a rollback.

**[Assumption]** `SOAK-MAX-CoreThr 4484` is the maximum of that column, and the system-summary row sums count columns. It may be one interval's sum across CPUs, not 4484 events on one core.

Zones after `TURBOSTAT-STOPPED` (millidegrees): `acpitz` 27800, `INT3400 Thermal` 20000, `TCPU` 66050, `TCPU_PCI` 66000, `x86_pkg_temp` 67000. Those are the end snapshot. The 92°C figures are the turbostat sample max.

`thermald` active and enabled, `2.5.11-0ubuntu1.1`. Record only. CPU 0 EPP stayed `balance_performance`.

`linux-tools-common`, `linux-tools-7.0.0-42`, and `linux-tools-7.0.0-42-generic` were already `7.0.0-42.42`. The paste added no packages.

## Unchanged

CIS L1 totals stay **225 PASS, 18 PASS (manual), 31 N/A, 0 FAIL** (274/274). Next open items are 9 EDAC, 12 signed UKI (option D), and IRQ affinity later. Capture tuning was compared and unchanged (`TUNING-UNCHANGED`, `TUNING-BEFORE-OK`).

## Logs

On Johnny: `/home/aj/cis-audit/step8-thermal-soak/`. Raw `soak-turbostat.txt` stays there. The summary text AJ pulled is below.

## Summary

```
HOST johnny
KERNEL 7.0.0-42-generic
DATE-UTC 2026-11-05T17:11:19Z
NPROC 24
NPROC-CONF 24
STRESS-NG 0.20.01-1
TUNING-BEFORE-OK
CPU0-EPP balance_performance
TOOLS-PRESENT
linux-tools-7.0.0-42	7.0.0-42.42
linux-tools-7.0.0-42-generic	7.0.0-42.42
linux-tools-common	7.0.0-42.42
stress-ng	0.20.01-1
PKGS-ADDED-NONE
THERMALD active active
THERMALD enabled enabled
THERMALD version 2.5.11-0ubuntu1.1
PROBE-OK
IDLE-START
IDLE-DONE
SOAK-START 2026-11-05T17:12:22Z
STRESS-RC 0
STRESS-ELAPSED-SEC 1800
stress-ng: 17:12:24.09 info:  [3153] dispatching hogs: 24 cpu
STRESS-SUCCESS-LINE
TURBOSTAT-STOPPED
IDLE-ROWS 25
IDLE-SUMMARIES 1
IDLE-MAX-CoreTmp 44
IDLE-MAX-PkgTmp 44
IDLE-MAX-PkgWatt 9.23
IDLE-MAX-CorWatt 2.40
IDLE-MAX-GFXWatt 0.00
IDLE-MAX-Busypct 0.08
IDLE-MAX-CoreThr 0
IDLE-MAX-PKG_pct 0.00
IDLE-MAX-RAM_pct 0.00
SOAK-ROWS 4500
SOAK-SUMMARIES 180
SOAK-MAX-CoreTmp 92
SOAK-MAX-PkgTmp 92
SOAK-MAX-PkgWatt 121.06
SOAK-MAX-CorWatt 114.03
SOAK-MAX-GFXWatt 0.00
SOAK-MAX-Busypct 99.76
SOAK-MAX-CoreThr 4484
SOAK-MAX-PKG_pct 6.76
SOAK-MAX-RAM_pct 0.00
ZONES-AFTER-BEGIN
thermal_zone0 acpitz 27800
thermal_zone1 INT3400 Thermal 20000
thermal_zone2 TCPU 66050
thermal_zone3 TCPU_PCI 66000
thermal_zone4 x86_pkg_temp 67000
ZONES-AFTER-END
NOTE-no-throttle-journal
NOTE-throttle-sysfs-changed
NOTE-throttled
TUNING-UNCHANGED
STEP8-DONE
```
