# Step 13 — IRQ affinity (applied 2026-11-05)

Rev 10, 2026-11-06. **Boot race 2 (13d) is APPLIED and cold-reboot proven** (`STEP13B-ENO3-WAIT-FIXED`, then boot 2026-11-06 01:20:40Z: oneshot `active`, spread 3/3/3/3, `PIN-OK`, no manual start; see "Boot race 2" Result). Doc-only nits from PRs #14 and #15 are closed in this revision; the helper, unit and 13d script are unchanged. Rev 9, 2026-11-06. Boot race 2 (13d) was drafted: eno3 address wait added; 13c had been applied but the cold boot still failed with `STOP-eno3-addr`. Rev 8, 2026-11-05. **Boot race (13c) is a draft; B1 fixed (tuning is NOTE-only, no wait)**: see "Boot race" below; Johnny is not fixed until AJ's 13c paste and a later reboot. Rev 6, 2026-11-05. **Step 13b is APPLIED** (AJ's paste at tip `bf89820` printed `STEP13B-NAME-MATCH-DONE`; see "Step 13b — applied" below). Post-review nits are in `82962b8` and are for a re-run or the next boot only; Johnny already succeeded on `bf89820`. Rev 5 (step 13b draft added; the rest of this file describes the applied `c765e01` paste). Applied on Johnny. The closeout commit `e0a7c42` is 2026-11-05 20:19:35Z (~14:19 CT), after rev 86's commit `b19ab07` at 20:13:58Z (~14:13 CT). An earlier line on this rev said ~14:18 CT. AJ's paste printed `STEP13-IRQ-DONE`. The paste was tip `c765e01`. **[Inference]** AJ's scp file sizes matched that tip. This repo does not store that size listing. Soft nits in `b19ab07` did not run and do not require a re-run. Do not re-run this step to spread the IRQs. The live pin put every recorded `eno1np0` vector on CPU 1.

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

Name match: **applied** as step 13b below. Do not re-run the `c765e01` paste (it stops at `STOP-hash`). Rollback to the first-run masks is still `sudo bash /root/step13-revert.sh`.

## Step 13b — name match (follow-up, applied 2026-11-05)

Applied. Branch `claude/step13b-name-match`, PR #11 against `claude/practical-ritchie-4c6vvf` (not merged). AJ's paste at tip `bf89820` printed `STEP13B-NAME-MATCH-DONE`. The sections from here to "Stops (13b)" were written as the draft; where the post-nits script differs, the text says so. **Do not re-run the `c765e01` paste.** It now stops: `step-13-irq-affinity.sh` still pins the old helper hash `77b899e3…`, and the repo helper is a new file. Rock-box self-test checks that.

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

1. Gates: host `johnny`, kernel `7.0.0-42-generic`, root, `SUDO_USER` `aj` or empty, lock `/run/johnny-capture-irq.lock`. One log per run: `/root/step13b-apply-<UTC stamp>.log` (`STOP-log-exists` if the name is taken; nothing is rotated over). The applied run on `bf89820` wrote `/root/step13b-apply.log` (old fixed name) and that file is left alone.
2. Stages the new helper and unit under `/root` and checks their sha256 (below).
3. Live helper must be `77b899e3…` (or already the new one); live unit must be `9df4969f…` (or already the new one); the backup TSV must exist and not be a symlink; `johnny-capture-irq.service` must be enabled. `irqbalance` active is `STOP-irqbalance-active`: this script does not re-do the ban/hold logic.
4. Runs the new helper's `preflight` and builds the map. Prints one `PLAN irq name cpu` line per pinned vector. No queue name in the map is `STOP-no-queue-names`. A queue count other than 12 is `STOP-queue-count` (12 is the live RX/TX combined count).
5. Builds the irdma restore plan from the backup TSV (`irdma-0000:01:00.0-*` lines). Each IRQ number must still carry the same name in `/proc/interrupts` (`STOP-irdma-renamed` if not).
6. Saves current masks of every `eno1np0` PCI vector (ice and irdma) for its own rollback. `/var/lib/johnny/step13b-prev/` is the write-once record of the `c765e01` helper and unit: if it exists it must hash to the OLD values (`STOP-prev-helper`, `STOP-prev-unit`), and it is only written while the live files are still OLD. Then it copies the live helper and unit (hash-checked, OLD or NEW) to a per-run `/var/lib/johnny/step13b-entry.XXXXXX/` (`ENTRY-SAVED`). Rollback uses that entry copy, not PREV, and removes it on exit.
7. Installs the new helper and unit, `systemctl daemon-reload`, runs `/etc/johnny/irq-affinity.sh apply`.
8. Writes the backup masks (`0-23`) back to the irdma vectors and reads them back.
9. Reads the spread from `/proc/interrupts` independently (`SPREAD irq name cpu n`, then `SPREAD-COUNT cpu1=3 cpu2=3 cpu3=3 cpu4=3`). Any capture CPU with zero queues is a stop, and the per-CPU counts must sum to the queue count (`STOP-spread-sum`).
10. Checks `eno2np1` masks unchanged, `eno3` address/route, queue counts and RPS/XPS strings unchanged, lockdown unchanged. Then checks that no **ice** vector in the map has CPU 0 in its mask and prints `ICE-CPU0-CLEAR`. The irdma vectors are back on `0-23` on purpose, so the line says ice only. (The `bf89820` run printed plain `CPU0-CLEAR` here; that was an unconditional echo and is replaced.)

Does not: write `/var/lib/johnny/irq-affinity-before.tsv`, touch `irqbalance`, edit netplan, change `capture-cores`, `systemctl start/stop` anything, reboot, or run `apt`. The unit is replaced but not started: `IRQUNIT inactive enabled` stays true until the next boot.

On a stop after the first install, it prints `REVERTING-13B`, writes the saved pre-run masks back, and reinstalls the helper and unit this run saw on entry (`MASKS-PUT-BACK`, `HELPER-PUT-BACK`, `UNIT-PUT-BACK`). A re-run that started on the NEW files therefore rolls back to the NEW files. A stop before any change prints `NO-CHANGE-13B`.

**[Assumption]** Writing `0-23` to an irdma vector is accepted, as the kernel set that mask itself at boot. If the write fails the script stops and rolls back (irdma back to CPU 1).

### Step 13b — applied

**Source.** AJ's paste output, `STEP13B-NAME-MATCH-DONE`, at tip `bf89820` (commit 2026-11-05T14:49:38-06:00). Johnny install time of the helper and unit: 2026-11-05 21:03:23Z (~15:03 CT), read over read-only SSH from rock-box. This closeout did not run the paste and did not use sudo.

What the paste printed (as given to this seat, in this order):

- `NOTE-eno2-unrequested 204..215 (12 lines)`
- `NOTE-irq-aux` for 187 `ice-0000:01:00.0:misc`, 188 `ice-0000:01:00.0:ll_ts`, 201 `ice-0000:01:00.0:ctrl-TxRx-0`
- `NOTE-irdma-skip 217..229 (13 lines)`
- IRQ 187 `misc` and 188 `ll_ts` on CPU 1. IRQs 189..200 `ice-eno1np0-TxRx-0..11` on CPUs `1,2,3,4,1,2,3,4,1,2,3,4`. IRQ 201 `ctrl-TxRx-0` on CPU 1.
- `CPU0-CLEAR` (plain wording of `bf89820`; see the post-nits change), `QUEUES RX/TX 12`, `RPS/XPS 000000`
- `ENO2-IRQ-UNCHANGED`, `ENO3-OK`, `PIN-OK`
- `IRDMA 217..229 mask 0-23`, `IRDMA-RESTORED`
- `SPREAD-COUNT cpu1=3 cpu2=3 cpu3=3 cpu4=3`
- `ENO2-IRQ-UNCHANGED`, `LOCKDOWN-UNCHANGED`, `ENO3-OK`, `CPU0-CLEAR`
- `STEP13B-NAME-MATCH-DONE`

The paste summary AJ handed over is condensed (it has `NOTE-` ranges, not every line). The raw transcript is on Johnny at `/root/step13b-apply.log` (old fixed log name) and was not read here.

**Live hashes, read-only over SSH from rock-box (Johnny, 2026-11-05 21:06Z), all equal the repo tip values:**

| Johnny path | sha256 |
|---|---|
| `/etc/johnny/irq-affinity.sh` | `29f0d0d2d7e3f4c1d2a740057bbbabe4328aa23209a38c341e26edbd44ae5530` (NEW; was `77b899e3…`) |
| `/etc/systemd/system/johnny-capture-irq.service` | `03ce0ceb5f01501fed42488a2cb3697f81bc8d91ef94d4ee5f68df1a8efc2c6a` (13b blob, has `Wants=network-online.target` and the ordering cycle; was `9df4969f…`; superseded in repo by the cycle fix) |
| `/home/aj/cis-audit/step-13b-name-match.sh` | `da03abac57ac277917ef9b82e3805e885ac19f9b8d2922c635f882b0fb85ee2c` (the `bf89820` script; the repo script has changed since, see below) |
| `/var/lib/johnny/step13b-prev/irq-affinity.sh` | `77b899e350bce43184d14b37e4d72c84eae3a7e0816138b1c41631b6ca32ed4e` (c765e01 helper, as expected) |
| `/var/lib/johnny/step13b-prev/johnny-capture-irq.service` | `9df4969fbb8e9000c13d409cc1788846ca9b1acf06275fd7336eb616cd6bb355` (c765e01 unit, as expected) |

The unit is still `inactive` / enabled: 13b ran `daemon-reload` only and never started it. Johnny booted at 16:07 UTC, before the apply, so the unit has not run under systemd and the new `Wants=` has not been exercised.

**Johnny already succeeded on `bf89820`.** The six soft nits from the adversarial review (`APPROVE-WITH-NITS`) are in commit `82962b8`. They changed the 13b script and the self-test, not the helper or the unit. Nothing in `82962b8` ran on Johnny. They matter only if the 13b script is run again. Do not re-run it for them.

| Nit | Where it landed |
|---|---|
| 1 rollback used write-once PREV | rollback restores this run's `step13b-entry.*` copies; PREV must hash OLD before it is written or trusted |
| 2 unconditional `CPU0-CLEAR` | `ICE-CPU0-CLEAR`, computed over the ice vectors in the map; irdma on `0-23` is intended and documented in Goal/Pass |
| 3 `same_cpulist` passed two bad specs | `cpulist_flat` fails on `STOP-cpulist`; self-test has two-bad-specs cases |
| 4 stale checkout could pass the paste | paste checks `git status`, prints the tip, and `sha256sum -c` of the three files on rock-box and again on Johnny |
| 5 queue count and logs | `STOP-queue-count` unless 12; `STOP-spread-sum`; one `step13b-apply-<UTC>.log` per run |
| 6 first reboot is the test for `Wants=` | post-reboot checks below, and the handoff |

### After the first reboot (found a problem)

Johnny rebooted 2026-11-05 23:10:49 UTC (~17:10 CT). `johnny-capture-irq.service` did not run: see **Ordering cycle** below. This was found by AJ's paste (journal lines quoted there); this seat did not read Johnny after that. **Johnny is not fixed** until AJ runs the unit-only paste and it prints `STEP13B-IRQ-UNIT-CYCLE-FIXED`; a reboot after that is the real proof.

### Files

| Path on Johnny | Repo mirror | Mode | sha256 |
|---|---|---|---|
| `/etc/johnny/irq-affinity.sh` | `etc/johnny/irq-affinity.sh` | 0755 | **repo now = live now (13d applied) `807f5a5599bc3e6478a6172b3a54eb576c08f0c4609047a69b834ffec8af3804`** (read over SSH 2026-11-06 ~01:23Z). Before 13d (13c, applied `STEP13B-ENO1-WAIT-FIXED`): `7c475e4a29d711ea5e104a115f0df3d01730fbf3a452eb68cdc3f8a2953fe388`. Before 13c (13b): `29f0d0d2d7e3f4c1d2a740057bbbabe4328aa23209a38c341e26edbd44ae5530`. Old live: `77b899e350bce43184d14b37e4d72c84eae3a7e0816138b1c41631b6ca32ed4e` |
| `/etc/systemd/system/johnny-capture-irq.service` | `etc/systemd/system/johnny-capture-irq.service` | 0644 | **repo now = live now (13d applied, `TimeoutStartSec=150`, comment-only change vs 13c) `6084be53011599d64d7240e4547b53f8dbaa2e2c588d3975f0517a18e6453ed2`**; before 13d (13c) `0220ecdff1cd603726b692fbd41a19c580d98640fd70cd68efcf530afa0e04ea`; before 13c (cycle fix) `a191cdbb7a2391ba8e8b91b3dd36235b0a344799d948a6db74d27ad21958953a` (cycle fix, `After=` has no `johnny-capture-tuning.service`; see Ordering cycle). Older (13b) `03ce0ceb5f01501fed42488a2cb3697f81bc8d91ef94d4ee5f68df1a8efc2c6a` (13b, has the cycle). Older live: `9df4969fbb8e9000c13d409cc1788846ca9b1acf06275fd7336eb616cd6bb355` |
| `/home/aj/cis-audit/step-13b-name-match.sh` | `docs/tool-install/step-13b-name-match.sh` | 0755 | repo tip (post-nits, empty-spec fail-safe; header now says do not re-run, `UNIT_NEW_SHA256` is the cycle-fix unit): `901d2e4bbbae2b64bc11f35b533c4911715d0bf12846dd5dc82c07656f846ae0`. Applied on Johnny from `bf89820`: `da03abac57ac277917ef9b82e3805e885ac19f9b8d2922c635f882b0fb85ee2c` (the copy in `/home/aj/cis-audit/` is that one) |

The 13b script cannot store its own hash. The row above is the full-file digest and the self-test compares it. The post-nits change touched only the 13b script and the self-test. The helper and unit hashes are unchanged.

### Preconditions

- Second SSH session open and AMT KVM available, as for step 13.
- Adversarial-reviewer has said OK on this exact paste.
- The rock-box checkout is on this branch. The block below runs the self-test first and stops on failure.

### Paste

**Retired.** The 13b script ran once from `bf89820` and must not be re-run: its `UNIT_OLD`/`UNIT_NEW` gate no longer matches the live unit (`03ce0ceb…`) and the repo unit has moved on. The first reboot showed an ordering cycle in that unit; the fix is the unit-only paste in **Ordering cycle** below. A full 13b re-run is not needed (helper unchanged).

### Verify

Not part of the paste. On rock-box, read-only:

```bash
ssh aj@192.168.50.152 'echo HOST $(hostname -s); echo IRQUNIT $(systemctl is-active johnny-capture-irq.service) $(systemctl is-enabled johnny-capture-irq.service); grep -c "^Wants=network-online.target$" /etc/systemd/system/johnny-capture-irq.service; for i in $(seq 187 201) $(seq 217 229); do printf "%s %s %s eff %s\n" "$i" "$(awk -v n="$i:" "\$1==n{print \$NF}" /proc/interrupts)" "$(tr -d "[:space:]" < /proc/irq/$i/smp_affinity_list)" "$(tr -d "[:space:]" < /proc/irq/$i/effective_affinity_list)"; done; ip -br addr show eno3; ip -4 route show default'
```

Expect IRQs 189–200 on `1 2 3 4 1 2 3 4 1 2 3 4`, 187/188/201 on `1`, 217–229 on `0-23`, `Wants=` count `1`.

### Rollback

Not part of the paste. On Johnny, second SSH session or KVM, as before: `sudo bash /root/step13-revert.sh`. It restores every saved mask in the first-run TSV (queues back to `0`–`11`, misc/irdma to `0-23`), removes the helper and unit, and does not need 13b to have run. To go back only to the post-step-13 state (everything on CPU 1, old helper and unit), AJ would have to ask for that block; the 13b script does that automatically on its own failure.

### Stops (13b)

`STOP-host`, `STOP-kernel`, `STOP-not-root`, `STOP-user`, `STOP-locked`, `STOP-hash <file>`, `STOP-live-helper-hash`, `STOP-live-unit-hash`, `STOP-live-symlink`, `STOP-no-affinity-backup`, `STOP-irq-unit-not-enabled`, `STOP-irqbalance-active`, `STOP-preflight` (the helper's own `STOP-*` line comes first), `STOP-map`, `STOP-no-queue-names`, `STOP-queue-count`, `STOP-log-exists`, `STOP-prev-helper`, `STOP-prev-unit`, `STOP-entry-helper`, `STOP-entry-unit`, `STOP-spread-sum`, `STOP-ice-cpu0`, `STOP-irdma-gone|ro|name|renamed`, `STOP-no-irdma-backup`, `STOP-no-pre-masks`, `STOP-install-hash`, `STOP-irdma-write|restore`, `STOP-spread`, `STOP-spread-empty`, `STOP-eno2-irq-moved`, `STOP-eno3`, `STOP-queues-changed`, `STOP-lockdown`.

The sections below are the procedure AJ ran (`c765e01`), plus the later wording from `b19ab07`. They are not a second apply.

This is the tool-install step that replaces the open item "IRQ affinity later" from step 11. Handoff Next steps item 13 stays the finished Agent team note. That bullet is not this step. There is no `docs/tool-install/step-13-*.md` before this draft, and the tool-install sequence after step 12 is 13.

Ownership: Fast Path owns the capture-unit path `etc/systemd/system/johnny-capture.*` (`docs/agent-team.md` §4). `johnny-capture-irq.service` is that path. The policyscript and the one-line `IRQBALANCE_ARGS` edit are the smallest host change that keeps the pin from being undone. They are in the same paste, the same way step 11 put netplan and the tuning unit in one script. This draft does not change `docs/agent-team.md`.

### Ordering cycle (found at first reboot, 2026-11-05 23:10:49Z)

**Evidence (AJ's paste from Johnny).**

```
multi-user.target: Found ordering cycle: johnny-capture-irq.service/start after johnny-capture-tuning.service/start after multi-user.target/start - after johnny-capture-irq.service
multi-user.target: Job johnny-capture-irq.service/start deleted to break ordering cycle starting with multi-user.target/start
```

Unit `inactive` (dead) / enabled, `Wants=` count 1, live unit `03ce0ceb…`, helper `29f0d0d2…`, both equal to tip `1d7c028`. IRQ pins fell back to kernel defaults (TxRx 0–11, aux 0–23) because the oneshot never ran.

**Cause.** `johnny-capture-tuning.service` (step 11, applied) has `After=multi-user.target` and `WantedBy=multi-user.target`. `johnny-capture-irq.service` had `After=… johnny-capture-tuning.service` and `WantedBy=multi-user.target`. A target implicitly gets `After=` on every unit it pulls in with `Wants=`/`Requires=` (which `WantedBy=` creates) unless `DefaultDependencies=no`: https://www.freedesktop.org/software/systemd/man/latest/systemd.target.html. So `multi-user.target` is ordered after the irq unit, the irq unit is after tuning, and tuning is after `multi-user.target`: a loop, exactly as the journal prints it. systemd deleted the irq start job to break it. **[Assumption]** Tuning does not loop with the target by itself because its explicit `After=multi-user.target` stops systemd adding the reverse implicit edge (systemd's behavior in `unit_add_default_target_dependency`, from memory of the source, not re-read here); it is why only the irq job was deleted and it is why this PR leaves tuning alone. Not re-verified on 26.04 specifically.

**Fix (this PR).** `johnny-capture-irq.service`: remove `johnny-capture-tuning.service` from `After=`. It is now `After=network-online.target irqbalance.service`, `Wants=network-online.target` kept. `johnny-capture-tuning.service` is **not changed** (step 11 applied, out of scope). The irq pins and the EPP/idle tuning do not need an order between them: they touch different things (IRQ masks vs cpufreq/cpuidle).

**Johnny needs** the unit-only paste below after the adversarial-reviewer says OK on this exact block. It replaces only the unit, runs `daemon-reload`, and starts the oneshot once. Helper unchanged (`29f0d0d2…`). No full 13b re-run, no reboot.

| Item | sha256 |
|---|---|
| `etc/systemd/system/johnny-capture-irq.service` (new) | `a191cdbb7a2391ba8e8b91b3dd36235b0a344799d948a6db74d27ad21958953a` |
| unit live now (13b, has the cycle) | `03ce0ceb5f01501fed42488a2cb3697f81bc8d91ef94d4ee5f68df1a8efc2c6a` |
| `docs/tool-install/step-13b-unit-cycle-fix.sh` | `bf6cca5c50566832db2278d4259dda76886a491eebf7a45dad88a14045fd35e1` |
| `docs/tool-install/step-13-self-test.sh` | `2f96c01e668e9b166aa8c88f30d46643d01f5bea3e8a5407fb895aee28d23dd1` |
| `etc/johnny/irq-affinity.sh` (unchanged) | `29f0d0d2d7e3f4c1d2a740057bbbabe4328aa23209a38c341e26edbd44ae5530` |

#### Paste (unit only)

On rock-box. One block. It stops unless the checkout is clean under `docs/tool-install` and `etc`, the four files hash to the table above, and the self-test passes; then it copies the unit and script to Johnny, hash-checks them there, and runs the script under `sudo`.

```bash
cd /home/aj/Projects/strix-halo-johnny && \
test -z "$(git status --porcelain -- docs/tool-install etc)" && \
git rev-parse --short HEAD && \
printf '%s  %s\n' \
  bf6cca5c50566832db2278d4259dda76886a491eebf7a45dad88a14045fd35e1 docs/tool-install/step-13b-unit-cycle-fix.sh \
  2f96c01e668e9b166aa8c88f30d46643d01f5bea3e8a5407fb895aee28d23dd1 docs/tool-install/step-13-self-test.sh \
  29f0d0d2d7e3f4c1d2a740057bbbabe4328aa23209a38c341e26edbd44ae5530 etc/johnny/irq-affinity.sh \
  a191cdbb7a2391ba8e8b91b3dd36235b0a344799d948a6db74d27ad21958953a etc/systemd/system/johnny-capture-irq.service \
  | sha256sum -c - && \
bash docs/tool-install/step-13-self-test.sh && \
ssh aj@192.168.50.152 'mkdir -p /home/aj/cis-audit' && \
scp docs/tool-install/step-13b-unit-cycle-fix.sh aj@192.168.50.152:/home/aj/cis-audit/step-13b-unit-cycle-fix.sh && \
scp etc/systemd/system/johnny-capture-irq.service aj@192.168.50.152:/home/aj/cis-audit/johnny-capture-irq-cyclefix.service && \
ssh -t aj@192.168.50.152 'printf "%s  %s\n" bf6cca5c50566832db2278d4259dda76886a491eebf7a45dad88a14045fd35e1 /home/aj/cis-audit/step-13b-unit-cycle-fix.sh a191cdbb7a2391ba8e8b91b3dd36235b0a344799d948a6db74d27ad21958953a /home/aj/cis-audit/johnny-capture-irq-cyclefix.service | sha256sum -c - && sudo -v && sudo bash /home/aj/cis-audit/step-13b-unit-cycle-fix.sh'
```

**[Assumption]** `printf` reuses its format per hash/path pair (bash builtin). The block has not been run.

Pass lines in order (a `NOTE-tuning-not-active` before `INPUTS-OK` is allowed): `INPUTS-OK`, `PREV-SAVED` (first run only), `UNIT-INSTALLED`, `AFTER-OK`, `START-OK`, twelve `TXRX n irq … cpu …` lines, `SPREAD-COUNT cpu1=3 cpu2=3 cpu3=3 cpu4=3`, three `AUX` lines (misc, ll_ts, ctrl-TxRx-0 on `1`), `IRDMA` lines (left alone; `0-23` expected, not a pass/fail), then `STEP13B-IRQ-UNIT-CYCLE-FIXED`. The script matches IRQs by name, not number. Log: `/root/step13b-cyclefix-<UTC>.log`.

Stops: `STOP-host`, `STOP-not-root`, `STOP-log-exists`, `STOP-hash`, `STOP-helper-hash`, `STOP-live-unit-missing`, `STOP-live-unit-hash`, `STOP-unit-not-enabled`, `STOP-prev-hash`, `STOP-install-hash`, `STOP-after-still-lists-tuning`, `STOP-start-failed`, `STOP-not-active`, `STOP-txrx-count`, `STOP-txrx-mask`, `STOP-aux-mask`. After install, a failure in the hash, `After=`, or start checkpoints puts the old unit back (`ROLLED-BACK-UNIT`; masks are not touched). A mask `STOP-` after a good start leaves the new unit installed.

#### Verify after the paste (not part of the paste)

Read-only, from rock-box. Johnny reads `active` for the oneshot, and `After=` has no tuning:

```bash
ssh aj@192.168.50.152 'echo HOST $(hostname -s); echo IRQUNIT $(systemctl is-active johnny-capture-irq.service) $(systemctl is-enabled johnny-capture-irq.service); sha256sum /etc/systemd/system/johnny-capture-irq.service; systemctl show -p After --value johnny-capture-irq.service; awk "/ice-eno1np0-TxRx|ice-0000:01:00.0:(misc|ll_ts|ctrl-TxRx-0)|irdma-0000:01:00.0-/{n=\$NF; sub(\":\",\"\",\$1); print \$1, n}" /proc/interrupts | while read -r i n; do printf "%s %s %s\n" "$i" "$n" "$(tr -d "[:space:]" < /proc/irq/$i/smp_affinity_list)"; done'
```

Expect TxRx-0..11 on `1 2 3 4 1 2 3 4 1 2 3 4`, misc/ll_ts/ctrl-TxRx-0 on `1`, irdma left alone (`0-23` expected), unit hash `a191cdbb7a2391ba8e8b91b3dd36235b0a344799d948a6db74d27ad21958953a`.

**The reboot is the real test.** Until Johnny reboots with the new unit, the cycle fix is verified only by `systemctl show` here. After the next reboot, expect no `Found ordering cycle` for `johnny-capture-irq.service` (`journalctl -b -g "ordering cycle"`), the oneshot `active`, and the pins above without a manual start. AJ has not been asked to reboot.

#### Rollback (not part of the paste)

On Johnny: `sudo install -m 0644 -o root -g root /var/lib/johnny/step13b-cyclefix-prev/johnny-capture-irq.service /etc/systemd/system/johnny-capture-irq.service && sudo systemctl daemon-reload` puts the cyclic 13b unit (`03ce0ceb…`) back; masks stay as they are. Full revert to pre-step-13 is still `sudo bash /root/step13-revert.sh` (it deletes the unit).

### Boot race (found at second reboot, 2026-11-05 23:36:59Z): eno1 and tuning not ready

**Evidence (AJ's paste from Johnny).** The ordering cycle is gone (`CYCLE 0`, unit sha `a191cdbb…`). The unit now runs at boot, but the helper stops:

```
STOP-eno1-link speed= flags=0x1002 carrier= oper=down
tr: tr-error-read-error: Invalid input
```

A manual `systemctl start johnny-capture-irq.service` after the link was up worked (prior boot journal: `PIN-OK` at 23:34:41Z).

**Cause.** `Wants=`/`After=network-online.target` is satisfied by management `eno3` (192.168.50.152). The capture NIC `eno1np0` is brought up by netplan later. At that moment its flags are `0x1002` (not admin-up), and sysfs `speed`/`carrier` return EINVAL while the link is down, so `tr` prints the read error. Separately, `johnny-capture-tuning.service` has `After=multi-user.target`, so it can only go `active` after the irq oneshot exits; the helper must not wait for it (see B1 below).

**Fix.** The irq unit does **not** get `After=johnny-capture-tuning.service` back (that is the cycle). Instead the helper waits, bounded:

| Wait | Where | Bound | Notes |
|---|---|---|---|
| `wait_eno1_link` | `preflight`, before the `STOP-eno1-link` check | 50 tries x 2s = 100s | ready = admin-up, speed 10000, carrier 1 or oper up, and flags admin-up+promisc+noarp. Prints `NOTE-wait-eno1 try=N speed= flags= carrier= oper=` every 3rd try. On timeout the old `STOP-eno1-link` / `STOP-eno1-flags` lines still print. |
| (tuning) | `preflight` | none | **Not waited on.** Tuning not `active` / not `enabled` / EPP not `performance` on a capture CPU print `NOTE-tuning-not-active`, `NOTE-tuning-not-enabled`, `NOTE-tuning-epp <cpu> <value>` and continue. |

**Review B1 (adversarial-reviewer, tip `b73e881`) and the fix.** The first 13c draft waited 60s inside the irq oneshot for tuning `active`. That deadlocks at boot: irq is `WantedBy=multi-user.target`; tuning is `After=multi-user.target`, so tuning cannot go `active` until the irq oneshot exits, and the wait always timed out into `STOP-tuning`. Fix (option a): `wait_tuning_ready` and every hard `STOP-tuning` / `STOP-tuning-epp` are gone; tuning checks are `NOTE-tuning-…` lines only. IRQ pins do not need the tuning oneshot. `After=johnny-capture-tuning.service` stays off the irq unit (that is the cycle) and the tuning unit is unchanged.

`read_trim` now sends its errors to `/dev/null` and returns empty, so a down link prints no `tr:` line; an empty value is simply "not ok" to the wait loop.

`TimeoutStartSec` goes from 30 to **150** (eno1 wait 100s + 50s preflight/pin slack). No `Restart=`: a permanent `STOP-` (wrong kernel, bad hash) would loop, and the oneshot exit is already visible; a restart belt can be added later if AJ wants it. `johnny-capture-tuning.service` is unchanged.

| Item | sha256 |
|---|---|
| `etc/johnny/irq-affinity.sh` (13c) | `7c475e4a29d711ea5e104a115f0df3d01730fbf3a452eb68cdc3f8a2953fe388` |
| `etc/johnny/irq-affinity.sh` (live now, 13b) | `29f0d0d2d7e3f4c1d2a740057bbbabe4328aa23209a38c341e26edbd44ae5530` |
| `etc/systemd/system/johnny-capture-irq.service` (13c) | `0220ecdff1cd603726b692fbd41a19c580d98640fd70cd68efcf530afa0e04ea` |
| `etc/systemd/system/johnny-capture-irq.service` (live now, cycle fix) | `a191cdbb7a2391ba8e8b91b3dd36235b0a344799d948a6db74d27ad21958953a` |
| `docs/tool-install/step-13c-eno1-wait.sh` | `41e3c9f443bbb7df776b88c2b1701bc17d369607c64831495511cf7aaafca2f0` |
| `docs/tool-install/step-13-self-test.sh` | `d86c24be703d71f4b4e2f4ade1d759e8a23eb3dd429c8ebb7ab3dbc836121da5` |

#### Paste (helper + unit)

On rock-box. One block. It stops unless the checkout is clean under `docs/tool-install` and `etc`, the files hash to the table, and the self-test passes; then it copies helper, unit and script to Johnny, hash-checks them there, and runs the script under `sudo`. **[Assumption]** `printf` reuses its format per hash/path pair. Not run.

```bash
cd /home/aj/Projects/strix-halo-johnny && \
test -z "$(git status --porcelain -- docs/tool-install etc)" && \
git rev-parse --short HEAD && \
printf '%s  %s\n' \
  41e3c9f443bbb7df776b88c2b1701bc17d369607c64831495511cf7aaafca2f0 docs/tool-install/step-13c-eno1-wait.sh \
  7c475e4a29d711ea5e104a115f0df3d01730fbf3a452eb68cdc3f8a2953fe388 etc/johnny/irq-affinity.sh \
  0220ecdff1cd603726b692fbd41a19c580d98640fd70cd68efcf530afa0e04ea etc/systemd/system/johnny-capture-irq.service \
  | sha256sum -c - && \
bash docs/tool-install/step-13-self-test.sh && \
ssh aj@192.168.50.152 'mkdir -p /home/aj/cis-audit' && \
scp docs/tool-install/step-13c-eno1-wait.sh aj@192.168.50.152:/home/aj/cis-audit/step-13c-eno1-wait.sh && \
scp etc/johnny/irq-affinity.sh aj@192.168.50.152:/home/aj/cis-audit/irq-affinity-wait.sh && \
scp etc/systemd/system/johnny-capture-irq.service aj@192.168.50.152:/home/aj/cis-audit/johnny-capture-irq-wait.service && \
ssh -t aj@192.168.50.152 'printf "%s  %s\n" 41e3c9f443bbb7df776b88c2b1701bc17d369607c64831495511cf7aaafca2f0 /home/aj/cis-audit/step-13c-eno1-wait.sh 7c475e4a29d711ea5e104a115f0df3d01730fbf3a452eb68cdc3f8a2953fe388 /home/aj/cis-audit/irq-affinity-wait.sh 0220ecdff1cd603726b692fbd41a19c580d98640fd70cd68efcf530afa0e04ea /home/aj/cis-audit/johnny-capture-irq-wait.service | sha256sum -c - && sudo -v && sudo bash /home/aj/cis-audit/step-13c-eno1-wait.sh'
```

Pass lines in order (a `NOTE-tuning-not-active` before `INPUTS-OK` is allowed): `INPUTS-OK`, `PREV-SAVED`, `FILES-INSTALLED`, `AFTER-OK`, `START-OK`, twelve `TXRX n irq … cpu …`, `SPREAD-COUNT cpu1=3 cpu2=3 cpu3=3 cpu4=3`, three `AUX` lines, `IRDMA` lines (not pass/fail), then `STEP13B-ENO1-WAIT-FIXED`. Log: `/root/step13c-<UTC>.log`.

Stops: `STOP-host`, `STOP-not-root`, `STOP-log-exists`, `STOP-hash`, `STOP-helper-missing`, `STOP-helper-hash`, `STOP-live-unit-missing`, `STOP-live-unit-hash`, `STOP-unit-not-enabled`, `STOP-prev-hash`, `STOP-install-hash`, `STOP-after-still-lists-tuning`, `STOP-timeout-not-150s`, `STOP-start-failed`, `STOP-not-active`, `STOP-txrx-count`, `STOP-txrx-mask`, `STOP-aux-mask`. Hash, `After=`, timeout and start failures put both old files back (`ROLLED-BACK`; masks untouched).

**Johnny is not fixed** until this paste prints `STEP13B-ENO1-WAIT-FIXED` **and** a later reboot shows the oneshot `active` with the spread, without a manual start. After that reboot, read `journalctl -b -u johnny-capture-irq.service` for `NOTE-wait-eno1`, any `NOTE-tuning-…`, and `PIN-OK`. AJ has not been asked to reboot.

#### Rollback (not part of the paste)

On Johnny: `sudo install -m 0755 -o root -g root /var/lib/johnny/step13c-prev/irq-affinity.sh /etc/johnny/irq-affinity.sh && sudo install -m 0644 -o root -g root /var/lib/johnny/step13c-prev/johnny-capture-irq.service /etc/systemd/system/johnny-capture-irq.service && sudo systemctl daemon-reload` restores the cycle-fix unit and 13b helper. Masks stay as they are.

### Boot race 2 (third reboot, 2026-11-06 01:00:55Z): eno3 address not visible yet (step 13d, applied; cold reboot PASS)

**Evidence (AJ reboot proof, journal).** `CYCLE 0`. `johnny-capture-irq.service` exit-code `failed`. `NOTE-wait-eno1 try=0 speed= flags=0x1002 carrier= oper=down`, then about 2s later `STOP-eno3-addr`. No `STOP-eno1-link`, so the eno1 wait returned quickly. IRQ affinity stayed at kernel defaults. After boot, eno3 has `192.168.50.152/24`, default via eno3, eno1np0 up; a manual start works.

**Cause (supported by journal timestamps; not traced inside the helper).** Read-only journal of the failing boot (`journalctl -b -1`, UTC): `systemd-networkd-wait-online.service` was skipped (unmet `ConditionPathIsSymbolicLink=/run/systemd/generator/network-online.target.wants/...`), so `network-online.target` was reached at 01:00:58.607 and gated on nothing. The oneshot started at 01:00:58.609; `NOTE-wait-eno1 try=0` at 01:00:59.25; eno1np0 `Gained carrier` at 01:00:59.52; `STOP-eno3-addr` at 01:01:01.36 (the eno1 wait had returned after about one poll). eno3's DHCPv4 lease (`192.168.50.152/24`) arrived at 01:01:06.50, about 5s after the STOP. `preflight` made `STOP-eno3-addr` hard with no wait, so the unit failed before the address existed. Root cause of the early `network-online.target` (`wait-online` skipped) is left for the later architecture pass; the helper's own wait is the fix here.

**Fix.** `wait_eno1_link` is replaced by `wait_boot_ready` (same style, same 50 tries x 2s = 100s). One loop polls both: eno1np0 (admin-up, 10G, carrier or oper up, admin-up+promisc+noarp flags) **and** eno3 (`eno3_ok`: `192.168.50.152/` on eno3, default route `dev eno3`, admin-up). It returns when both are ready. While not ready it prints `NOTE-wait-eno1 try=N …` and/or `NOTE-wait-eno3 try=N why=STOP-eno3-addr|STOP-eno3-route|STOP-eno3-down` every 3rd try. On timeout the hard checks in `preflight` still print `STOP-eno1-link` / `STOP-eno1-flags` and `STOP-eno3-addr` / `STOP-eno3-route` / `STOP-eno3-down`, unchanged in meaning. The eno3 checks in `preflight` now call `eno3_ok` (same tokens, one definition).

**Budget.** Waits share one 100s loop (concurrent, not 100s + 100s). `TimeoutStartSec=150` is unchanged: 100s wait + 50s for the rest of preflight and the pin. Only the comment in the unit changed (so its sha changed). **[Assumption]** cold-boot DHCP on eno3 normally lands well inside 100s. Observed on two boots: DHCPv4 came 7.9s (01:00:58.6 to 01:01:06.5) and 7.3s (01:20:43.6 to 01:20:50.9) after the irq unit started.

**Boot-time effect.** The oneshot still gates `multi-user.target`: in the proven boot `multi-user.target` was reached at 01:20:52.669, right after the oneshot finished at 01:20:52. If eno1 or eno3 never comes ready, boot waits up to 100s and the unit then fails (same failure path as before, bounded). A boot with `NOTE-wait-eno1` or `NOTE-wait-eno3` lines in the journal is the wait working, not a hang.

**Unchanged.** Tuning stays `NOTE-tuning-…` only; no `After=johnny-capture-tuning.service` on the irq unit (that edge is the ordering cycle; no new ordering edge is added, so cycle risk is none); tuning unit untouched; `read_trim` silent. Wait order is eno1 and eno3 together, so no order-dependent early exit.

**Result (applied; cold reboot PASS).** AJ ran the 13d paste (token `STEP13B-ENO3-WAIT-FIXED`, as AJ reported; the paste output is not stored in this repo). Johnny's `step13d-prev/` was created 01:19 UTC and the unit restarted at 01:19:21Z. Then AJ cold-rebooted: boot 2026-11-06 01:20:40Z. Read-only SSH afterward (2026-11-06 ~01:23Z, UTC):

- Live files match the repo: helper `807f5a5599bc3e6478a6172b3a54eb576c08f0c4609047a69b834ffec8af3804`, unit `6084be53011599d64d7240e4547b53f8dbaa2e2c588d3975f0517a18e6453ed2`. `TimeoutStartUSec=2min 30s`; `After=` has no `johnny-capture-tuning.service`.
- `johnny-capture-irq.service` `active`, `enabled`, `Result=success`, `ExecMainStatus=0`, `ActiveEnterTimestamp` 01:20:52. No manual start. Ordering cycle count 0 in this boot's journal.
- Boot journal: `wait-online` skipped again; unit start 01:20:43.607; `NOTE-wait-eno1 try=0 … oper=down` and `NOTE-wait-eno3 try=0 why=STOP-eno3-addr` at 01:20:44.2; eno1np0 `Gained carrier` 01:20:44.48; eno3 `Gained carrier` 01:20:46.64; `NOTE-wait-eno3 try=3` at 01:20:50.27; eno3 DHCPv4 01:20:50.94; wait returned and `NOTE-tuning-not-active inactive` plus four `NOTE-tuning-epp` lines at 01:20:52.33 (expected: tuning is `After=multi-user.target`); `CAPTURE-CPUS 1 2 3 4`, `OK-tuning`. About 8.7s from unit start to finish. The `NOTE-eno2-unrequested`, `NOTE-irq-aux` and `NOTE-irdma-skip` lines are the same as step 13b.
- Spread: the twelve `ice-eno1np0-TxRx-*` IRQs are on CPUs `1 2 3 4 1 2 3 4 1 2 3 4` (3/3/3/3).
- Journal noise: 11 lines `/etc/johnny/irq-affinity.sh: line 33: printf: write error: Broken pipe` (the 13c session had the same). The unit still succeeded. It is `expand_affinity` writing into a closed pipe under `trap '' PIPE`; harmless, not changed here (a helper edit would change the pinned hashes).

One cold boot is one sample; the 100s wait is the margin. The pin does not change what the capture NICs do; only IRQ masks.

| Item | sha256 |
|---|---|
| `etc/johnny/irq-affinity.sh` (13d, live now) | `807f5a5599bc3e6478a6172b3a54eb576c08f0c4609047a69b834ffec8af3804` |
| `etc/johnny/irq-affinity.sh` (before 13d, 13c) | `7c475e4a29d711ea5e104a115f0df3d01730fbf3a452eb68cdc3f8a2953fe388` |
| `etc/systemd/system/johnny-capture-irq.service` (13d, live now) | `6084be53011599d64d7240e4547b53f8dbaa2e2c588d3975f0517a18e6453ed2` |
| `etc/systemd/system/johnny-capture-irq.service` (before 13d, 13c) | `0220ecdff1cd603726b692fbd41a19c580d98640fd70cd68efcf530afa0e04ea` |
| `docs/tool-install/step-13d-eno3-wait.sh` | `80f4b5f0c6ff6dfc5bebf62acb2c96b7e41cfd886fd415ac0da235103cd84888` |
| `docs/tool-install/step-13-self-test.sh` (this revision; the as-run 13d paste did not hash it, see Notes below) | `e6f2552310821be7f93ec5ea42dda9089348d85ffb065ef36c2ffb011d8ad9b6` |

#### Paste (13d: helper + unit)

On rock-box. One block, same shape as the 13c paste: stops unless the checkout is clean under `docs/tool-install` and `etc`, the files hash to the table, and the self-test passes; then copies to Johnny, hash-checks there, and runs the script under `sudo`. The script itself refuses unless live files are the 13c blobs (or already the 13d blobs). **Applied:** AJ ran this block as written and reported the token. Do not re-run it; live is already the 13d blobs. The block below is the record of what ran and is left unedited.

```bash
cd /home/aj/Projects/strix-halo-johnny && \
test -z "$(git status --porcelain -- docs/tool-install etc)" && \
git rev-parse --short HEAD && \
printf '%s  %s\n' \
  80f4b5f0c6ff6dfc5bebf62acb2c96b7e41cfd886fd415ac0da235103cd84888 docs/tool-install/step-13d-eno3-wait.sh \
  807f5a5599bc3e6478a6172b3a54eb576c08f0c4609047a69b834ffec8af3804 etc/johnny/irq-affinity.sh \
  6084be53011599d64d7240e4547b53f8dbaa2e2c588d3975f0517a18e6453ed2 etc/systemd/system/johnny-capture-irq.service \
  | sha256sum -c - && \
bash docs/tool-install/step-13-self-test.sh && \
ssh aj@192.168.50.152 'mkdir -p /home/aj/cis-audit' && \
scp docs/tool-install/step-13d-eno3-wait.sh aj@192.168.50.152:/home/aj/cis-audit/step-13d-eno3-wait.sh && \
scp etc/johnny/irq-affinity.sh aj@192.168.50.152:/home/aj/cis-audit/irq-affinity-eno3.sh && \
scp etc/systemd/system/johnny-capture-irq.service aj@192.168.50.152:/home/aj/cis-audit/johnny-capture-irq-eno3.service && \
ssh -t aj@192.168.50.152 'printf "%s  %s\n" 80f4b5f0c6ff6dfc5bebf62acb2c96b7e41cfd886fd415ac0da235103cd84888 /home/aj/cis-audit/step-13d-eno3-wait.sh 807f5a5599bc3e6478a6172b3a54eb576c08f0c4609047a69b834ffec8af3804 /home/aj/cis-audit/irq-affinity-eno3.sh 6084be53011599d64d7240e4547b53f8dbaa2e2c588d3975f0517a18e6453ed2 /home/aj/cis-audit/johnny-capture-irq-eno3.service | sha256sum -c - && sudo -v && sudo bash /home/aj/cis-audit/step-13d-eno3-wait.sh'
```

Pass lines in order (a `NOTE-tuning-not-active` before `INPUTS-OK` is allowed): `INPUTS-OK`, `PREV-SAVED`, `FILES-INSTALLED`, `AFTER-OK`, `START-OK`, twelve `TXRX n irq … cpu …`, `SPREAD-COUNT cpu1=3 cpu2=3 cpu3=3 cpu4=3`, three `AUX` lines, `IRDMA` lines (not pass/fail), then `STEP13B-ENO3-WAIT-FIXED`. Log: `/root/step13d-<UTC>.log`. Stops are the same as 13c (`STOP-live-unit-hash` / `STOP-helper-hash` mean live is not the 13c blobs).

This paste ran on a live system, which is where 13c also passed; it did not exercise the race. The cold reboot did: see Result above (`active`, spread 3/3/3/3, no manual start). Check for the next boot: `journalctl -b -u johnny-capture-irq.service` for `NOTE-wait-eno1`, `NOTE-wait-eno3` and the pin lines.

#### Rollback (13d, not part of the paste)

On Johnny: `sudo install -m 0755 -o root -g root /var/lib/johnny/step13d-prev/irq-affinity.sh /etc/johnny/irq-affinity.sh && sudo install -m 0644 -o root -g root /var/lib/johnny/step13d-prev/johnny-capture-irq.service /etc/systemd/system/johnny-capture-irq.service && sudo systemctl daemon-reload` restores the 13c helper and unit. Masks stay as they are.

#### Notes from the 13c and 13d reviews (docs only; nothing here changes a pinned hash)

- **`sudo -v` is not the first line of the paste.** The sudo runs on Johnny inside `ssh -t`, after the remote hash check. A local `sudo -v` on rock-box would not help. Same shape as the approved 13c paste.
- **`git rev-parse --short HEAD` in the paste only prints the tip; it does not pin it.** The `sha256sum -c` of the three blobs is the pin. After a merge the tip differs but the paste stays valid while those blobs are unchanged.
- **Self-test hash not in the paste (13c nit N3, same for 13d).** The self-test cannot hash itself and the as-run 13c and 13d pastes did not hash it; the gate was that it printed `SELF-TEST-OK`. The runbook now records its digest (13d table above; 13c table has `d86c24be703d71f4b4e2f4ade1d759e8a23eb3dd429c8ebb7ab3dbc836121da5`, which is the 13c-time file). For a new paste, add `docs/tool-install/step-13-self-test.sh` to the `printf` hash list so a stale self-test on rock-box cannot pass.
- **A `STOP-` after a good start does not roll back.** In the 13c and 13d scripts the checkpoints after `START-OK` (`STOP-not-active`, `STOP-txrx-*`, `STOP-aux-mask`) are state checks, not file defects; the new files stay installed. Hash, `After=`, timeout and start failures do roll back (`ROLLED-BACK`).
- **Pins now run before tuning's EPP and idle settings at boot** (tuning is `After=multi-user.target`). That is why the boot journal shows `NOTE-tuning-not-active inactive` and `NOTE-tuning-epp … balance_performance`; it is expected and not a failure.
- **Self-test covers the preflight order.** The self-test now asserts `preflight` calls `wait_boot_ready` before the hard `eno3_ok` check (PR #15 nit 1).

## Machines

| Machine | What this step does there |
|---|---|
| Johnny | The script runs as root. Hostname gate `johnny`. Kernel gate `7.0.0-42-generic`. |
| rock-box | Where the required self-test and the paste are typed. Self-test first, then `scp`, then `ssh -t`. **[Assumption]** the checkout is still `/home/aj/Projects/strix-halo-johnny`, as in step 11 and `docs/agent-team.md`. |
| ABLETON_BOX | No command. Do not SSH. Do not touch the syslog collector. |

## Goal

Pin every MSI-X IRQ of the capture NIC `eno1np0` onto the CPUs listed in `/etc/johnny/capture-cores`, one CPU per IRQ, and make that pin survive `irqbalance` and a reboot. CPU 0 stays out of those masks (step 13 text; after step 13b that holds for the **ice** vectors only. The 13 irdma vectors of the same PCI function are intentionally back on `0-23`, the kernel's own mask, and are not pinned). `eno3` stays `192.168.50.152/24` with its default route. The paste prints `STEP13-IRQ-DONE` only after that pin is in place and the checks below have passed. A draft, a stopped run, or a revert does not print it.

## Pass

All of these, from the script's own output:

- `CAPTURE-CPUS 1 2 3 4`
- `OK-tuning`
- `CPU0-CLEAR` (step 13 / `c765e01`; the 13b script prints `ICE-CPU0-CLEAR` instead, for the ice vectors only)
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
| `/etc/systemd/system/johnny-capture-irq.service` | `etc/systemd/system/johnny-capture-irq.service` | 0644 | repo file after the cycle fix: `a191cdbb7a2391ba8e8b91b3dd36235b0a344799d948a6db74d27ad21958953a` (has `Wants=network-online.target`, no tuning in `After=`). Not the live file until the unit-only paste runs. Live after 13b: `03ce0ceb5f01501fed42488a2cb3697f81bc8d91ef94d4ee5f68df1a8efc2c6a`. Live install from `c765e01`: `9df4969fbb8e9000c13d409cc1788846ca9b1acf06275fd7336eb616cd6bb355` (no `Wants=`). Soft-nit `Wants=` is not on Johnny. |
| `/root/step13-revert.sh` | `docs/tool-install/step-13-revert.sh` | 0755 | `c9dd1522e278bc3bad3a711a4fdcd18b1b768d9da19dff07376a5db7dfa4cc1d` |
| `/home/aj/cis-audit/step-13-irq-affinity.sh` | `docs/tool-install/step-13-irq-affinity.sh` | 0755 | `83b8748b8793d7ab3f7bb383775cf24ae155c52da7063ca219bfc993bcc2bdf7` |

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
| `NOTE-tuning-not-active` / `NOTE-tuning-not-enabled` / `NOTE-tuning-epp` | Informational only (13c); pin continues. Before 13c these were `STOP-tuning` lines. |
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
