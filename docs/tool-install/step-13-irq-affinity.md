# Step 13 — IRQ affinity (applied 2026-11-05)

Rev 5, 2026-11-05 (step 13b name-match draft added; the rest of this file describes the applied `c765e01` paste). Applied on Johnny. The closeout commit `e0a7c42` is 2026-11-05 20:19:35Z (~14:19 CT), after rev 86's commit `b19ab07` at 20:13:58Z (~14:13 CT). An earlier line on this rev said ~14:18 CT. AJ's paste printed `STEP13-IRQ-DONE`. The paste was tip `c765e01`. **[Inference]** AJ's scp file sizes matched that tip. This repo does not store that size listing. Soft nits in `b19ab07` did not run and do not require a re-run. Do not re-run this step to spread the IRQs. The live pin put every recorded `eno1np0` vector on CPU 1.

## After the run

Raw transcript stays on Johnny at `/root/step13-apply.log`. This section is the summary. Grok did not SSH.

Auth: rock-box `sudo -v` failed three times. That password is rock-box's, and it was the wrong one. Johnny `ssh -t` … `sudo` succeeded on the retry. No secret is stored here.

Paste result:

- `LOCKDOWN none[integrity]confidentiality` (the script strips spaces; the same string as `none [integrity] confidentiality`)
- `PCI eno1np0 0000:01:00.0 eno2np1 0000:01:00.1`
- `CAPTURE-CPUS 1 2 3 4`
- `OK-tuning`
- `NOTE-no-irqbalance` (no 12 second wait, no `IRQ-HELD`)
- `REVERT-READY`
- `QUEUES` RX 12 and TX 12; `RPS-RX0 000000`; `XPS-TX0 000000`
- `NOTE-eno2-unrequested` for IRQs 204–215 (`eno2np1` admin-down, expected)
- `AFFINITY-BACKUP`, helper, policyscript, and unit `INSTALLED`, `UNIT-ENABLED`
- `PIN-NEEDED` then `PIN-OK`
- `CPU0-CLEAR`, `ENO2-IRQ-UNCHANGED`, `ENO3-OK`, `LOCKDOWN-UNCHANGED`
- `STEP13-IRQ-DONE`

Name mismatch. The script's queue pattern is `eno1np0-TxRx-N`, `eno1np0-rx-N`, or `eno1np0-tx-N`. Live names are `ice-eno1np0-TxRx-0` through `ice-eno1np0-TxRx-11`, `ice-0000:01:00.0:misc`, `ll_ts`, `ctrl-TxRx-0`, and `irdma-0000:01:00.0-*` completion queues. The `ice-` prefix misses the pattern, so each of those printed `NOTE-irq-fallback` and was pinned to capture CPU 1 (the first ID in the file). `irdma-` names also printed `NOTE-irq-name`. Ice vectors are IRQs 187–201. irdma vectors are IRQs 217–229. All of them are on CPU 1. CPUs 2, 3, and 4 got none of these IRQs.

During the pin, stderr repeated `/etc/johnny/irq-affinity.sh: line 28: printf: write error: Broken pipe`. Line 28 is the `printf` inside `expand_affinity`. The paste ignores SIGPIPE, the helper kept going, and `STEP13-IRQ-DONE` still printed. The noise is not a failed pin.

**[Inference]** The installed helper, policyscript, revert script, and unit are the `c765e01` blobs. That paste hashes them before install, and it reached `STEP13-IRQ-DONE`. This closeout did not re-hash the live files. Those digests:

| Installed path | c765e01 sha256 |
|---|---|
| `/etc/johnny/irq-affinity.sh` | `77b899e350bce43184d14b37e4d72c84eae3a7e0816138b1c41631b6ca32ed4e` |
| `/etc/johnny/irqbalance-policy.sh` | `7a3eeb944be0ee60ba94099b3ae4da3c905c941003c5c50221921032a9ffb0a8` |
| `/etc/systemd/system/johnny-capture-irq.service` | `9df4969fbb8e9000c13d409cc1788846ca9b1acf06275fd7336eb616cd6bb355` |
| `/root/step13-revert.sh` | `c9dd1522e278bc3bad3a711a4fdcd18b1b768d9da19dff07376a5db7dfa4cc1d` |

The `c765e01` unit does not contain `Wants=network-online.target`. The repo copy after `b19ab07` does. That line is not on Johnny. It is not a reason to re-run.

`irqbalance` is not installed (`NOTE-no-irqbalance`). The later read printed `IRQBALANCE inactive`. Nothing restarted it.

Rock-box read-only verify, same day, after `STEP13-IRQ-DONE`:

- `HOST johnny`, `KERNEL 7.0.0-42-generic`
- `ip -br link show eno1np0 eno2np1 eno3` failed: `Error: either "dev" is duplicate, or "eno2np1" is garbage.` iproute2 does not take three device names that way. The one-liner in the old verify block is wrong. `eno3` was still read from the address and route lines: UP, `192.168.50.152/24`, default via `192.168.50.1` dev `eno3`. This verify did not re-print `eno1np0` or `eno2np1` flags.
- `TUNING active enabled`
- `IRQUNIT inactive enabled`. The paste enabled the unit and ran the helper itself. It did not `systemctl start` the unit, so systemd has not marked the oneshot active. `RemainAfterExit=yes` would show `active` only after systemd runs `ExecStart`. Inactive here is not a failed pin. **[Inference]** A later boot would start the oneshot after `network-online.target`, because the unit is enabled and ordered after that target. The unit has not run under systemd, and Johnny has not rebooted since this paste.
- `IRQBALANCE inactive`
- `LOCKDOWN none[integrity]confidentiality`
- `RPS 000000`, `XPS 000000`
- Every `ENO1` IRQ 187–201 and 217–229: `smp_affinity_list` `1` and `effective_affinity_list` `1`

## Open follow-up

Name match: drafted as step 13b below. Not applied. The paragraph that stood here said the same thing in the future tense. Do not re-run the `c765e01` paste to "fix" the spread. Rollback to the first-run masks is still `sudo bash /root/step13-revert.sh`.

## Step 13b — name match (follow-up, not yet applied)

Draft. Branch `claude/step13b-name-match`, PR against `claude/practical-ritchie-4c6vvf`. Not on Johnny until AJ's paste prints `STEP13B-NAME-MATCH-DONE`. **Do not re-run the `c765e01` paste.** It now stops: `step-13-irq-affinity.sh` still pins the old helper hash `77b899e3…`, and the repo helper is a new file. Rock-box self-test checks that.

### Facts this follow-up is built on

- Live queue names, read from Johnny over read-only SSH on 2026-11-05: `ice-eno1np0-TxRx-0` … `ice-eno1np0-TxRx-11` (IRQs 189–200), `ice-0000:01:00.0:misc` (187), `ll_ts` (188), `ctrl-TxRx-0` (201), and `irdma-0000:01:00.0-AEQCEQ-0` / `-CEQ-1` … `-CEQ-12` (217–229).
- Live `/etc/johnny/irq-affinity.sh` sha256 `77b899e3…` and live unit `9df4969f…` (no `Wants=`). Both are the `c765e01` blobs.
- `/var/lib/johnny/irq-affinity-before.tsv` has the first-run masks. Queue IRQs 189–200 were `0`–`11` (the kernel's own spread). `misc`, `ll_ts`, `ctrl` and every irdma vector were `0-23`.
- `NOTE-no-irqbalance`. `IRQBALANCE inactive`.

### What changed in the helper

`etc/johnny/irq-affinity.sh`:

- Queue pattern is `^(ice-)?eno1np0-(TxRx|rx|tx)-N$`. Queue N uses `capture[N modulo 4]`. For `1 2 3 4` and 12 queues that is 1,2,3,4,1,2,3,4,1,2,3,4: three queues per CPU.
- `ice-<bdf>:misc`, `:ll_ts`, `:ctrl-TxRx-N` are `NOTE-irq-aux` and stay on the first capture CPU (CPU 1). `NOTE-irq-fallback` is now only for a name the helper has not seen.
- `irdma-*` vectors that share the PCI function are `NOTE-irdma-skip`. They are not put in the pin map, so the helper never writes them, and they are not in its rollback list. They are not queues.
- `PROC_ROOT=/proc` is a plain variable. The self-test points it at a fake tree. It is not read from the environment.
- The helper still bans nothing and still does not touch `eno2np1`, `eno3`, RSS, RPS, or XPS.

### What the 13b script does

`docs/tool-install/step-13b-name-match.sh`, run as root on Johnny. One script, fail-fast, no reboot.

1. Gates: host `johnny`, kernel `7.0.0-42-generic`, root, `SUDO_USER` `aj` or empty, lock `/run/johnny-capture-irq.lock`. Log `/root/step13b-apply.log`.
2. Stages the new helper and unit under `/root` and checks their sha256 (below).
3. Live helper must be `77b899e3…` (or already the new one); live unit must be `9df4969f…` (or already the new one); the backup TSV must exist and not be a symlink; `johnny-capture-irq.service` must be enabled. `irqbalance` active is `STOP-irqbalance-active`: this script does not re-do the ban/hold logic.
4. Runs the new helper's `preflight` and builds the map. Prints one `PLAN irq name cpu` line per pinned vector. No queue name in the map is `STOP-no-queue-names`.
5. Builds the irdma restore plan from the backup TSV (`irdma-0000:01:00.0-*` lines). Each IRQ number must still carry the same name in `/proc/interrupts` (`STOP-irdma-renamed` if not).
6. Saves current masks of every `eno1np0` PCI vector (ice and irdma) for its own rollback, and saves the old helper and unit to `/var/lib/johnny/step13b-prev/` (never overwritten).
7. Installs the new helper and unit, `systemctl daemon-reload`, runs `/etc/johnny/irq-affinity.sh apply`.
8. Writes the backup masks (`0-23`) back to the irdma vectors and reads them back.
9. Reads the spread from `/proc/interrupts` independently (`SPREAD irq name cpu n`, then `SPREAD-COUNT cpu1=3 cpu2=3 cpu3=3 cpu4=3`). Any capture CPU with zero queues is a stop.
10. Checks `eno2np1` masks unchanged, `eno3` address/route, queue counts and RPS/XPS strings unchanged, lockdown unchanged.

Does not: write `/var/lib/johnny/irq-affinity-before.tsv`, touch `irqbalance`, edit netplan, change `capture-cores`, `systemctl start/stop` anything, reboot, or run `apt`. The unit is replaced but not started: `IRQUNIT inactive enabled` stays true until the next boot.

On a stop after the first install, it prints `REVERTING-13B`, writes the saved pre-run masks back, and reinstalls the saved helper and unit (`MASKS-PUT-BACK`, `HELPER-PUT-BACK`, `UNIT-PUT-BACK`). A stop before any change prints `NO-CHANGE-13B`.

**[Assumption]** Writing `0-23` to an irdma vector is accepted, as the kernel set that mask itself at boot. If the write fails the script stops and rolls back (irdma back to CPU 1).

### Files

| Path on Johnny | Repo mirror | Mode | sha256 |
|---|---|---|---|
| `/etc/johnny/irq-affinity.sh` | `etc/johnny/irq-affinity.sh` | 0755 | new: `29f0d0d2d7e3f4c1d2a740057bbbabe4328aa23209a38c341e26edbd44ae5530`. Old live: `77b899e350bce43184d14b37e4d72c84eae3a7e0816138b1c41631b6ca32ed4e` |
| `/etc/systemd/system/johnny-capture-irq.service` | `etc/systemd/system/johnny-capture-irq.service` | 0644 | new: `03ce0ceb5f01501fed42488a2cb3697f81bc8d91ef94d4ee5f68df1a8efc2c6a` (adds `Wants=network-online.target`). Old live: `9df4969fbb8e9000c13d409cc1788846ca9b1acf06275fd7336eb616cd6bb355` |
| `/home/aj/cis-audit/step-13b-name-match.sh` | `docs/tool-install/step-13b-name-match.sh` | 0755 | `da03abac57ac277917ef9b82e3805e885ac19f9b8d2922c635f882b0fb85ee2c` |

The 13b script cannot store its own hash. The row above is the full-file digest and the self-test compares it.

### Preconditions

- Second SSH session open and AMT KVM available, as for step 13.
- Adversarial-reviewer has said OK on this exact paste.
- The rock-box checkout is on this branch. The block below runs the self-test first and stops on failure.

### Paste

On rock-box. One block, chained with `&&` so a failed self-test, `scp`, or `ssh` stops the rest. `sudo -v` is the first thing the Johnny command runs, on Johnny (a rock-box `sudo -v` would refresh the wrong machine). AJ types Johnny's sudo password at that prompt.

```bash
bash /home/aj/Projects/strix-halo-johnny/docs/tool-install/step-13-self-test.sh && \
ssh aj@192.168.50.152 'mkdir -p /home/aj/cis-audit' && \
scp /home/aj/Projects/strix-halo-johnny/docs/tool-install/step-13b-name-match.sh aj@192.168.50.152:/home/aj/cis-audit/step-13b-name-match.sh && \
scp /home/aj/Projects/strix-halo-johnny/etc/johnny/irq-affinity.sh aj@192.168.50.152:/home/aj/cis-audit/irq-affinity.sh && \
scp /home/aj/Projects/strix-halo-johnny/etc/systemd/system/johnny-capture-irq.service aj@192.168.50.152:/home/aj/cis-audit/johnny-capture-irq.service && \
ssh -t aj@192.168.50.152 'sudo -v && sudo bash /home/aj/cis-audit/step-13b-name-match.sh'
```

Success ends with `STEP13B-NAME-MATCH-DONE`. Pass lines: `STAGED-OK`, `PLAN-QUEUES 12`, `IRDMA-RESTORE-PLAN 13`, `PRE-MASKS-SAVED`, `PREV-SAVED`, `INSTALLED` for the helper and the unit, `PIN-OK`, `IRDMA-RESTORED`, twelve `SPREAD` lines, `SPREAD-COUNT cpu1=3 cpu2=3 cpu3=3 cpu4=3`, `ENO2-IRQ-UNCHANGED`, `ENO3-OK`, `LOCKDOWN-UNCHANGED`, `CPU0-CLEAR`. `NOTE-irdma-skip` appears 13 times (IRQs 217–229) and `NOTE-irq-aux` three times (187, 188, 201). The 13 and the 3 are what the live name list says. A different count is a note to read, not a stop.

The helper prints the same `printf: write error: Broken pipe` noise on line 28 as before. That is SIGPIPE ignored in `expand_affinity`, not a failed pin.

### Verify

Not part of the paste. On rock-box, read-only:

```bash
ssh aj@192.168.50.152 'echo HOST $(hostname -s); echo IRQUNIT $(systemctl is-active johnny-capture-irq.service) $(systemctl is-enabled johnny-capture-irq.service); grep -c "^Wants=network-online.target$" /etc/systemd/system/johnny-capture-irq.service; for i in $(seq 187 201) $(seq 217 229); do printf "%s %s %s eff %s\n" "$i" "$(awk -v n="$i:" "\$1==n{print \$NF}" /proc/interrupts)" "$(tr -d "[:space:]" < /proc/irq/$i/smp_affinity_list)" "$(tr -d "[:space:]" < /proc/irq/$i/effective_affinity_list)"; done; ip -br addr show eno3; ip -4 route show default'
```

Expect IRQs 189–200 on `1 2 3 4 1 2 3 4 1 2 3 4`, 187/188/201 on `1`, 217–229 on `0-23`, `Wants=` count `1`.

### Rollback

Not part of the paste. On Johnny, second SSH session or KVM, as before: `sudo bash /root/step13-revert.sh`. It restores every saved mask in the first-run TSV (queues back to `0`–`11`, misc/irdma to `0-23`), removes the helper and unit, and does not need 13b to have run. To go back only to the post-step-13 state (everything on CPU 1, old helper and unit), AJ would have to ask for that block; the 13b script does that automatically on its own failure.

### Stops (13b)

`STOP-host`, `STOP-kernel`, `STOP-not-root`, `STOP-user`, `STOP-locked`, `STOP-hash <file>`, `STOP-live-helper-hash`, `STOP-live-unit-hash`, `STOP-live-symlink`, `STOP-no-affinity-backup`, `STOP-irq-unit-not-enabled`, `STOP-irqbalance-active`, `STOP-preflight` (the helper's own `STOP-*` line comes first), `STOP-map`, `STOP-no-queue-names`, `STOP-irdma-gone|ro|name|renamed`, `STOP-no-irdma-backup`, `STOP-no-pre-masks`, `STOP-install-hash`, `STOP-irdma-write|restore`, `STOP-spread`, `STOP-spread-empty`, `STOP-eno2-irq-moved`, `STOP-eno3`, `STOP-queues-changed`, `STOP-lockdown`.

The sections below are the procedure AJ ran (`c765e01`), plus the later wording from `b19ab07`. They are not a second apply.

This is the tool-install step that replaces the open item "IRQ affinity later" from step 11. Handoff Next steps item 13 stays the finished Agent team note. That bullet is not this step. There is no `docs/tool-install/step-13-*.md` before this draft, and the tool-install sequence after step 12 is 13.

Ownership: Fast Path owns the capture-unit path `etc/systemd/system/johnny-capture.*` (`docs/agent-team.md` §4). `johnny-capture-irq.service` is that path. The policyscript and the one-line `IRQBALANCE_ARGS` edit are the smallest host change that keeps the pin from being undone. They are in the same paste, the same way step 11 put netplan and the tuning unit in one script. This draft does not change `docs/agent-team.md`.

## Machines

| Machine | What this step does there |
|---|---|
| Johnny | The script runs as root. Hostname gate `johnny`. Kernel gate `7.0.0-42-generic`. |
| rock-box | Where the required self-test and the paste are typed. Self-test first, then `scp`, then `ssh -t`. **[Assumption]** the checkout is still `/home/aj/Projects/strix-halo-johnny`, as in step 11 and `docs/agent-team.md`. |
| ABLETON_BOX | No command. Do not SSH. Do not touch the syslog collector. |

## Goal

Pin every MSI-X IRQ of the capture NIC `eno1np0` onto the CPUs listed in `/etc/johnny/capture-cores`, one CPU per IRQ, and make that pin survive `irqbalance` and a reboot. CPU 0 stays out of those masks. `eno3` stays `192.168.50.152/24` with its default route. The paste prints `STEP13-IRQ-DONE` only after that pin is in place and the checks below have passed. A draft, a stopped run, or a revert does not print it.

## Pass

All of these, from the script's own output:

- `CAPTURE-CPUS 1 2 3 4`
- `OK-tuning`
- `CPU0-CLEAR`
- `ENO2-IRQ-UNCHANGED`
- `ENO3-OK`
- `LOCKDOWN-UNCHANGED` (or `NOTE-no-lockdown` if that file cannot be read)
- `STEP13-IRQ-DONE`

When `irqbalance` is active, the script also prints `IRQ-HELD` after a 12 second wait. That line means the `eno1np0` masks were read again and still matched the chosen CPUs. The wait does not write them a second time. A mask that drifted is `STOP-irq-held`. If this run had already changed the box, that stop prints `REVERTING`. If this run changed nothing, it prints `CONFIG-KEPT` and leaves the masks where they are. When `irqbalance` is not installed, `NOTE-no-irqbalance` is a pass, not a failure, and there is no 12 second wait. `ALREADY-APPLIED` together with `STEP13-IRQ-DONE` means a second run found the pin already in place and, if `irqbalance` was active, the same read-only hold passed.

## What it does

1. Reads `/etc/johnny/capture-cores`. The sha256 must be `16fbd7d1f18d2fedb247d73edc3bc6aa040f5ab99bd3b48c35b79e543d22179b` (CPUs 1, 2, 3, 4, one per line). CPU 0 in that file is `STOP-cpu0-in-set`. The script does not rewrite the file and does not pick a new set.
2. Requires `johnny-capture-tuning.service` active and enabled, and `energy_performance_preference` `performance` on those four CPUs. It does not start the service and does not write EPP or idle bits.
3. Requires the step 11 link shape: `eno1np0` driver `ice`, speed `10000`, admin up, promiscuous, no ARP, no address; `eno2np1` driver `ice`, admin down, no address, and a different PCI device from `eno1np0`; `eno3` still `192.168.50.152/` with the default route out `eno3`.
4. Refuses to run if an XDP program is attached to `eno1np0`. It does not detach one.
5. Installs `/root/step13-revert.sh` before it records IRQ masks and before it edits `irqbalance`.
6. Saves the current `smp_affinity_list` of each requested `eno1np0` and `eno2np1` MSI-X IRQ to `/var/lib/johnny/irq-affinity-before.tsv` once, before any `irqbalance` restart. The line format is `irq|mask|name`. A later run prints `BACKUP-KEPT` and does not overwrite that file. Revert writes both sets back. The paste still does not choose new CPUs for `eno2np1`. An `eno2np1` MSI vector with no `/proc/irq` entry is `NOTE-eno2-unrequested` and is left out of the save. An empty save prints `NOTE-eno2-no-proc` and `ENO2-IRQ-UNCHANGED`. An `eno1np0` MSI vector with no `/proc/irq` entry is `STOP-eno1-unrequested` before any mask write. On a first run that stop prints `NO-CHANGE`. The revert script may already be installed. No IRQ mask was written. A first real run can hit this if `ice` allocates MSI vectors it has not requested. That stop is the fail-safe.
7. Writes one capture CPU into each `eno1np0` IRQ's `smp_affinity_list`. Queue IRQs whose `/proc/interrupts` name matches `eno1np0-TxRx-N`, `eno1np0-rx-N`, or `eno1np0-tx-N` use CPU `capture[N modulo 4]`. **That is the `c765e01` helper. It missed the live `ice-` prefix. The repo helper after step 13b accepts `[ice-]eno1np0-…` and skips `irdma-*` vectors.** Every other MSI-X IRQ of that PCI device (misc, `ll_ts`, or a name this draft has not seen) uses the lowest capture CPU, which is CPU 1 for the current file. The script prints `NOTE-irq-name` for a name that is neither `eno1np0…` nor `ice-…`, and still pins it. A name that mentions `eno2np1`, `eno3`, or `eno4` is `STOP-irq-foreign` before the write.
8. If `irqbalance.service` exists, bans both ice PFs from balancing so the restart cannot move `eno2np1`, and so later intervals cannot undo the `eno1np0` pin. It does not stop or mask `irqbalance`. It does not set `IRQBALANCE_BANNED_CPUS` or `IRQBALANCE_BANNED_CPULIST`.
9. Enables `johnny-capture-irq.service` so a boot runs `/etc/johnny/irq-affinity.sh apply` again. The unit `After=` and `Wants=` `network-online.target`. It has no `ExecStop` and no retry. If `eno1np0` is not up when the oneshot runs, the unit fails and stays failed until a later `systemctl start johnny-capture-irq.service`. Disabling the unit does not restore masks. The revert script does.

## What it does not do

- No reboot, no `apt`, no GRUB, no `update-initramfs`, no sudoers, no `NOPASSWD`.
- Does not edit netplan, the `eno1np0` promiscuous drop-in, or `eno2np1`'s `activation-mode`.
- Does not write `eno2np1` IRQ masks. See the decision below.
- Does not write `eno3` or `eno4` sysfs, and does not ban `eno3` in the policyscript.
- Does not change RSS, the queue count, ring sizes, offloads, or coalescing. No `ethtool -L`, `-G`, `-K`, `-X`, or `-C`.
- Does not write `rps_cpus` or `xps_cpus`. The script records `rx-0` `rps_cpus`, `tx-0` `xps_cpus`, and the queue counts, and stops if those strings change.
- Does not load a DDP package, attach an XDP program, or leave one attached.
- Does not change the cpufreq governor, EPP, or idle states.
- Does not weaken kernel lockdown. It reads `/sys/kernel/security/lockdown` and stops if that string changes.
- Does not set `isolcpus`, `irqaffinity=`, or any other kernel command line.

## Decisions

### `eno2np1` is not pinned

`eno2np1` is admin-down (`activation-mode: off` from step 11). The SFP+8 DAC is out and the switch port is disabled. Moving its IRQs onto CPUs 1–4 would share the capture CPUs with a port that has no frames. The script records every `eno2np1` MSI-X `smp_affinity_list` before it changes anything else, and `ENO2-IRQ-UNCHANGED` means those strings are the same after the pin and, when `irqbalance` is active, after the 12 second wait.

The policyscript still returns `ban=true` for the `eno2np1` PCI device. That is not a pin. It stops `irqbalance`, if it is restarted, from moving those vectors as a side effect. CPU 0 may remain in the `eno2np1` mask. That is accepted. Those vectors are not the mirror path. An admin-up `eno2np1` is `STOP-eno2-up`. The script does not bring the port down. The same PCI device for both ports is `STOP-eno2-same-pci`.

`msi_irqs` lists allocated vectors. `/proc/irq/N` exists only after the driver requests that vector. An admin-down port can have allocated vectors and no `/proc/irq` entry. Those are skipped. A requested `eno2np1` vector is saved and must keep the same mask (`STOP-eno2-irq-moved` if it changes).

**[Assumption]** The `msi_irqs` directory still exists while the PF is admin-down, because the driver probed the function. If that directory is missing, the script stops with `STOP-no-msi eno2np1` before it writes an `eno1np0` mask.

### CPU 0 stays free of capture IRQs

`/etc/johnny/capture-cores` is the set. The hash gate is the membership test. Each `eno1np0` IRQ is given exactly one CPU from that set. After the write, `smp_affinity_list` must expand to that one CPU. If `effective_affinity_list` exists and is non-empty, it must be the same CPU. Empty or absent effective affinity prints `NOTE-effective-empty` or `NOTE-no-effective` and is not a failure. A non-empty effective mask that names any other CPU, including CPU 0, is `STOP-effective` and the run reverts.

Housekeeping IRQs, including `eno3`, are not moved by this script. `irqbalance` may still place them on CPUs 1–4. This step does not ban those CPUs. Banning CPUs 1–4 would push `eno3` and the disk toward CPU 0, which is the opposite of keeping CPU 0 free for the host.

### RPS, XPS, and RSS stay deferred

Step 11 left IRQ affinity, RSS, and RPS for the point where a capture program stays loaded. This step is only the IRQ pin.

RPS (`/sys/class/net/eno1np0/queues/rx-*/rps_cpus`) steers skbs in software after the driver. Native XDP runs in NAPI on the IRQ's CPU. RPS does not move that. XPS (`xps_cpus`) places transmit queues. `eno1np0` has no address and ARP is off, so it should not transmit. RSS already chooses a queue in hardware. Pinning the queue's IRQ chooses the CPU. Changing the indirection table or the queue count is a different step. The kernel scaling doc is the split used here: RSS is the hardware queue, the IRQ affinity is which CPU that queue's interrupt may use, and RPS is a separate software map ([scaling](https://docs.kernel.org/networking/scaling.html)).

The paste does not call `ethtool -X` or `-L`. It stops if the recorded RPS or XPS string, or the queue-directory count, changes during the run.

### `irqbalance` is not stopped

The ice driver doc's aRFS example says to stop `irqbalance` until the next reboot ([ice](https://docs.kernel.org/networking/device_drivers/ethernet/intel/ice.html)). This step does not do that. A stop would leave every other IRQ, including `eno3`, wherever it last sat, and a mask would do the same across reboot. The paste bans only the two ice PF devices.

Ubuntu 26.04 publishes `irqbalance` `1.9.4-3` ([source package](https://packages.ubuntu.com/source/resolute/irqbalance)). Debian's build of that version installs the env file as `/etc/default/irqbalance` and points the unit's `EnvironmentFile` at that path ([debian/rules](https://sources.debian.org/src/irqbalance/1.9.4-3/debian/rules/), [debian/irqbalance.install](https://sources.debian.org/data/main/i/irqbalance/1.9.4-3/debian/irqbalance.install)). **[Assumption]** Johnny's unit, if installed, matches that. The script reads `systemctl cat irqbalance.service` and stops with `STOP-irqbalance-env` unless the last `EnvironmentFile` is `/etc/default/irqbalance`. An `Environment=` line that sets `IRQBALANCE_*` is the same stop. This draft has not seen Johnny's unit. `irqbalance` is not in the handoff SBOM. Absence is `NOTE-no-irqbalance`. A process named `irqbalance` without the unit is `STOP-irqbalance-unknown`. The script does not install the package.

The env file is edited only when every uncommented `IRQBALANCE_ARGS` is missing, empty, or already `--policyscript=/etc/johnny/irqbalance-policy.sh`. Any other value is `STOP-irqbalance-args` before a write. An uncommented non-empty `IRQBALANCE_BANNED_CPUS` or `IRQBALANCE_BANNED_CPULIST` is `STOP-irqbalance-banned` before a write. The first-run file is copied to `/var/lib/johnny/irqbalance.default.pre-step13` and not overwritten later.

irqbalance 1.9.4 runs the policyscript as `exec <script> <pci-sysfs-dir> <irq>` ([classify.c at v1.9.4](https://github.com/Irqbalance/irqbalance/blob/v1.9.4/classify.c)). The PCI directory is `/sys/bus/pci/devices/<bdf>`. The script prints `ban=true` when that directory is `eno1np0`'s device or `eno2np1`'s device, and prints nothing otherwise. Exit is 0. The man page describes the same `ban=true` key ([irqbalance.1 at v1.9.4](https://github.com/Irqbalance/irqbalance/blob/v1.9.4/irqbalance.1)).

If `irqbalance` is `active`, and its command line does not already contain that policyscript argument, the paste restarts the unit and then requires the argument on the main PID's command line (`STOP-irqbalance-cmd` if it never appears). It then waits 12 seconds. The default sample interval is 10 seconds ([same man page](https://github.com/Irqbalance/irqbalance/blob/v1.9.4/irqbalance.1)). **[Assumption]** Johnny is on that default, because a custom `IRQBALANCE_ARGS` would already have stopped the paste. After the wait the script reads `eno1np0` masks again with `map_needs_write` and does not write them. `IRQ-HELD` means none of them needed a rewrite, and the `eno2np1` masks, `eno3`, and the RPS/XPS strings were unchanged. `STOP-irq-held` means at least one `eno1np0` mask moved during the wait. If this run had changed the box, the script prints `REVERTING` and runs `/root/step13-revert.sh`. If this run changed nothing (`CONFIG-KEPT`), it does not revert and it does not write the masks back. The command line check is not that proof. `inactive` or `failed` is left that way (`NOTE-irqbalance-inactive`). The paste does not start `irqbalance`. `activating` or `deactivating` is `STOP-irqbalance-state` before a change.

1.9.4-3 dropped `ProtectKernelTunables=yes` ([changelog](https://sources.debian.org/data/main/i/irqbalance/1.9.4-3/debian/changelog)). **[Assumption]** the policyscript can read `/sys/class/net` from inside the service. If it cannot, `irqbalance` will not ban the ice IRQs. The 12 second read will see the moved masks and print `STOP-irq-held`. It does not pin them again to hide that. Revert runs only when this run had already changed the box.

### Names and managed IRQs

**[Assumption]** Ubuntu `7.0.0-42-generic` matches mainline `v7.0` ice IRQ names closely enough for the round-robin above. In that tree, combined queues are named `<ifname>-TxRx-<n>` and the non-queue vector is `ice-<driver-device>:misc` ([ice_main.c at v7.0](https://github.com/torvalds/linux/blob/v7.0/drivers/net/ethernet/intel/ice/ice_main.c)). The same file calls `netif_set_affinity_auto()`, which spreads queue affinity with `cpumask_local_spread` across the node, including CPU 0, until userspace writes a mask ([net/core/dev.c at v7.0](https://github.com/torvalds/linux/blob/v7.0/net/core/dev.c)). The Launchpad tree for `Ubuntu-7.0.0-42.42` did not answer from this draft, so the script does not require those strings. It pins the MSI-X set from `/sys/class/net/eno1np0/device/msi_irqs`. An `eno1np0` name in `/proc/interrupts` whose IRQ is not in that set is `STOP-irq-outside-msi`. A requested name that is not `eno1np0-TxRx-N`, `eno1np0-rx-N`, or `eno1np0-tx-N` is `NOTE-irq-fallback` and is pinned to the lowest capture CPU (CPU 1 for the current file). That includes the misc vector. It is a note, not a stop. **Live names turned out to be `ice-eno1np0-TxRx-N`; step 13b fixes the match. Sections above this one were written before that was known.**

Writes go to `/proc/irq/N/smp_affinity_list`, which is the CPU-list form of the allowed mask ([IRQ affinity](https://docs.kernel.org/core-api/irq/irq-affinity.html)). If that file is not writable, the paste stops with `STOP-affinity-ro` before it saves masks, installs the unit, or edits `irqbalance`. Managed interrupts are not movable from `/proc` ([managed IRQs](https://docs.kernel.org/core-api/irq/managed_irq.html)). This step does not set `isolcpus=managed_irq` and does not touch GRUB. A failed write is `STOP-affinity-write` and reverts.

**[Inference]** A userspace write updates the NAPI affinity notifier's stored mask, so a later `irq_set_affinity()` from `napi_restore_config` keeps the pin. That inference is from `netif_napi_irq_notify` in the `v7.0` file above. The paste does not bounce the link to test it. **[Inference]** On a later boot the enabled oneshot would re-apply the pin after `network-online.target`. That has not happened. The unit has not run under systemd, and there has been no reboot since this paste.

## Files the paste writes

These repo files are the bytes the paste installs. They are not on Johnny until `STEP13-IRQ-DONE`.

| Path on Johnny | Repo mirror | Mode | sha256 |
|---|---|---|---|
| `/etc/johnny/irq-affinity.sh` | `etc/johnny/irq-affinity.sh` | 0755 | `c765e01` blob, live now: `77b899e350bce43184d14b37e4d72c84eae3a7e0816138b1c41631b6ca32ed4e`. Repo file after step 13b: `29f0d0d2d7e3f4c1d2a740057bbbabe4328aa23209a38c341e26edbd44ae5530` (see step 13b) |
| `/etc/johnny/irqbalance-policy.sh` | `etc/johnny/irqbalance-policy.sh` | 0755 | `7a3eeb944be0ee60ba94099b3ae4da3c905c941003c5c50221921032a9ffb0a8` |
| `/etc/systemd/system/johnny-capture-irq.service` | `etc/systemd/system/johnny-capture-irq.service` | 0644 | repo file after `b19ab07`: `03ce0ceb5f01501fed42488a2cb3697f81bc8d91ef94d4ee5f68df1a8efc2c6a` (has `Wants=network-online.target`). Not the live file. Live install from `c765e01`: `9df4969fbb8e9000c13d409cc1788846ca9b1acf06275fd7336eb616cd6bb355` (no `Wants=`). Soft-nit `Wants=` is not on Johnny. |
| `/root/step13-revert.sh` | `docs/tool-install/step-13-revert.sh` | 0755 | `c9dd1522e278bc3bad3a711a4fdcd18b1b768d9da19dff07376a5db7dfa4cc1d` |
| `/home/aj/cis-audit/step-13-irq-affinity.sh` | `docs/tool-install/step-13-irq-affinity.sh` | 0755 | `701cdae4eb871a7e5a26071866c813f2d1e2baf97e431585323515f2922bc14d` |

`/etc/johnny/capture-cores` is read, not written. sha256 stays `16fbd7d1f18d2fedb247d73edc3bc6aa040f5ab99bd3b48c35b79e543d22179b`.

The helper is `etc/johnny/irq-affinity.sh`. The apply script copies the helper, the policyscript, the unit, and the revert script to `/root` (mode 0755 or 0644, root-owned), checks those sha256 values, and sources `/root/step13-helper.sh`. It does not source the copy under `/home/aj/cis-audit`. `aj` can write that directory. `/root` is not writable by `aj`. It does not check its own sha256. That digest covers the constants in the file, so the file cannot contain it. The table row for `step-13-irq-affinity.sh` is the full-file digest. The self-test compares the repo file to that row.

Not mirrored, created on Johnny by a successful or reverted run:

| Path | Purpose |
|---|---|
| `/var/lib/johnny/irq-affinity-before.tsv` | first-run `eno1np0` and `eno2np1` masks. Kept so a later revert still restores them |
| `/var/lib/johnny/irqbalance.default.pre-step13` | first-run `/etc/default/irqbalance` |
| `/var/lib/johnny/step13-irqbalance-was-active` | `active`, `inactive`, or `failed` |
| `/root/step13-apply.log` | transcript of this run. A previous log is renamed to `/root/step13-apply.log.1` before the new one is opened. `STOP-host`, `STOP-kernel`, and `STOP-not-root` happen before that rename |
| `/etc/default/irqbalance` | one `IRQBALANCE_ARGS` line, only if the unit exists. Hash is whatever the script prints at apply time. This draft does not invent it |

## Preconditions

- Second SSH session already open, and AMT KVM available. The paste does not `netplan apply`. It can restart `irqbalance`. If `eno3` drops, the KVM console runs the rollback below.
- The rock-box checkout contains this commit. The self-test below has printed `SELF-TEST-OK`. If any of the five `scp` sources is missing, stop. Do not clone another copy in this step.
- `aj` has no passwordless sudo. The script has no sudoers change.
- Step 11 is still applied: `eno1np0` promisc + `NOARP` at 10000, `eno2np1` admin-down, tuning service active. This paste does not repair that shape.

## Required check

On rock-box, before the paste. This is required. It does not SSH and does not write a NIC. Stop if it does not print `SELF-TEST-OK`.

```bash
bash /home/aj/Projects/strix-halo-johnny/docs/tool-install/step-13-self-test.sh
```

The writer ran that script on the draft host. It printed `SELF-TEST-OK`. The apply script, run on that same host, printed `STOP-host` and exited 1 before creating a log. That host is not Johnny.

A `STEP13-IRQ-DONE` from tip `c765e01` does not need this check again.

## Paste

On rock-box, after `SELF-TEST-OK`. One block. There is no `sudo -v`. That command would refresh sudo on rock-box only, and Johnny's sudo is the prompt on the `ssh -t` line. The script runs as root on Johnny.

```bash
ssh aj@192.168.50.152 'mkdir -p /home/aj/cis-audit'
scp /home/aj/Projects/strix-halo-johnny/docs/tool-install/step-13-irq-affinity.sh aj@192.168.50.152:/home/aj/cis-audit/step-13-irq-affinity.sh
scp /home/aj/Projects/strix-halo-johnny/docs/tool-install/step-13-revert.sh aj@192.168.50.152:/home/aj/cis-audit/step-13-revert.sh
scp /home/aj/Projects/strix-halo-johnny/etc/johnny/irq-affinity.sh aj@192.168.50.152:/home/aj/cis-audit/irq-affinity.sh
scp /home/aj/Projects/strix-halo-johnny/etc/johnny/irqbalance-policy.sh aj@192.168.50.152:/home/aj/cis-audit/irqbalance-policy.sh
scp /home/aj/Projects/strix-halo-johnny/etc/systemd/system/johnny-capture-irq.service aj@192.168.50.152:/home/aj/cis-audit/johnny-capture-irq.service
ssh -t aj@192.168.50.152 'sudo bash /home/aj/cis-audit/step-13-irq-affinity.sh'
```

Success ends with `STEP13-IRQ-DONE`. When `irqbalance` is active, that line is printed only after `IRQ-HELD`. The transcript is `/root/step13-apply.log`. The paste sleeps 12 seconds in that SSH session when `irqbalance` is active, then reads the masks. It does not write them again. SIGHUP and SIGPIPE are ignored. A dropped SSH session still runs the rollback if this run had already changed the box.

A failure before a change leaves the affinity and `irqbalance` config as they were. The revert script may already be at `/root/step13-revert.sh`. A failure after a change prints `REVERTING` and runs that script. A first run that stops before a change prints `NO-CHANGE`. A later run that stops before a change, with the helper or the unit or the mask save already present, prints `CONFIG-KEPT`. A rerun that writes a file again and then fails rolls back to the first-run affinity save. After `STEP13-IRQ-DONE`, do not rerun unless that rollback is acceptable.

The script refuses any host other than `johnny` (`STOP-host`) and any kernel other than `7.0.0-42-generic` (`STOP-kernel`) before it opens the log. `STOP-not-root` is the same, before the log. `SUDO_USER` must be `aj` when it is set (`STOP-user`). An empty `SUDO_USER` prints `NOTE-no-sudo-user` and continues. That is the KVM root shell.

## Verify

Not part of the paste. On rock-box, after `STEP13-IRQ-DONE`, read-only:

```bash
ssh aj@192.168.50.152 'echo HOST $(hostname -s); echo KERNEL $(uname -r); ip -br link show dev eno1np0; ip -br link show dev eno2np1; ip -br link show dev eno3; ip -br addr show eno3; ip -4 route show default; echo TUNING $(systemctl is-active johnny-capture-tuning.service) $(systemctl is-enabled johnny-capture-tuning.service); echo IRQUNIT $(systemctl is-active johnny-capture-irq.service) $(systemctl is-enabled johnny-capture-irq.service); echo IRQBALANCE $(systemctl is-active irqbalance.service || true); echo LOCKDOWN $(tr -d "[:space:]" < /sys/kernel/security/lockdown); echo RPS $(tr -d "[:space:]" < /sys/class/net/eno1np0/queues/rx-0/rps_cpus); echo XPS $(tr -d "[:space:]" < /sys/class/net/eno1np0/queues/tx-0/xps_cpus); for n in /sys/class/net/eno1np0/device/msi_irqs/*; do i=$(basename "$n"); printf "ENO1 %s %s %s\n" "$i" "$(tr -d "[:space:]" < /proc/irq/$i/smp_affinity_list)" "$(tr -d "[:space:]" < /proc/irq/$i/effective_affinity_list)"; done'
```

The 2026-11-05 verify used `ip -br link show eno1np0 eno2np1 eno3`. That failed: `Error: either "dev" is duplicate, or "eno2np1" is garbage.` The block above is the corrected read, one `ip -br link show dev` per name. It was not re-run for this note. Do not re-run the affinity paste to fix that one-liner.

What that verify actually printed: `HOST johnny`, `KERNEL 7.0.0-42-generic`, `eno3` `192.168.50.152/24`, default via `192.168.50.1` dev `eno3`, tuning `active enabled`, IRQ unit `inactive enabled` (enabled, not active), `IRQBALANCE inactive`, lockdown `none[integrity]confidentiality`, RPS and XPS `000000`. IRQs 187–201 and 217–229 are mask `1` and effective `1`. This run did not spread them across CPUs 2–4.

`IRQ-HELD` in the paste log is the same kind of read, done 12 seconds after the pin, inside the paste. `STEP13-IRQ-DONE` after an active `irqbalance` means that read still matched. A mask outside `1`–`4` means the hold did not stick. The paste should have printed `STOP-irq-held` instead of `STEP13-IRQ-DONE`. If that run had changed the box, it also prints `REVERTING`. If it had changed nothing, it prints `CONFIG-KEPT` and leaves the masks. An `ENO1` line that errors because `/proc/irq` is missing is an allocated vector the driver did not request. The paste treats that on `eno1np0` as `STOP-eno1-unrequested` before it writes. A first run then prints `NO-CHANGE`.

## Rollback

Not part of the paste. On Johnny, from the second SSH session or the KVM console, only after the paste has installed the script:

```bash
sudo bash /root/step13-revert.sh
```

That script restores `eno1np0` masks from `/var/lib/johnny/irq-affinity-before.tsv`, copies `/var/lib/johnny/irqbalance.default.pre-step13` back onto `/etc/default/irqbalance` when the backup exists, deletes the policyscript, the helper, and `johnny-capture-irq.service`, and restarts `irqbalance` only if the recorded state was `active`. It prints `NOTE-irqbalance-will-balance` in that case: once the ban is gone, `irqbalance` may move the ice IRQs again. That is the pre-step state. It does not change netplan, promiscuous mode, `capture-cores`, or `johnny-capture-tuning.service`. It does not reboot. Safe to run twice. It prints `REVERTED`.

Before the paste, `/root/step13-revert.sh` does not exist. There is nothing to roll back.

## Stops

The script prints the specific `STOP-*` line and exits non-zero. After a change, it also prints `REVERTING`.

| Line | When |
|---|---|
| `STOP-host` / `STOP-kernel` / `STOP-not-root` / `STOP-user` | Wrong machine, kernel, uid, or sudo user. No log file yet for the first three. |
| `STOP-cores-hash` / `STOP-cpu0-in-set` | `capture-cores` is not the step 11 file, or it lists CPU 0. |
| `STOP-tuning` / `STOP-tuning-epp` | The tuning unit is not active and enabled, or a capture CPU is not `performance`. |
| `STOP-eno1-link` / `STOP-eno1-flags` / `STOP-eno1-addr` | `eno1np0` is not the step 11 capture shape. |
| `STOP-eno2-up` / `STOP-eno2-same-pci` / `STOP-eno2-irq-moved` | `eno2np1` is up, shares a PCI device, or its mask changed. |
| `STOP-eno3-addr` / `STOP-eno3-route` / `STOP-eno3-down` | Management link is not the reserved address and route. |
| `STOP-xdp-present` | An XDP program is attached. The script does not detach it. |
| `STOP-eno1-unrequested` | An `eno1np0` MSI vector has no `/proc/irq` entry. No mask write. A first run prints `NO-CHANGE`. Possible on the first real run if `ice` allocated vectors it has not requested. |
| `STOP-irq-held` | After the 12 second wait, an `eno1np0` mask is not the chosen CPU. The script does not write it back. `REVERTING` only if this run changed the box. Otherwise `CONFIG-KEPT`. |
| `STOP-affinity-ro` | Userspace cannot write the mask. No unit install and no `irqbalance` edit. |
| `STOP-irqbalance-env` / `STOP-irqbalance-args` / `STOP-irqbalance-banned` / `STOP-irqbalance-state` / `STOP-irqbalance-unknown` | The unit is not the Debian shape, or another ban is already set, or a stray daemon is running. |
| `STOP-effective` / `STOP-queues-changed` / `STOP-lockdown` | The pin did not land, RPS/XPS or the queue count moved, or lockdown changed. |
| `STOP-revert-failed` | The rollback itself failed. Use the KVM console and the revert script. |

## Sources

- `/proc/irq/N/smp_affinity_list`: <https://docs.kernel.org/core-api/irq/irq-affinity.html>
- Managed IRQs cannot be moved from userspace: <https://docs.kernel.org/core-api/irq/managed_irq.html>
- RSS, RPS, and XPS are different maps: <https://docs.kernel.org/networking/scaling.html>
- ice aRFS text says to stop `irqbalance`. This step bans the two PFs instead: <https://docs.kernel.org/networking/device_drivers/ethernet/intel/ice.html>
- **[Assumption]** `7.0.0-42` ice names and `netif_set_affinity_auto`: <https://github.com/torvalds/linux/blob/v7.0/drivers/net/ethernet/intel/ice/ice_main.c> and <https://github.com/torvalds/linux/blob/v7.0/net/core/dev.c>
- Ubuntu 26.04 `irqbalance` `1.9.4-3`: <https://packages.ubuntu.com/source/resolute/irqbalance>
- Unit env file path in that package: <https://sources.debian.org/src/irqbalance/1.9.4-3/debian/rules/>
- Policyscript arguments and `ban=true`: <https://github.com/Irqbalance/irqbalance/blob/v1.9.4/classify.c> and <https://github.com/Irqbalance/irqbalance/blob/v1.9.4/irqbalance.1>
