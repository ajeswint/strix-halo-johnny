# Step 9 — EDAC (draft, not applied)

Drafted 2026-11-05 ~12:06 CT. Nothing in this step has run on Johnny, on rock-box, or on ABLETON_BOX. Grok 4.7 wrote the paste. Claude reviews and does not edit.

Johnny has one DDR5 module, and that module is non-ECC. This step records what the kernel exposes for EDAC and states that ECC correction is unavailable on the installed stick. It does not change BIOS, RAM, modules, or sysfs.

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
- Print `ECC-UNAVAILABLE` from the DIMM record below, and `STEP9-DONE` when the read finishes.

Wall time is a few seconds. There is no soak.

## DIMM record

**[Assumption]** The stick has not been replaced since the 2026-10-28 read. This paste does not run `dmidecode` (that read was root) and does not open `/sys/firmware/dmi/tables`.

AJ's `sudo dmidecode -t memory` on 2026-10-28 printed one module: `CT32G56C46S5` (a 5600 part), running at 4800 MT/s, no ECC, single channel (`docs/sessions/Johnny_OS_Session_Log_2026-10-28.csv`). The handoff still says 1× 32GB DDR5 non-ECC. BIOS RAM speed 4800 MT/s is the board maximum and is closed. The parked ECC purchase (2× Kingston `KSM56T46BD8KM-48HM`) has not been bought or seated in this step.

`ECC-UNAVAILABLE` means that installed module does not provide ECC correction. An empty EDAC tree is consistent with that. An empty tree is also what a missing driver looks like, so the paste records the two facts on separate lines (`ECC-UNAVAILABLE` and `NOTE-no-mc` or `NOTE-mc-present`). It does not treat a missing `mc*` directory as the proof of the DIMM type.

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

`igen6_edac` in that Ubuntu tag is the in-band ECC (IBECC) client driver. Its header says IBECC is what a controller uses when it does not support out-of-band ECC. The Arrow Lake IDs in that file are the U/H compute dies `0x7d06`, `0x7d20`, and `0x7d30`. If IBECC is off on a device the driver did bind, it prints `MC%d In-Band ECC is disabled` and returns `-ENODEV` ([`igen6_edac.c` at `Ubuntu-7.0.0-42.42`](https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/resolute/plain/drivers/edac/igen6_edac.c?h=Ubuntu-7.0.0-42.42)).

`ie31200_edac` in that tag is the older client out-of-band driver. Its newest HX ID there is Raptor Lake-HX `0xa702` (the comment says i9-13950HX). A search of that file for `7d1c`, `7d2d`, and `Arrow Lake` found none ([`ie31200_edac.c` at `Ubuntu-7.0.0-42.42`](https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/resolute/plain/drivers/edac/ie31200_edac.c?h=Ubuntu-7.0.0-42.42)).

`i10nm_edac` is the 10nm server controller driver. `skx_edac` is the Skylake-server family. Neither is the 285HX part.

The paste reads `/sys/bus/pci/devices/*/class` for class `0x060000` (host bridge) and compares each Intel device ID to those modules' `modinfo` aliases. `ALIAS-MATCH` means the on-disk module names that ID. `NOTE-no-alias` means it does not. `modinfo` does not load the module. This draft does not claim Johnny's host-bridge ID. The summary line is the live value.

**[Assumption]** A 285HX host bridge is not one of the three Arrow Lake-UH IDs above. If the paste prints `ALIAS-MATCH`, that assumption is wrong and the summary wins.

## Pass

The paste passes when it prints `STEP9-DONE`. That line is printed only when all of these are true:

1. The shell is not root (`id -u` is not 0).
2. `hostname --short` is `johnny` and `uname -r` is `7.0.0-42-generic`.
3. The module list, host-bridge list, and EDAC sysfs dump were written under `/home/aj/cis-audit/step9-edac/`.
4. The summary contains `ECC-UNAVAILABLE` and `DIMM-RECORD CT32G56C46S5 non-ECC single-channel 2026-10-28`.

These are recorded and do not withhold `STEP9-DONE`:

- `NOTE-no-mc` (no `mc*` directory). Expected on this stick.
- `NOTE-mc-present`. Unexpected. Bring the summary back. Do not clear it by writing `reset_counters`, and do not load a module to "explain" it.
- `NOTE-no-alias` for `igen6_edac` and `ie31200_edac`. A driver-table gap, not a failed paste.
- `NOTE-no-alias-file`. `modinfo` found no module file. On 7.0.0-42 the annotations say those drivers are modules, so this line is a finding to bring back.
- `NOTE-dmesg-denied` or `NOTE-journal-denied`. The optional log paste below is only for those notes.
- `NOTE-dmesg-stderr` or `NOTE-journal-stderr`. The read returned lines, or an empty match file, and the command also wrote on stderr. The stderr file stays in the log directory.
- `DMESG-EDAC-LINES 0` and `JOURNAL-EDAC-LINES 0` when the read was allowed and nothing matched.
- `MCE-DIR present`. Normal on this CPU. Not ECC.

`NOTE-mc-present` together with `ECC-UNAVAILABLE` is a conflict to read, not a license to change BIOS.

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
- `igen6_edac`'s `In-Band ECC is disabled` line, if it shows up in the log after a bind, means the driver saw the device and IBECC was off. That is a BIOS or DIMM fact to record. It is not a cue to flip a BIOS switch from this runbook.
- Do not enable an ECC BIOS item on a non-ECC stick. This draft does not describe that item and does not ask AJ to look for it.
- ABLETON_BOX stays out of this note. rock-box stays out of this note.

## Logs and sudo

Directory on Johnny: `/home/aj/cis-audit/step9-edac`. If that path already exists, the paste renames it with a UTC timestamp and starts clean. `aj` can `scp` it. The main paste never calls sudo.

`kernel.dmesg_restrict` is set to 1 on Johnny (CIS 1.5.5, `/etc/sysctl.d/60-johnny-cis-kernel.conf`). The kernel docs say that when `dmesg_restrict` is 1, `dmesg(8)` requires `CAP_SYSLOG` ([sysctl/kernel](https://www.kernel.org/doc/html/latest/admin-guide/sysctl/kernel.html)). The paste reads `/proc/sys/kernel/dmesg_restrict` and tries `dmesg` as `aj`. A denial becomes `NOTE-dmesg-denied`. It does not change the sysctl.

**[Assumption]** `aj` may be in group `adm` or `systemd-journal`, in which case `journalctl -k` works without sudo while `dmesg` still fails. The paste records `GROUPS` and the journal result separately. If the journal hint says the user is not seeing system messages, the line is `NOTE-journal-denied`.

The optional sudo paste is only for `NOTE-dmesg-denied` or `NOTE-journal-denied`. Skip it when both reads already produced `DMESG-EDAC-LINES` and `JOURNAL-EDAC-LINES`. It is not required for `STEP9-DONE`.

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

Do not commit the raw files. The apply session, after AJ runs the paste, puts `summary.txt` in `docs/sessions/` and a short block in the handoff.

## Paste on Johnny

One block, in an SSH session from rock-box. It does not prompt for a password.

```bash
ssh -o ServerAliveInterval=30 aj@192.168.50.152
```

Then, on Johnny:

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
      val=$(head -c 256 "$p" | tr '\n' ' ')
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

note "DIMM-RECORD CT32G56C46S5 non-ECC single-channel 2026-10-28"
note ECC-UNAVAILABLE
note STEP9-DONE
EOF
```

## Optional log paste

Run this only when `summary.txt` contains `NOTE-dmesg-denied` or `NOTE-journal-denied`. It is the sudo the main paste refused to take. It reads the kernel log and appends counts. It does not load a module and does not write EDAC sysfs.

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
| `STOP-logs-already` | `LOGS-DONE` is already in the summary. Do not append a second log pass. |
| `NOTE-chown-failed` | `LOGS-DONE` was written, then `chown` to `aj` failed. Do not run the optional paste again. |
| `STEP9-DONE` | The unprivileged probe finished. ECC on the installed stick is recorded unavailable. |
| `LOGS-DONE` | The optional sudo log read finished. Not required for the pass. |

`NOTE-no-mc`, `NOTE-mc-present`, `NOTE-no-alias`, `NOTE-dmesg-denied`, and `NOTE-journal-denied` are findings. They still allow `STEP9-DONE`.

## Collect

On rock-box, after the paste returns:

```bash
mkdir -p /home/aj/johnny-step9
scp -r aj@192.168.50.152:/home/aj/cis-audit/step9-edac /home/aj/johnny-step9/
```

Read `/home/aj/johnny-step9/step9-edac/summary.txt`. That file is what a later apply session puts in `docs/sessions/` and, as a short block, in `docs/os-handoff.md`.

Bring back the `HB` lines, `ALIAS-MATCH` or `NOTE-no-alias`, `MC-DIRS`, `CSROW-DIRS`, `DIMM-DIRS`, `RANK-DIRS`, and `ECC-UNAVAILABLE`. If the optional paste ran, also bring back `DMESG-SUDO-LINES` and `JOURNAL-SUDO-LINES`.

Leave the raw files on disk. Do not commit them.

## Rollback

No Johnny config change. No package install. No module load. Ctrl-C leaves a partial directory and does not print `STEP9-DONE`. There is no revert script. Do not run `/root/step11-revert.sh` because the EDAC tree was empty.

## After the run

Not applied. AJ has not run the paste. When `STEP9-DONE` exists, the apply session records the summary and only then moves this step off "drafted". `NOTE-no-mc` on this stick is the expected corroboration. `NOTE-mc-present` is a stop for interpretation, not a BIOS change. CIS L1 totals stay **225 PASS, 18 PASS (manual), 31 N/A, 0 FAIL** (274/274). Next open items after this draft remain 12 signed UKI and IRQ affinity later, plus running this paste when AJ chooses.
