# Step 9 — EDAC (applied)

Applied 2026-11-05 on Johnny. AJ ran both pastes from tip `e08260f`. The main paste printed `STEP9-DONE` at `2026-11-05T18:15:40Z` (~12:15 CT). The optional sudo paste printed `LOGS-DONE`. Grok 4.7 recorded the closeout. Claude reviews and does not edit. Do not run the pastes again.

The nit commit after that run (`68b22e7`) is doc-only. It does not change the live result. Three lines in the blocks below were not in the paste AJ executed: `|| true` on the sysfs `head -c`, `STOP-no-denial` on the optional paste, and the SSH command in prose. `NOTE-dmesg-denied` was already in the summary, so the optional run matches the denial that gate now checks. No module was loaded. No sysfs write. No BIOS or RAM change.

Johnny has one DDR5 module. The 2026-10-28 record says that module is non-ECC, which means no side-band ECC DIMM. `ECC-UNAVAILABLE` restates that record. It is not a measurement from sysfs. IBECC was not evaluated.

## Result

`STEP9-DONE`. `LOGS-DONE`. `NOTE-no-mc`. `NOTE-dmesg-denied`. Host bridge `0000:00:00.0` vendor `0x8086` device `0x7d1c`. `NOTE-no-alias` for `igen6_edac`, `ie31200_edac`, `i10nm_edac`, and `skx_edac`.

`edac_core` printed `KO edac_core not-loaded (builtin)` and `EDAC-POLL-MSEC 1000`. The other seven names (`igen6_edac`, `ie31200_edac`, `i10nm_edac`, `skx_edac`, `sb_edac`, `pnd2_edac`, `amd64_edac`) printed `KO` and `not-loaded`, each with a `.ko.zst` path under `/lib/modules/7.0.0-42-generic/kernel/drivers/edac/`. `MC-DIRS 0`, `CSROW-DIRS 0`, `DIMM-DIRS 0`, `RANK-DIRS 0`. Sysfs had `/sys/devices/system/edac` and `/sys/devices/system/edac/mc`, and no `mc*` controller directory.

`DMESG-RESTRICT 1`. Unprivileged `dmesg` wrote `dmesg: read kernel buffer failed: Operation not permitted`. `GROUPS` includes `adm`. `JOURNAL-EDAC-LINES 1`. That one journal match was `EDAC MC: Ver: 3.0.0` (core present, no controller bound). The sudo paste counted `DMESG-SUDO-LINES 1` and `JOURNAL-SUDO-LINES 1`. The return did not quote those two sudo line bodies, and it did not include `NOTE-dmesg-sudo-stderr`, `NOTE-journal-sudo-stderr`, or `NOTE-chown-failed`.

`MCE-DIR present`. CPU `Intel(R) Core(TM) Ultra 9 285HX`. `EUID 1000`.

`ECC-UNAVAILABLE` and `DIMM-RECORD CT32G56C46S5 non-ECC single-channel 2026-10-28` restate the 2026-10-28 `dmidecode` record. No side-band ECC DIMM is seated. IBECC was not evaluated. `0x7d1c` is not an alias of the four Intel EDAC modules on this kernel. Session copy: `docs/sessions/2026-11-05-step9-edac-applied.md`. Raw logs stay on Johnny at `/home/aj/cis-audit/step9-edac/`.

CIS L1 totals stay **225 PASS, 18 PASS (manual), 31 N/A, 0 FAIL** (274/274). Next open items are 12 signed UKI and IRQ affinity later.

## Machines

| Machine | What this step does |
|---|---|
| Johnny (`johnny`, `192.168.50.152`) | The only host the paste may run on. Minisforum MS-02 Ultra, Core Ultra 9 285HX, 1× 32GB DDR5. |
| rock-box (`aj-rock-box`) | SSH from here. Do not run the paste on rock-box. |
| ABLETON_BOX | Windows helper (`docs/hosts/ableton_box.md`). No Linux EDAC sysfs. Do not run this paste there. |

The fleet note further down is for a later Johnny-class sensor that actually has ECC DIMMs. It is not a probe of rock-box and not a probe of ABLETON_BOX.

## Goal

On Johnny, as `aj`, with no sudo in the main paste:

- List the EDAC modules the running kernel has on disk, and which of those are loaded.
- List `/sys/devices/system/edac` if it exists: `mc*`, and any `csrow*`, `dimm*`, or `rank*` directories under it.
- Read kernel-log lines that mention EDAC or ECC when `aj` is allowed to. If `dmesg` or `journalctl -k` is denied, record that. Do not start sudo from the main paste.
- Print `DIMM-RECORD` and `ECC-UNAVAILABLE` to restate the 2026-10-28 record, then `STEP9-DONE` when the read finishes. `ECC-UNAVAILABLE` is that restatement. It is not a probe measurement.

Wall time is a few seconds. There is no soak.

## DIMM record

The 2026-11-05 probe did not run `dmidecode` and did not open `/sys/firmware/dmi/tables`. `ECC-UNAVAILABLE` still restates the 2026-10-28 record. `NOTE-no-mc` is consistent with that record. It is not a new measurement of the DIMM.

AJ's `sudo dmidecode -t memory` on 2026-10-28 printed one module: `CT32G56C46S5` (a 5600 part), running at 4800 MT/s, no ECC, single channel (`docs/sessions/Johnny_OS_Session_Log_2026-10-28.csv`). The handoff still says 1× 32GB DDR5 non-ECC. BIOS RAM speed 4800 MT/s is the board maximum and is closed. The parked ECC purchase (2× Kingston `KSM56T46BD8KM-48HM`) has not been bought or seated in this step.

`ECC-UNAVAILABLE` restates that 2026-10-28 record: no side-band ECC DIMM. The probe does not measure it. An empty EDAC tree is recorded separately (`NOTE-no-mc` or `NOTE-mc-present`). A missing `mc*` directory is not the proof of the DIMM type. IBECC is not evaluated: the paste does not load `igen6_edac` and does not read an IBECC activate bit. `NOTE-mc-present` together with `ECC-UNAVAILABLE` is not always a conflict. The first is a driver registration, if one appears. The second is the old DIMM record.

## Sysfs layout

EDAC's sysfs lives at `/sys/devices/system/edac`. The kernel admin guide puts memory controllers at `mc/mcX` and says the recommended view is the `dimmX` or `rankX` directory under that controller, not a hand-walk of chip-select rows. A controller that cannot name the module uses `rankX`. A modern Intel controller that can name the module uses `dimmX`. The same guide still describes the older chip-select layout (`csrowX` plus channel). The paste counts all three names and does not require any of them ([RAS admin guide](https://docs.kernel.org/admin-guide/RAS/main.html)).

Attributes this step may read, from the sysfs ABI ([`sysfs-devices-edac`](https://www.kernel.org/doc/Documentation/ABI/testing/sysfs-devices-edac)):

| Path under `mc/mc*` | What a read means |
|---|---|
| `ce_count`, `ce_noinfo_count` | Corrected errors seen by this controller |
| `ue_count`, `ue_noinfo_count` | Uncorrected errors seen by this controller |
| `mc_name`, `size_mb`, `max_location`, `seconds_since_reset` | Controller identity, size, last slot, time since the counters were cleared |
| `(dimm\|rank)*/dimm_ce_count`, `dimm_ue_count` | Per-module or per-rank counts |
| `(dimm\|rank)*/dimm_edac_mode` | Correction mode the driver reports (the ABI example is `S4ECD4ED`) |
| `(dimm\|rank)*/dimm_mem_type`, `dimm_dev_type`, `dimm_location`, `size` | Type, device width, location, size in MB |

Do not write these. The same ABI says:

- `reset_counters` is write-only. A write zeros the CE and UE counters.
- `sdram_scrub_rate` is read/write. A write sets a scrub bandwidth.
- `dimm_label` is a label userspace may assign. A write changes it.

The paste uses `cat` and `head -c` on files it can read. It does not redirect into sysfs. `uevent`, `power`, and `subsystem` are skipped. The admin guide says the `power` directories and `subsystem` symlinks are created by sysfs and serve no EDAC purpose.

`/sys/devices/system/machinecheck` is the CPU machine-check banks. The paste records only whether that directory exists (`MCE-DIR`). It does not dump bank files, and a present machine-check directory is not an ECC counter.

The admin guide's example `modprobe amd76x_edac` is not a Johnny command. This step does not load or unload any module.

## Drivers on kernel 7.0.0-42

Ubuntu resolute's `7.0.0-42.42` annotations build these as modules on amd64: `CONFIG_EDAC_IGEN6`, `CONFIG_EDAC_IE31200`, `CONFIG_EDAC_I10NM`, `CONFIG_EDAC_SKX`. `CONFIG_EDAC_SUPPORT` is `y`. `CONFIG_EDAC_DEBUG` is `n` ([annotations](https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/resolute/plain/debian.master/config/annotations?h=Ubuntu-7.0.0-42.42)). **[Assumption]** The installed `linux-modules` package matches that policy. The paste lists the `.ko` files with `modinfo -n` and does not trust the annotation alone.

`igen6_edac` in that Ubuntu tag is the in-band ECC (IBECC) client driver. Its header says IBECC is what a controller uses when it does not support out-of-band ECC. The Arrow Lake IDs in that file are the U/H compute dies `0x7d06`, `0x7d20`, and `0x7d30`. If IBECC is off on a device the driver did bind, it prints `MC%d In-Band ECC is disabled` and returns `-ENODEV` ([`igen6_edac.c` at `Ubuntu-7.0.0-42.42`](https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/resolute/plain/drivers/edac/igen6_edac.c?h=Ubuntu-7.0.0-42.42)). Johnny has no side-band ECC DIMM seated. This paste does not evaluate IBECC.

`ie31200_edac` in that tag is the older client out-of-band driver. Its newest HX ID there is Raptor Lake-HX `0xa702` (the comment says i9-13950HX). A search of that file for `7d1c`, `7d2d`, and `Arrow Lake` found none ([`ie31200_edac.c` at `Ubuntu-7.0.0-42.42`](https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/resolute/plain/drivers/edac/ie31200_edac.c?h=Ubuntu-7.0.0-42.42)).

`i10nm_edac` is the 10nm server controller driver. `skx_edac` is the Skylake-server family. Neither is the 285HX part.

The paste reads `/sys/bus/pci/devices/*/class` for class `0x060000` (host bridge) and compares each Intel device ID to those modules' `modinfo` aliases. `ALIAS-MATCH` means the on-disk module names that ID. `NOTE-no-alias` means it does not. `modinfo` does not load the module.

The 2026-11-05 run printed host bridge `0000:00:00.0` device `0x7d1c` and `NOTE-no-alias` for `igen6_edac`, `ie31200_edac`, `i10nm_edac`, and `skx_edac`. `0x7d1c` is not one of the three Arrow Lake-UH IDs above.

## Pass

The paste passes when it prints `STEP9-DONE`. That line is printed only when all of these are true:

1. The shell is not root (`id -u` is not 0).
2. `hostname --short` is `johnny` and `uname -r` is `7.0.0-42-generic`.
3. The shell user is `aj`.
4. The module list, host-bridge list, and EDAC sysfs dump were written under `/home/aj/cis-audit/step9-edac/`.

`ECC-UNAVAILABLE` and `DIMM-RECORD CT32G56C46S5 non-ECC single-channel 2026-10-28` are printed by the script from that fixed record. They are not a pass test. Requiring them as proof would be a tautology: the script writes the same string on every successful run.

These are recorded and do not withhold `STEP9-DONE`:

- `NOTE-no-mc` (no `mc*` directory). Expected on this stick.
- `NOTE-mc-present`. A controller directory is present. Bring the summary back. Do not clear it by writing `reset_counters`, and do not load a module. Paired with `ECC-UNAVAILABLE`, it is not always a conflict.
- `NOTE-no-alias` for `igen6_edac` and `ie31200_edac`. A driver-table gap, not a failed paste.
- `NOTE-no-alias-file`. `modinfo` found no module file. On 7.0.0-42 the annotations say those drivers are modules, so this line is a finding to bring back.
- `NOTE-dmesg-denied`. `dmesg` wrote stderr and the match file is empty. That is the denial (`Operation not permitted` when `dmesg_restrict` is 1).
- `NOTE-dmesg-stderr`. `dmesg` produced matching lines and also wrote stderr. An empty match file with stderr is `NOTE-dmesg-denied`, not this line.
- `NOTE-journal-denied`. The journal hint or a permission error, and the match file is empty.
- `NOTE-journal-stderr`. The journal read produced matching lines, or an empty match file that was not a denial, and stderr was non-empty.
- `NOTE-dmesg-denied` or `NOTE-journal-denied` is the only reason to run the optional log paste. The optional paste stops with `STOP-no-denial` when neither line is in the summary.
- `DMESG-EDAC-LINES 0` and `JOURNAL-EDAC-LINES 0` when the read was allowed and nothing matched.
- `MCE-DIR present`. Normal on this CPU. Not ECC.

`NOTE-mc-present` together with `ECC-UNAVAILABLE` is not always a conflict. `ECC-UNAVAILABLE` restates the 2026-10-28 record (no side-band ECC DIMM). `NOTE-mc-present` would mean a driver registered a controller. This probe does not evaluate IBECC, so that pair does not say the DIMM record is wrong and does not say IBECC is on. Bring the summary back. Do not change BIOS from this step.

## What this step does not do

- It does not enter BIOS and does not change a memory or ECC setting.
- It does not reseat, add, or remove RAM.
- It does not `modprobe`, `insmod`, `rmmod`, or `modprobe -r`.
- It does not write `reset_counters`, `sdram_scrub_rate`, `dimm_label`, or `edac_mc_poll_msec`.
- It does not install `edac-utils`, `rasdaemon`, or an out-of-tree module.
- It does not change capture tuning, netplan, GRUB, sysctl, or the step 11 service.
- It does not reboot, power-cycle, or run `/root/step11-revert.sh`.
- It does not run on rock-box or on ABLETON_BOX.
- It does not draft step 12 (signed UKI) or IRQ affinity.
- It does not buy the parked Kingston sticks.

## Fleet note

Use this when a later Johnny-class machine boots with ECC DIMMs. The parked parts are 2× Kingston `KSM56T46BD8KM-48HM` (Minisforum-validated). Two sticks also leave single-channel. The price check stays parked in `docs/os-handoff.md`. Governance owns that purchase (`licensing-procurement` in `docs/agent-team.md`). Platform owns the host probe. This note does not place the order.

After that later boot, run this same read-only paste. Do not load a module by hand to force a directory into existence.

- `MC-DIRS` greater than 0, with `dimm*` or `rank*` under it, means a driver registered a controller. Read `dimm_edac_mode`, `ce_count`, and `ue_count`. A non-zero `ce_count` is a stick to watch. A non-zero `ue_count` is an uncorrected error. This step does not set a threshold and does not turn on `panic_on_ue`.
- `NOTE-no-mc` on a machine that was built with ECC DIMMs is a stop for that image. On today's Johnny it is the expected corroboration of the non-ECC stick, not a stop.
- `NOTE-no-alias` for both `igen6_edac` and `ie31200_edac`, after an ECC install, still with `NOTE-no-mc`, means the 7.0.0-42 tables do not name that host bridge. Record the `HB` line. Do not build or load an out-of-tree EDAC module in this step. Kernel lockdown is on. An out-of-tree module would be a later choice AJ makes, with a MOK, in its own step.
- `igen6_edac`'s `In-Band ECC is disabled` line, if it shows up in a later log after a bind, means the driver saw the device and IBECC was off. Today's paste does not evaluate IBECC and does not load that module, so that line is not a result of this step.
- Do not enable an ECC BIOS item on the seated non-ECC stick. This step does not describe that item and does not ask AJ to look for it.
- ABLETON_BOX stays out of this note. rock-box stays out of this note.

## Logs and sudo

Directory on Johnny: `/home/aj/cis-audit/step9-edac`. If that path already exists, the paste renames it with a UTC timestamp and starts clean. `aj` can `scp` it. The main paste never calls sudo.

`kernel.dmesg_restrict` is set to 1 on Johnny (CIS 1.5.5, `/etc/sysctl.d/60-johnny-cis-kernel.conf`). The kernel docs say that when `dmesg_restrict` is 1, `dmesg(8)` requires `CAP_SYSLOG` ([sysctl/kernel](https://www.kernel.org/doc/html/latest/admin-guide/sysctl/kernel.html)). The paste reads `/proc/sys/kernel/dmesg_restrict` and tries `dmesg` as `aj`. A denial becomes `NOTE-dmesg-denied`. It does not change the sysctl.

**[Assumption]** `aj` may be in group `adm` or `systemd-journal`, in which case `journalctl -k` works without sudo while `dmesg` still fails. The paste records `GROUPS` and the journal result separately. If the journal hint says the user is not seeing system messages, the line is `NOTE-journal-denied`.

The optional sudo paste runs only when the summary already has `STEP9-DONE` and at least one of `NOTE-dmesg-denied` or `NOTE-journal-denied`. The paste itself checks those lines and stops with `STOP-no-denial` otherwise. It is not required for `STEP9-DONE`.

| File | Contents |
|---|---|
| `transcript.txt` | The terminal transcript |
| `summary.txt` | The lines to bring back |
| `modules.txt` | `KO` or `NOTE-no-ko` per name, loaded or not |
| `host-bridge.txt` | PCI class `0x060000` devices |
| `alias-*.txt` | `modinfo -F alias` for the four Intel drivers |
| `edac-sysfs.txt` | Directory and file reads under `/sys/devices/system/edac` |
| `dmesg-edac.txt`, `dmesg.err` | Matching lines, or the denial |
| `journal-edac.txt`, `journal.err` | Matching lines, or the denial |
| `dmesg-edac-sudo.txt`, `journal-edac-sudo.txt` | Only if the optional sudo paste ran |

Do not commit the raw files. The applied summary is in `docs/sessions/2026-11-05-step9-edac-applied.md` and, as a short block, in `docs/os-handoff.md`.

## Paste on Johnny

Applied. AJ already ran this probe from tip `e08260f`. Do not paste it again.

From rock-box, the SSH command is `ssh -o ServerAliveInterval=30 aj@192.168.50.152`. The one block below is what runs on Johnny as `aj`. It does not prompt for a password. The block includes the post-run `|| true` on `head -c`. The executed paste did not have that `|| true`. The run still reached `STEP9-DONE`.

```bash
bash <<'EOF'
set -euo pipefail
umask 022

if [ "$(id -u)" -eq 0 ]; then
  printf '%s\n' STOP-root
  exit 1
fi
h=$(hostname --short)
if [ "$h" != johnny ]; then
  printf '%s\n' "STOP-host $h"
  exit 1
fi
k=$(uname -r)
if [ "$k" != 7.0.0-42-generic ]; then
  printf '%s\n' "STOP-kernel $k"
  exit 1
fi
if [ "$(id -un)" != aj ]; then
  printf '%s\n' "STOP-user $(id -un)"
  exit 1
fi

OUT=/home/aj/cis-audit/step9-edac
if [ -e "$OUT" ]; then
  mv "$OUT" "/home/aj/cis-audit/step9-edac.prev.$(date -u +%Y%m%dT%H%M%SZ)"
fi
mkdir -p /home/aj/cis-audit
mkdir -p "$OUT"

exec > >(tee -a "$OUT/transcript.txt") 2>&1

note() { printf '%s\n' "$*" | tee -a "$OUT/summary.txt"; }

note "HOST $h"
note "KERNEL $k"
note "DATE-UTC $(date -u +%Y-%m-%dT%H:%M:%SZ)"
note "EUID $(id -u)"
note "GROUPS $(id -nG | tr ' ' ',')"
model=$(awk -F: '/^model name/ { sub(/^[[:space:]]+/,"",$2); print $2; exit }' /proc/cpuinfo)
note "CPU $model"
if [ -r /proc/sys/kernel/dmesg_restrict ]; then
  note "DMESG-RESTRICT $(tr -d '[:space:]' < /proc/sys/kernel/dmesg_restrict)"
else
  note NOTE-no-dmesg-restrict
fi
if [ -d /sys/devices/system/machinecheck ]; then
  note MCE-DIR present
else
  note MCE-DIR absent
fi

: > "$OUT/modules.txt"
for m in edac_core igen6_edac ie31200_edac i10nm_edac skx_edac sb_edac pnd2_edac amd64_edac; do
  loaded=not-loaded
  if awk -v m="$m" '$1 == m { found=1 } END { exit(found ? 0 : 1) }' /proc/modules; then
    loaded=loaded
  fi
  if modinfo -n "$m" >"$OUT/modinfo-n.txt" 2>"$OUT/modinfo-n.err"; then
    ko=$(tr -d '[:space:]' < "$OUT/modinfo-n.txt")
    printf 'KO %s %s %s\n' "$m" "$loaded" "$ko"
  else
    printf 'NOTE-no-ko %s %s\n' "$m" "$loaded"
  fi
done | tee "$OUT/modules.txt" | while IFS= read -r line; do note "$line"; done

poll=/sys/module/edac_core/parameters/edac_mc_poll_msec
if [ -r "$poll" ]; then
  note "EDAC-POLL-MSEC $(tr -d '[:space:]' < "$poll")"
else
  note NOTE-no-edac-poll
fi

: > "$OUT/host-bridge.txt"
shopt -s nullglob
for d in /sys/bus/pci/devices/*; do
  [ -r "$d/class" ] || continue
  class=$(tr '[:upper:]' '[:lower:]' < "$d/class" | tr -d '[:space:]')
  case "$class" in
    0x060000)
      ven=$(tr '[:upper:]' '[:lower:]' < "$d/vendor" | tr -d '[:space:]')
      dev=$(tr '[:upper:]' '[:lower:]' < "$d/device" | tr -d '[:space:]')
      printf '%s class %s vendor %s device %s\n' "$(basename "$d")" "$class" "$ven" "$dev"
      ;;
  esac
done | sort > "$OUT/host-bridge.txt"
if [ ! -s "$OUT/host-bridge.txt" ]; then
  note NOTE-no-host-bridge
else
  while IFS= read -r line; do note "HB $line"; done < "$OUT/host-bridge.txt"
fi

for m in igen6_edac ie31200_edac i10nm_edac skx_edac; do
  if ! modinfo -F alias "$m" >"$OUT/alias-$m.txt" 2>"$OUT/alias-$m.err"; then
    note "NOTE-no-alias-file $m"
    continue
  fi
  matched=0
  if [ -s "$OUT/host-bridge.txt" ]; then
    while read -r _bdf _classword _class _vendorword ven _deviceword dev; do
      [ "$ven" = 0x8086 ] || continue
      case "$dev" in
        0x[0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
        *)
          note "NOTE-odd-device $dev"
          continue
          ;;
      esac
      id=${dev#0x}
      if grep -Eiq "d0000${id}sv" "$OUT/alias-$m.txt"; then
        note "ALIAS-MATCH $m $dev"
        matched=1
      fi
    done < "$OUT/host-bridge.txt"
  fi
  if [ "$matched" -eq 0 ]; then
    note "NOTE-no-alias $m"
  fi
done

: > "$OUT/edac-sysfs.txt"
if [ ! -e /sys/devices/system/edac ]; then
  printf '%s\n' NOTE-no-edac-dir >> "$OUT/edac-sysfs.txt"
else
  find /sys/devices/system/edac -xdev \( -type d -o -type f \) \
    ! -name uevent ! -name power ! -path '*/power/*' ! -path '*/subsystem' ! -path '*/subsystem/*' \
    | sort | while IFS= read -r p; do
    if [ -d "$p" ]; then
      printf 'DIR %s\n' "$p"
    elif [ -f "$p" ] && [ ! -L "$p" ] && [ -r "$p" ]; then
      val=$(head -c 256 "$p" | tr '\n' ' ' || true)
      printf 'FILE %s %s\n' "$p" "$val"
    else
      printf 'SKIP %s\n' "$p"
    fi
  done >> "$OUT/edac-sysfs.txt"
fi

mc=0
csrow=0
dimm=0
rank=0
if [ -d /sys/devices/system/edac/mc ]; then
  mc=$(find /sys/devices/system/edac/mc -mindepth 1 -maxdepth 1 -type d -name 'mc[0-9]*' | wc -l | tr -d '[:space:]')
  csrow=$(find /sys/devices/system/edac/mc -type d -name 'csrow[0-9]*' | wc -l | tr -d '[:space:]')
  dimm=$(find /sys/devices/system/edac/mc -type d -name 'dimm[0-9]*' | wc -l | tr -d '[:space:]')
  rank=$(find /sys/devices/system/edac/mc -type d -name 'rank[0-9]*' | wc -l | tr -d '[:space:]')
fi
note "MC-DIRS $mc"
note "CSROW-DIRS $csrow"
note "DIMM-DIRS $dimm"
note "RANK-DIRS $rank"
if [ "$mc" -eq 0 ]; then
  note NOTE-no-mc
else
  note NOTE-mc-present
fi
if [ -s "$OUT/edac-sysfs.txt" ]; then
  grep -E '^(NOTE-no-edac-dir|DIR )|ce_count|ue_count|edac_mode|mc_name|size_mb|/size ' "$OUT/edac-sysfs.txt" | head -n 80 | while IFS= read -r line; do
    note "SYSFS $line"
  done || true
fi

if ! command -v dmesg >/dev/null 2>&1; then
  note NOTE-no-dmesg
else
  set +e
  set +o pipefail
  dmesg --time-format=iso </dev/null 2>"$OUT/dmesg.err" | grep -Ei 'edac|ibecc|igen6|ie31200|i10nm|skx_edac|(^|[^A-Za-z])ECC([^A-Za-z]|$)' | head -n 200 > "$OUT/dmesg-edac.txt"
  set -o pipefail
  set -e
  if [ -s "$OUT/dmesg.err" ] && [ ! -s "$OUT/dmesg-edac.txt" ]; then
    note NOTE-dmesg-denied
    head -n 5 "$OUT/dmesg.err" | while IFS= read -r line; do note "DMESG-ERR $line"; done
  else
    n=$(wc -l < "$OUT/dmesg-edac.txt" | tr -d '[:space:]')
    note "DMESG-EDAC-LINES ${n:-0}"
    if [ -s "$OUT/dmesg.err" ]; then
      note NOTE-dmesg-stderr
    fi
  fi
fi

if ! command -v journalctl >/dev/null 2>&1; then
  note NOTE-no-journalctl
else
  set +e
  set +o pipefail
  journalctl -k --no-pager -o short-iso </dev/null 2>"$OUT/journal.err" | grep -Ei 'edac|ibecc|igen6|ie31200|i10nm|skx_edac|(^|[^A-Za-z])ECC([^A-Za-z]|$)' | head -n 200 > "$OUT/journal-edac.txt"
  set -o pipefail
  set -e
  denied=0
  if [ -s "$OUT/journal.err" ] && grep -Eiq 'not seeing messages|permission denied|access denied|not permitted' "$OUT/journal.err"; then
    denied=1
  fi
  if [ "$denied" -eq 1 ] && [ ! -s "$OUT/journal-edac.txt" ]; then
    note NOTE-journal-denied
    head -n 8 "$OUT/journal.err" | while IFS= read -r line; do note "JOURNAL-ERR $line"; done
  else
    n=$(wc -l < "$OUT/journal-edac.txt" | tr -d '[:space:]')
    note "JOURNAL-EDAC-LINES ${n:-0}"
    if [ -s "$OUT/journal.err" ]; then
      note NOTE-journal-stderr
    fi
  fi
fi

# Restates the 2026-10-28 dmidecode record. Not a sysfs measurement.
note "DIMM-RECORD CT32G56C46S5 non-ECC single-channel 2026-10-28"
note ECC-UNAVAILABLE
note STEP9-DONE
EOF
```

## Optional log paste

Applied. AJ already ran this after `NOTE-dmesg-denied`, and it printed `LOGS-DONE`. Do not run it again.

The block below is the sudo the main paste does not take. It reads the kernel log and appends counts. It does not load a module and does not write EDAC sysfs. `STOP-no-denial` was added after the run. The executed paste gated only on `STEP9-DONE`. The summary already contained `NOTE-dmesg-denied`, which is the line this gate now requires.

`sudo -v` prompts once. `sudo bash <<'EOF'` makes the script bash's stdin, so `dmesg` and `journalctl` are given `</dev/null`.

```bash
sudo -v
sudo bash <<'EOF'
set -euo pipefail
umask 022

h=$(hostname --short)
if [ "$h" != johnny ]; then
  printf '%s\n' "STOP-host $h"
  exit 1
fi
k=$(uname -r)
if [ "$k" != 7.0.0-42-generic ]; then
  printf '%s\n' "STOP-kernel $k"
  exit 1
fi
if ! id aj >/dev/null 2>&1; then
  printf '%s\n' STOP-no-aj
  exit 1
fi
OUT=/home/aj/cis-audit/step9-edac
if [ ! -f "$OUT/summary.txt" ] || ! grep -qx 'STEP9-DONE' "$OUT/summary.txt"; then
  printf '%s\n' STOP-no-probe
  exit 1
fi
if ! grep -Eq '^(NOTE-dmesg-denied|NOTE-journal-denied)$' "$OUT/summary.txt"; then
  printf '%s\n' STOP-no-denial
  exit 1
fi
if grep -qx 'LOGS-DONE' "$OUT/summary.txt"; then
  printf '%s\n' STOP-logs-already
  exit 1
fi

note() { printf '%s\n' "$*" | tee -a "$OUT/summary.txt"; }

exec > >(tee -a "$OUT/transcript.txt") 2>&1

set +e
set +o pipefail
dmesg --time-format=iso </dev/null 2>"$OUT/dmesg-sudo.err" | grep -Ei 'edac|ibecc|igen6|ie31200|i10nm|skx_edac|(^|[^A-Za-z])ECC([^A-Za-z]|$)' | head -n 200 > "$OUT/dmesg-edac-sudo.txt"
journalctl -k --no-pager -o short-iso </dev/null 2>"$OUT/journal-sudo.err" | grep -Ei 'edac|ibecc|igen6|ie31200|i10nm|skx_edac|(^|[^A-Za-z])ECC([^A-Za-z]|$)' | head -n 200 > "$OUT/journal-edac-sudo.txt"
set -o pipefail
set -e

dn=$(wc -l < "$OUT/dmesg-edac-sudo.txt" | tr -d '[:space:]')
jn=$(wc -l < "$OUT/journal-edac-sudo.txt" | tr -d '[:space:]')
note "DMESG-SUDO-LINES ${dn:-0}"
note "JOURNAL-SUDO-LINES ${jn:-0}"
if [ -s "$OUT/dmesg-sudo.err" ]; then
  note NOTE-dmesg-sudo-stderr
fi
if [ -s "$OUT/journal-sudo.err" ]; then
  note NOTE-journal-sudo-stderr
fi
note LOGS-DONE
chown -R aj:aj "$OUT" || note NOTE-chown-failed
EOF
```

## Stop lines

| Line | Meaning |
|---|---|
| `STOP-root` | The main paste was started as root. Run it as `aj`. |
| `STOP-host` | The shell is not on `johnny`. Do not continue on rock-box or any other host. |
| `STOP-kernel` | `uname -r` is not `7.0.0-42-generic`. Do not probe another kernel's module tree and call it this step. |
| `STOP-user` | The main paste is not running as `aj`. |
| `STOP-no-aj` | The optional paste cannot see account `aj`, so it will not append or `chown`. |
| `STOP-no-probe` | The optional sudo paste ran before `STEP9-DONE` existed. |
| `STOP-no-denial` | The summary has `STEP9-DONE` and has neither `NOTE-dmesg-denied` nor `NOTE-journal-denied`. Do not read the kernel log with sudo. |
| `STOP-logs-already` | `LOGS-DONE` is already in the summary. Do not append a second log pass. |
| `NOTE-chown-failed` | `LOGS-DONE` was written, then `chown` to `aj` failed. Do not run the optional paste again. |
| `STEP9-DONE` | The unprivileged probe finished. `ECC-UNAVAILABLE` just above it restates the 2026-10-28 DIMM record. It is not a measurement from this probe. |
| `LOGS-DONE` | The optional sudo log read finished. Not required for the pass. |

`NOTE-no-mc`, `NOTE-mc-present`, `NOTE-no-alias`, `NOTE-dmesg-denied`, and `NOTE-journal-denied` are findings. They still allow `STEP9-DONE`.

## Collect

On rock-box, after the paste returns:

```bash
mkdir -p /home/aj/johnny-step9
scp -r aj@192.168.50.152:/home/aj/cis-audit/step9-edac /home/aj/johnny-step9/
```

The summary AJ returned is already in `docs/sessions/2026-11-05-step9-edac-applied.md`. Raw files stay on Johnny. Do not commit them.

Bring back the `HB` lines, `ALIAS-MATCH` or `NOTE-no-alias`, `MC-DIRS`, `CSROW-DIRS`, `DIMM-DIRS`, `RANK-DIRS`, and `ECC-UNAVAILABLE`. If the optional paste ran, also bring back `DMESG-SUDO-LINES` and `JOURNAL-SUDO-LINES`.

Leave the raw files on disk. Do not commit them.

## Rollback

No Johnny config change. No package install. No module load. Ctrl-C leaves a partial directory and does not print `STEP9-DONE`. There is no revert script. Do not run `/root/step11-revert.sh` because the EDAC tree was empty.

## After the run

Applied. `STEP9-DONE` at `2026-11-05T18:15:40Z`. `LOGS-DONE`. Host bridge `0x7d1c`. `NOTE-no-mc`. `NOTE-dmesg-denied`. `ECC-UNAVAILABLE` restates the 2026-10-28 non-ECC DIMM record. No side-band ECC DIMM. IBECC was not evaluated. No module load, no sysfs write, no BIOS or RAM change. CIS L1 totals stay **225 PASS, 18 PASS (manual), 31 N/A, 0 FAIL** (274/274). Next open items are 12 signed UKI and IRQ affinity later.
