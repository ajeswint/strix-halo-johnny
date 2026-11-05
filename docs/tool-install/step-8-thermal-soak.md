# Step 8 — thermal soak (draft, not applied)

Drafted 2026-11-05 ~10:55 CT. Not applied. Nothing in this file has been run on Johnny or on rock-box. Grok 4.7 wrote the paste. Claude reviews it and does not edit it. AJ decides and runs the paste.

Ownership: Assurance owns the measurement (`throughput-soak` in `docs/agent-team.md`). Platform owns the apt names (`ubuntu-2604-packages`). This is one paste so AJ does not run two sudo blocks.

`stress-ng` 0.20.01-1 is already on Johnny (`docs/tool-install/step-7-apt.md`). This paste does not reinstall it. `turbostat` is not in that SBOM. The paste installs it only when the binary for kernel `7.0.0-42-generic` is missing.

## Goal

Run `stress-ng --cpu 0 --timeout 30m` on Johnny and sample `turbostat` for that same window. Record the package temperature, the hottest core temperature, package power when RAPL exposes it, and whether the package or a core counted a throttle. Leave capture tuning, BIOS, and the fan policy as they are.

The paste also takes a 60 second idle `turbostat` sample first, so the load file is not mixed with the quiet minute.

Wall time is about 31 minutes plus the probe, after `sudo` accepts the password.

## Pass

The paste passes when it prints `STEP8-DONE`. That line is printed only when all of these are true:

1. `hostname --short` is `johnny` and `uname -r` is `7.0.0-42-generic`.
2. `stress-ng` is already installed. The version is recorded. A newer version than 0.20.01-1 does not stop the paste.
3. `johnny-capture-tuning.service` is `active` and `enabled`. CPUs 1–4 still have EPP `performance`. Their idle names are still `POLL`, `C1_ACPI`, `C2_ACPI`, and `C3_ACPI`, with `POLL` and `C1_ACPI` enabled (`disable` 0) and `C2_ACPI` and `C3_ACPI` disabled (`disable` 1). CPU 0 is recorded and is not required to match that map.
4. A 2 second `turbostat` probe writes a non-empty file and does not report an MSR or permission failure.
5. `stress-ng` exits 0, and the wall clock of that command is at least 1700 seconds.
6. The 10 second `turbostat` log has at least 150 system-summary rows (about 25 minutes of samples).
7. The tuning file after the soak is byte-for-byte the same as the tuning file before it, including CPU 0.

These are recorded and do not by themselves withhold `STEP8-DONE`:

- Maximum `CoreTmp`, `PkgTmp`, and `PkgWatt` across the 10 second samples, or `NOTE-no-*` when that column is absent.
- A non-zero `CoreThr` or `PKG_%` sample. The summary line is `NOTE-throttled`. The counters are the finding. They are not a rollback.
- Thermal-zone millidegrees, hwmon fan inputs, and whether `thermald` is active.
- Kernel-journal lines in the window that match throttle, package temperature, or `thermald`.

**[Assumption]** AJ has not set a pass or fail temperature or a package-power cap. This step does not invent one. The numbers are for the later architecture budget. A thermal shutdown, a dead SSH session, or a missing `STEP8-DONE` is not a pass. Do not start a second soak in that case.

## What this step does not do

- It does not change EPP, idle states, the cpufreq governor, or `johnny-capture-tuning.service`.
- It does not edit netplan, GRUB, sysctl, or the capture NIC.
- It does not enter BIOS and does not change the fan curve.
- It does not install, start, stop, or restart `thermald`.
- It does not run `apt-get update` and does not reinstall `stress-ng`.
- It does not weaken kernel lockdown and does not load or unload a module by hand.
- It does not power-cycle, reboot, or run the step 11 revert script.
- It does not draft step 9 (EDAC), step 12 (signed UKI), or IRQ affinity.

## Load and the capture CPUs

`stress-ng --cpu 0` starts one CPU worker per configured processor (`sysconf(_SC_NPROCESSORS_CONF)`), not a pin to CPU 0. The Ubuntu 26.04 man page says a zero count selects the configured processors, and the example `stress-ng --cpu 0 --cpu-method all -t 20m` is "run cpu stressors on all configured CPUs" ([stress-ng(1) on resolute](https://manpages.ubuntu.com/manpages/resolute/man1/stress-ng.1.html)).

CPUs 1–4 stay in the scheduler's set. They will be busy for the half hour. The tuning service is not stopped, and this paste does not change their EPP or idle bits. SPAN frames can still arrive on `eno1np0`. **[Assumption]** Module 1 is not carrying production capture yet, so a half hour of busy capture CPUs is the measurement AJ asked for. The paste prints `nproc` (online) and `getconf _NPROCESSORS_CONF` (configured). It does not require either number to be 24.

**[Assumption]** The 285HX still has no SMT, so configured and online counts match. The paste does not enforce that.

## Why turbostat is sampled alongside, at 10 seconds

Upstream `turbostat(8)` has two modes. A forked command is one sample, printed when the command exits. Omitting the command prints a sample every interval (default 5 seconds). SIGINT ends interval mode and prints the current interval before exit ([turbostat.8](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/tools/power/x86/turbostat/turbostat.8)).

A single 30 minute sample would report package power as the average over the whole run, and `CoreTmp` / `PkgTmp` as one reading at the end. That misses the peak. The paste therefore runs interval mode in parallel with `stress-ng`, at 10 seconds, and sends SIGINT when `stress-ng` returns.

Ten seconds is enough for a closet fan curve and a package thermal time constant. It keeps the log small: on the order of 180 summary rows, plus one row per logical CPU. **[Assumption]** `CoreTmp` and `PkgTmp` are end-of-interval readings, so the recorded maximum is the maximum of those samples, not a proven peak between samples. `PkgWatt` is the RAPL energy delta over that 10 second window, so the recorded maximum is the hottest 10 second average, not an instantaneous spike. Throttle counters cover events between samples.

**[Assumption]** The `turbostat` in `linux-tools-7.0.0-42` still follows that upstream split. The paste does not pass a command and `--interval` together. The man page shipped on resolute is `/usr/share/man/man8/turbostat.8.gz` from `linux-tools-common` ([file list](https://packages.ubuntu.com/resolute/amd64/linux-tools-common/filelist)).

Columns are discovered from the header. The paste does not pass `--show`. A missing column on this CPU becomes `NOTE-no-*` and is not a failed install. **[Assumption]** Arrow Lake 285HX on kernel 7.0 may omit `PkgWatt` or the DTS columns. `CoreThr` is the per-interval throttle count, and the man page points at `/sys/devices/system/cpu/cpu*/thermal_throttle/` for the since-boot counters.

The same awk runs on the idle file and on the soak file.

## Packages

Checked against Ubuntu resolute (26.04), kernel source `linux` `7.0.0-42.42`:

| Package | What it ships | Source |
|---|---|---|
| `linux-tools-common` | `/usr/bin/turbostat` (the wrapper) and `turbostat.8.gz` | [resolute, 7.0.0-42.42, security](https://packages.ubuntu.com/resolute/amd64/linux-tools-common), [file list](https://packages.ubuntu.com/resolute/amd64/linux-tools-common/filelist) |
| `linux-tools-7.0.0-42-generic` | `/usr/lib/linux-tools/7.0.0-42-generic`. Depends on `linux-tools-7.0.0-42` | [resolute-updates, 7.0.0-42.42](https://packages.ubuntu.com/resolute-updates/amd64/linux-tools-7.0.0-42-generic), [file list](https://packages.ubuntu.com/resolute-updates/amd64/linux-tools-7.0.0-42-generic/filelist) |
| `linux-tools-7.0.0-42` | `/usr/lib/linux-tools-7.0.0-42/turbostat` | [file list](https://packages.ubuntu.com/resolute-updates/amd64/linux-tools-7.0.0-42/filelist) |

The wrapper on the resolute branch looks up `/usr/lib/linux-tools/$(uname -r)/` and then execs that path ([`debian/tools/generic`](https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/resolute/plain/debian/tools/generic)). **[Assumption]** `/usr/bin/turbostat` in `linux-tools-common` is that script, and `/usr/lib/linux-tools/7.0.0-42-generic` is the link the `-generic` package adds so the wrapper can see `turbostat`. The paste requires all three paths to be executable after the install check. It does not guess another kernel's tools.

`linux-tools-common` recommends `linux-perf` and `bpftool` ([package page](https://packages.ubuntu.com/resolute/amd64/linux-tools-common)). The paste uses `--no-install-recommends`. `bpftool` is already installed (step 7). Do not pull `linux-perf` for this step.

`thermald` exists in resolute ([package page](https://packages.ubuntu.com/resolute/thermald); Launchpad also shows `2.5.11-0ubuntu1.1` in updates). It is a Recommends of `linux-image-generic-hwe-26.04` ([package page](https://packages.ubuntu.com/resolute/linux-image-generic-hwe-26.04)). **[Assumption]** The server install may have skipped that Recommends. The paste records `is-active`, `is-enabled`, and the version. It does not install `thermald`.

**[Assumption]** Johnny's cached apt lists still name `linux-tools-7.0.0-42-generic`, because that is the tools package built with the installed kernel. The paste does not run `apt-get update`. If the candidate is `(none)`, it prints `STOP-no-candidate` and does not start the soak.

## Safety

Johnny is in the closet. Keep the SSH session that runs the paste open for the full half hour. Open a second SSH session first and do not paste anything into it. Use the second session only to see whether Johnny still answers.

From rock-box, twice (two terminals):

```bash
ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=120 aj@192.168.50.152
```

If the soak session dies and the second session also fails, the out-of-band path is AMT KVM. The working video path on record is the Johnny KVM icon on rock-box (Intel DMT Console, `docs/os-handoff.md` step 5). MeshCommander cleanup is closed (AJ, 2026-11-05): the computer was deleted, the node was killed, and Chrome site data for `http://127.0.0.1:3000` was cleared. MeshCommander is not sitting open. This step does not start it again.

Do not power-cycle in the middle of the soak. Ctrl-C aborts the paste. `STEP8-DONE` will be absent, and the partial files stay in the log directory. Power-cycle only if AJ decides the machine is wedged and KVM shows it is not making progress. Do not enter BIOS. Do not change the fan policy. `stress-ng` is built to push machines hot ([stress-ng(1)](https://manpages.ubuntu.com/manpages/resolute/man1/stress-ng.1.html)). Throttle, or a protective shutdown, is a result to record, not a cue to change firmware in this step.

`stress-ng` as root adjusts OOM scores so its stressors are harder to kill (same man page, `--no-oom-adjust`). This workload is CPU only. The paste runs it as `aj` through `runuser`, and still passes `--no-oom-adjust`. The added flags do not change the CPU method:

| Flag | Why |
|---|---|
| `--cpu 0 --timeout 30m` | The step 8 command. |
| `--no-oom-adjust` | Do not change OOM scores. |
| `--metrics-brief --times --tz --timestamp` | Short metric line, CPU time, thermal-zone report, timestamps in the log. Report only. |

Kernel lockdown stays as it is. If `turbostat` cannot read MSRs, the paste stops. That is not a reason to disable lockdown.

## Logs

Directory on Johnny: `/home/aj/cis-audit/step8-thermal-soak`. Step 7 already uses `~/cis-audit`, and `aj` can `scp` it. If that directory already exists, the paste renames it with a UTC timestamp and starts clean.

| File | Contents |
|---|---|
| `transcript.txt` | The terminal transcript |
| `summary.txt` | The lines to bring back. This is the file that later goes into the repo |
| `idle-turbostat.txt` | One 60 second sample, before the load |
| `soak-turbostat.txt` | 10 second samples for the load window |
| `stress-ng.txt` | `stress-ng` stdout and stderr |
| `tuning-before.txt`, `tuning-after.txt` | Service state, EPP, idle `disable` bits |
| `zones-before.txt`, `zones-after.txt` | Thermal-zone type and millidegrees |
| `hwmon-before.txt`, `hwmon-after.txt` | hwmon name, `temp*_input`, `fan*_input` |
| `throttle-before.txt`, `throttle-after.txt` | `thermal_throttle` sysfs, or `NOTE-no-throttle-sysfs` |
| `throttle-journal.txt` | Matching kernel lines since the start |
| `thermald.txt` | active, enabled, version or `not-installed` |
| `pkgs-added.txt` | Package names that apt added, empty when nothing was installed |
| `probe-turbostat.txt`, `probe-stderr.txt` | The 2 second probe |

Raw `soak-turbostat.txt` stays on Johnny and on rock-box. Do not commit it. Commit the summary, the package lines if apt installed anything, and the one header line from `soak-turbostat.txt` if a later session needs the live column names.

## Paste on Johnny

One block, in the first SSH session. `sudo -v` prompts once. The rest is root for the half hour, so the sudo timestamp does not have to survive 30 minutes. Heartbeats print every 5 minutes (`SOAK-HEARTBEAT`).

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
if [ ! -x /usr/bin/stress-ng ]; then
  printf '%s\n' STOP-no-stress-ng
  exit 1
fi
if ! command -v runuser >/dev/null 2>&1; then
  printf '%s\n' STOP-no-runuser
  exit 1
fi

OUT=/home/aj/cis-audit/step8-thermal-soak
if [ -e "$OUT" ]; then
  mv "$OUT" "/home/aj/cis-audit/step8-thermal-soak.prev.$(date -u +%Y%m%dT%H%M%SZ)"
fi
if [ ! -d /home/aj/cis-audit ]; then
  mkdir -p /home/aj/cis-audit
  chown aj:aj /home/aj/cis-audit
fi
mkdir -p "$OUT"
chown aj:aj "$OUT"

exec > >(tee -a "$OUT/transcript.txt") 2>&1

tspid=
hbpid=
cleanup() {
  trap - EXIT
  if [ -n "${tspid:-}" ] && kill -0 "$tspid" 2>/dev/null; then
    kill -INT "$tspid" 2>/dev/null || true
    wait "$tspid" 2>/dev/null || true
  fi
  if [ -n "${hbpid:-}" ] && kill -0 "$hbpid" 2>/dev/null; then
    kill "$hbpid" 2>/dev/null || true
    wait "$hbpid" 2>/dev/null || true
  fi
  if [ -d "$OUT" ]; then
    chown -R aj:aj "$OUT" || true
  fi
}
trap cleanup EXIT

note() { printf '%s\n' "$*" | tee -a "$OUT/summary.txt"; }

note "HOST $h"
note "KERNEL $k"
note "DATE-UTC $(date -u +%Y-%m-%dT%H:%M:%SZ)"
note "NPROC $(nproc)"
note "NPROC-CONF $(getconf _NPROCESSORS_CONF)"
note "STRESS-NG $(dpkg-query -W -f='${Version}' stress-ng)"

shopt -s nullglob

dump_tuning() {
  local dest=$1 c s
  {
    printf 'service-active %s\n' "$(systemctl is-active johnny-capture-tuning.service || true)"
    printf 'service-enabled %s\n' "$(systemctl is-enabled johnny-capture-tuning.service || true)"
    for c in 0 1 2 3 4; do
      printf 'epp %s %s\n' "$c" "$(cat "/sys/devices/system/cpu/cpu${c}/cpufreq/energy_performance_preference")"
      for s in /sys/devices/system/cpu/cpu${c}/cpuidle/state*; do
        printf 'idle %s %s %s %s\n' "$c" "$(basename "$s")" "$(cat "$s/name")" "$(cat "$s/disable")"
      done
    done
  } > "$dest"
}

check_tuning() {
  local f=$1 c name
  grep -q '^service-active active$' "$f" || return 1
  grep -q '^service-enabled enabled$' "$f" || return 1
  for c in 1 2 3 4; do
    grep -q "^epp ${c} performance$" "$f" || return 1
    grep -q "^idle ${c} [^ ][^ ]* POLL 0$" "$f" || return 1
    grep -q "^idle ${c} [^ ][^ ]* C1_ACPI 0$" "$f" || return 1
    grep -q "^idle ${c} [^ ][^ ]* C2_ACPI 1$" "$f" || return 1
    grep -q "^idle ${c} [^ ][^ ]* C3_ACPI 1$" "$f" || return 1
  done
  while read -r kind cpu st name dis; do
    [ "$kind" = idle ] || continue
    case "$cpu" in
      1|2|3|4)
        case "$name" in
          POLL|C1_ACPI|C2_ACPI|C3_ACPI) ;;
          *) return 2 ;;
        esac
        ;;
    esac
  done < "$f"
  return 0
}

dump_zones() {
  local dest=$1 z
  : > "$dest"
  for z in /sys/class/thermal/thermal_zone*; do
    [ -f "$z/type" ] || continue
    printf '%s %s %s\n' "$(basename "$z")" "$(cat "$z/type")" "$(cat "$z/temp")"
  done | sort > "$dest"
}

dump_hwmon() {
  local dest=$1 d f
  : > "$dest"
  for d in /sys/class/hwmon/hwmon*; do
    [ -f "$d/name" ] || continue
    printf 'NAME %s %s\n' "$(basename "$d")" "$(cat "$d/name")"
    for f in "$d"/temp*_input "$d"/fan*_input; do
      [ -e "$f" ] || continue
      printf '%s %s\n' "$(basename "$d")/$(basename "$f")" "$(cat "$f")"
    done
  done | sort > "$dest"
}

dump_throttle() {
  local dest=$1 f
  local files=(/sys/devices/system/cpu/cpu*/thermal_throttle/*)
  if [ "${#files[@]}" -eq 0 ]; then
    printf '%s\n' NOTE-no-throttle-sysfs > "$dest"
    return
  fi
  : > "$dest"
  for f in "${files[@]}"; do
    printf '%s %s\n' "$f" "$(cat "$f")"
  done | sort > "$dest"
}

if [ ! -r /sys/devices/system/cpu/cpu1/cpufreq/energy_performance_preference ]; then
  note STOP-no-epp
  exit 1
fi
dump_tuning "$OUT/tuning-before.txt"
set +e
check_tuning "$OUT/tuning-before.txt"
trc=$?
set -e
if [ "$trc" -eq 2 ]; then
  note STOP-tuning-idle-name
  cat "$OUT/tuning-before.txt"
  exit 1
fi
if [ "$trc" -ne 0 ]; then
  note STOP-tuning
  cat "$OUT/tuning-before.txt"
  exit 1
fi
note TUNING-BEFORE-OK
note "CPU0-EPP $(awk '$1 == "epp" && $2 == "0" { print $3 }' "$OUT/tuning-before.txt")"

need=0
[ -x /usr/bin/turbostat ] || need=1
[ -x /usr/lib/linux-tools/7.0.0-42-generic/turbostat ] || need=1
[ -x /usr/lib/linux-tools-7.0.0-42/turbostat ] || need=1
if [ "$need" -eq 1 ]; then
  note TOOLS-MISSING
  apt-cache policy linux-tools-common linux-tools-7.0.0-42-generic | tee "$OUT/apt-policy.txt"
  if awk '/Candidate:/ { if ($2 == "(none)") bad++ } END { exit(bad ? 0 : 1) }' "$OUT/apt-policy.txt"; then
    note STOP-no-candidate
    exit 1
  fi
  dpkg-query -W -f='${Package}\n' | sort > "$OUT/pkgs-before.txt"
  export DEBIAN_FRONTEND=noninteractive
  set +e
  apt-get install -y --no-install-recommends linux-tools-common linux-tools-7.0.0-42-generic | tee "$OUT/apt-install.txt"
  arc=$?
  set -e
  if [ "$arc" -ne 0 ]; then
    note STOP-apt
    exit 1
  fi
  dpkg-query -W -f='${Package}\n' | sort > "$OUT/pkgs-after.txt"
  comm -13 "$OUT/pkgs-before.txt" "$OUT/pkgs-after.txt" > "$OUT/pkgs-added.txt"
  note TOOLS-INSTALLED
else
  note TOOLS-PRESENT
  : > "$OUT/pkgs-added.txt"
fi
[ -x /usr/bin/turbostat ] || { note STOP-no-turbostat-bin; exit 1; }
[ -x /usr/lib/linux-tools/7.0.0-42-generic/turbostat ] || { note STOP-no-turbostat-bin; exit 1; }
[ -x /usr/lib/linux-tools-7.0.0-42/turbostat ] || { note STOP-no-turbostat-bin; exit 1; }
{
  dpkg-query -W -f='${Package}\t${Version}\n' stress-ng linux-tools-common linux-tools-7.0.0-42-generic linux-tools-7.0.0-42 || true
  if [ -s "$OUT/pkgs-added.txt" ]; then
    echo PKGS-ADDED
    while read -r pkg; do
      dpkg-query -W -f='${Package}\t${Version}\n' "$pkg" || true
    done < "$OUT/pkgs-added.txt"
  else
    echo PKGS-ADDED-NONE
  fi
} | tee "$OUT/versions.txt" | while IFS= read -r line; do note "$line"; done

{
  printf 'active %s\n' "$(systemctl is-active thermald || true)"
  printf 'enabled %s\n' "$(systemctl is-enabled thermald || true)"
  if dpkg-query -W -f='${Version}\n' thermald >"$OUT/thermald.ver" 2>/dev/null; then
    printf 'version %s\n' "$(cat "$OUT/thermald.ver")"
  else
    printf '%s\n' "version not-installed"
  fi
} > "$OUT/thermald.txt"
while IFS= read -r line; do note "THERMALD $line"; done < "$OUT/thermald.txt"

START=$(date -u +%Y-%m-%d\ %H:%M:%S)
printf '%s\n' "$START" > "$OUT/start.txt"
set +e
/usr/bin/turbostat --quiet --out "$OUT/probe-turbostat.txt" -- sleep 2 >"$OUT/probe-stdout.txt" 2>"$OUT/probe-stderr.txt"
prc=$?
set -e
if [ "$prc" -ne 0 ] || [ ! -s "$OUT/probe-turbostat.txt" ]; then
  note STOP-turbostat
  note "PROBE-RC $prc"
  if [ -s "$OUT/probe-stderr.txt" ]; then
    head -n 40 "$OUT/probe-stderr.txt"
  fi
  exit 1
fi
if [ -s "$OUT/probe-stderr.txt" ] && grep -Ei 'not found for kernel|Permission denied|Operation not permitted|cannot read MSR|failed to open MSR' "$OUT/probe-stderr.txt"; then
  note STOP-turbostat
  note "PROBE-RC $prc"
  head -n 40 "$OUT/probe-stderr.txt"
  exit 1
fi
note PROBE-OK

note IDLE-START
set +e
/usr/bin/turbostat --quiet --out "$OUT/idle-turbostat.txt" -- sleep 60 >"$OUT/idle-stdout.txt" 2>"$OUT/idle-stderr.txt"
irc=$?
set -e
if [ "$irc" -ne 0 ] || [ ! -s "$OUT/idle-turbostat.txt" ]; then
  note STOP-idle
  note "IDLE-RC $irc"
  if [ -s "$OUT/idle-stderr.txt" ]; then
    head -n 40 "$OUT/idle-stderr.txt"
  fi
  exit 1
fi
note IDLE-DONE

dump_zones "$OUT/zones-before.txt"
dump_hwmon "$OUT/hwmon-before.txt"
dump_throttle "$OUT/throttle-before.txt"

note "SOAK-START $(date -u +%Y-%m-%dT%H:%M:%SZ)"
/usr/bin/turbostat --interval 10 --quiet --out "$OUT/soak-turbostat.txt" >"$OUT/soak-stdout.txt" 2>"$OUT/soak-stderr.txt" &
tspid=$!
sleep 2
if ! kill -0 "$tspid" 2>/dev/null; then
  note STOP-turbostat-died
  if [ -s "$OUT/soak-stderr.txt" ]; then
    head -n 40 "$OUT/soak-stderr.txt"
  fi
  tspid=
  exit 1
fi

(
  i=1
  while [ "$i" -le 6 ]; do
    sleep 300
    printf '%s\n' "SOAK-HEARTBEAT $i $(date -u +%H:%M:%SZ)"
    i=$((i + 1))
  done
) &
hbpid=$!

cd "$OUT"
soak_begin=$(date +%s)
set +e
runuser -u aj -- /usr/bin/stress-ng --cpu 0 --timeout 30m --metrics-brief --times --tz --timestamp --no-oom-adjust >"$OUT/stress-ng.txt" 2>&1
src=$?
set -e
soak_end=$(date +%s)
elapsed=$((soak_end - soak_begin))
note "STRESS-RC $src"
note "STRESS-ELAPSED-SEC $elapsed"
if [ -s "$OUT/stress-ng.txt" ]; then
  grep -F 'dispatching hogs' "$OUT/stress-ng.txt" | head -n 1 | while IFS= read -r line; do note "$line"; done || true
  if grep -F -q 'successful run completed' "$OUT/stress-ng.txt"; then
    note STRESS-SUCCESS-LINE
  else
    note NOTE-no-success-line
  fi
else
  note NOTE-no-success-line
fi

if kill -0 "$tspid" 2>/dev/null; then
  kill -INT "$tspid" 2>/dev/null || true
  wait "$tspid" 2>/dev/null || true
  note TURBOSTAT-STOPPED
else
  note NOTE-turbostat-exited-early
fi
tspid=
if [ -n "${hbpid:-}" ] && kill -0 "$hbpid" 2>/dev/null; then
  kill "$hbpid" 2>/dev/null || true
  wait "$hbpid" 2>/dev/null || true
fi
hbpid=

dump_tuning "$OUT/tuning-after.txt"
dump_zones "$OUT/zones-after.txt"
dump_hwmon "$OUT/hwmon-after.txt"
dump_throttle "$OUT/throttle-after.txt"
journalctl -k --since "$START" --no-pager -o short-iso | grep -Ei 'throttl|temperature above|cpu clock|thermald|power limit|thermal' > "$OUT/throttle-journal.txt" || true

ts_report() {
  local tag=$1 file=$2
  awk -v tag="$tag" '
    function num(x) { return x ~ /^-?[0-9]+([.][0-9]+)?$/ }
    {
      cpu_at = 0
      for (i = 1; i <= NF; i++) if ($i == "CPU") cpu_at = i
      if (cpu_at && $cpu_at == "CPU") {
        delete col
        for (i = 1; i <= NF; i++) col[$i] = i
        next
      }
      if (!("CPU" in col)) next
      rows++
      if ($col["CPU"] == "-") summaries++
      n = split("CoreTmp PkgTmp PkgWatt CorWatt GFXWatt Busy% CoreThr PKG_% RAM_%", names, " ")
      for (j = 1; j <= n; j++) {
        name = names[j]
        if (!(name in col)) continue
        seen[name] = 1
        v = $col[name]
        if (!num(v)) continue
        if (!(name in max) || v + 0 > max[name] + 0) max[name] = v
      }
    }
    END {
      printf "%s-ROWS %d\n", tag, rows + 0
      printf "%s-SUMMARIES %d\n", tag, summaries + 0
      n = split("CoreTmp PkgTmp PkgWatt CorWatt GFXWatt Busy% CoreThr PKG_% RAM_%", names, " ")
      for (j = 1; j <= n; j++) {
        name = names[j]
        key = name
        gsub(/%/, "pct", key)
        if (!(name in seen)) printf "%s-NOTE-no-%s\n", tag, key
        else if (!(name in max)) printf "%s-NOTE-nonnumeric-%s\n", tag, key
        else printf "%s-MAX-%s %s\n", tag, key, max[name]
      }
    }
  ' "$file"
}

if [ -s "$OUT/idle-turbostat.txt" ]; then
  ts_report IDLE "$OUT/idle-turbostat.txt" | while IFS= read -r line; do note "$line"; done
fi
if [ ! -s "$OUT/soak-turbostat.txt" ]; then
  note STOP-no-samples
  exit 1
fi
ts_report SOAK "$OUT/soak-turbostat.txt" | while IFS= read -r line; do note "$line"; done
if [ -s "$OUT/soak-turbostat.txt" ]; then
  awk 'cpu_at { exit } { for (i = 1; i <= NF; i++) if ($i == "CPU") { print; exit } }' "$OUT/soak-turbostat.txt" | while IFS= read -r line; do note "SOAK-HEADER $line"; done
fi

note ZONES-AFTER-BEGIN
if [ -s "$OUT/zones-after.txt" ]; then
  while IFS= read -r line; do note "$line"; done < "$OUT/zones-after.txt"
else
  note NOTE-no-thermal-zone
fi
note ZONES-AFTER-END

if [ -s "$OUT/throttle-journal.txt" ]; then
  note "JOURNAL-THROTTLE-LINES $(wc -l < "$OUT/throttle-journal.txt" | tr -d ' ')"
else
  note NOTE-no-throttle-journal
fi

if cmp -s "$OUT/throttle-before.txt" "$OUT/throttle-after.txt"; then
  note THROTTLE-SYSFS-UNCHANGED
else
  note NOTE-throttle-sysfs-changed
fi

throttled=0
if grep -q '^SOAK-MAX-CoreThr ' "$OUT/summary.txt" && awk '/^SOAK-MAX-CoreThr / { if ($2 + 0 > 0) bad=1 } END { exit(bad ? 0 : 1) }' "$OUT/summary.txt"; then
  throttled=1
fi
if grep -q '^SOAK-MAX-PKG_pct ' "$OUT/summary.txt" && awk '/^SOAK-MAX-PKG_pct / { if ($2 + 0 > 0) bad=1 } END { exit(bad ? 0 : 1) }' "$OUT/summary.txt"; then
  throttled=1
fi
if [ "$throttled" -eq 1 ]; then
  note NOTE-throttled
fi

if ! cmp -s "$OUT/tuning-before.txt" "$OUT/tuning-after.txt"; then
  note STEP8-TUNING-CHANGED
  diff -u "$OUT/tuning-before.txt" "$OUT/tuning-after.txt" || true
  exit 1
fi
note TUNING-UNCHANGED

if [ "$src" -ne 0 ]; then
  note STEP8-STRESS-FAIL
  exit 1
fi
if [ "$elapsed" -lt 1700 ]; then
  note STEP8-SHORT
  exit 1
fi
sums=$(awk '/^SOAK-SUMMARIES / { print $2 }' "$OUT/summary.txt" | tail -n 1)
if [ -z "$sums" ] || [ "$sums" -lt 150 ]; then
  note STEP8-SHORT-SAMPLE
  exit 1
fi

note STEP8-DONE
EOF
```

## Stop lines

| Line | Meaning |
|---|---|
| `STOP-host` | The shell is not on `johnny`. Do not continue. |
| `STOP-kernel` | `uname -r` is not `7.0.0-42-generic`. Do not install another kernel's tools. |
| `STOP-no-stress-ng` | Step 7's package is missing. This paste does not install it. |
| `STOP-no-epp` | The cpufreq EPP file is missing. Do not change the driver. |
| `STOP-tuning` | The service is not active and enabled, EPP on CPUs 1–4 is not `performance`, or the idle map does not match step 11. The paste does not start the service and does not write sysfs. |
| `STOP-tuning-idle-name` | CPUs 1–4 grew an idle state other than `POLL`, `C1_ACPI`, `C2_ACPI`, `C3_ACPI`. |
| `STOP-no-candidate` | Apt has no candidate for `linux-tools-common` or `linux-tools-7.0.0-42-generic`. The paste does not run `apt-get update`. |
| `STOP-apt` | `apt-get install` of those two packages returned non-zero. The soak does not start. |
| `STOP-no-turbostat-bin` | The three paths are still not executable after the install check. |
| `STOP-turbostat` | The 2 second probe failed, the output was empty, or stderr reported an MSR or permission error. Lockdown stays on. |
| `STOP-turbostat-died` | Interval `turbostat` exited before the load started. |
| `STOP-idle` | The 60 second sample exited non-zero or wrote an empty file. |
| `STOP-no-samples` | The soak `turbostat` file is empty. |
| `STEP8-TUNING-CHANGED` | The load finished collecting, and the tuning file changed. No revert script is run. |
| `STEP8-STRESS-FAIL` | `stress-ng` exited non-zero. |
| `STEP8-SHORT` | Wall clock under 1700 seconds. |
| `STEP8-SHORT-SAMPLE` | Fewer than 150 summary rows. |
| `STEP8-DONE` | The pass line. |

`NOTE-throttled`, `NOTE-no-pkgwatt` (printed as `SOAK-NOTE-no-PkgWatt`), and `NOTE-no-throttle-journal` are findings. They still allow `STEP8-DONE` when the gates above passed.

## Collect

On rock-box, after the paste returns:

```bash
mkdir -p /home/aj/johnny-step8
scp -r aj@192.168.50.152:/home/aj/cis-audit/step8-thermal-soak /home/aj/johnny-step8/
```

Read `/home/aj/johnny-step8/step8-thermal-soak/summary.txt`. That file is what the apply session puts in `docs/sessions/` and, as a short block, in `docs/os-handoff.md`.

Also bring back, in the apply session only:

- The `PKGS-ADDED` lines, if apt installed anything. Those versions are the SBOM rows. Packages stay installed. Do not `apt-get remove` them as a rollback.
- The single `SOAK-HEADER` line, so the live column names are in the repo.
- `NOTE-throttled` and the max temperature and power lines.

Leave `soak-turbostat.txt`, `idle-turbostat.txt`, and `transcript.txt` on disk. They are the raw log. Do not commit them unless a later session truncates them to the header plus a few rows and says so.

## Rollback

No Johnny config change is expected. Capture tuning is read and compared, not written. BIOS and fans are not touched.

If the paste installed `linux-tools-common` and `linux-tools-7.0.0-42-generic` (and the dependency `linux-tools-7.0.0-42`), those packages stay. The apply session adds them to the SBOM. Removing them is not part of this step.

Ctrl-C leaves partial files and does not print `STEP8-DONE`. It does not need a revert script. Do not run `/root/step11-revert.sh` because the soak looked hot. That script undoes capture tuning.

## After AJ runs it

A later session, not this draft, records the summary and any new package versions in `docs/os-handoff.md` and bumps the handoff from drafted to applied. CIS L1 totals are not part of this step. Next open items after a pass stay 9 EDAC, 12 signed UKI, and IRQ affinity later.
