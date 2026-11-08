# Module 1, slice 1c — boot persistence unit (`johnny-capture-xdp.service`) for `j_xdp_observe` on `eno1np0` (applied)

Rev 4, 2026-11-08 America/Chicago. Status: **rev 3 boot helper reinstalled on Johnny (Nits reinstall APPLIED).** AJ ran the Nits reinstall paste at **2026-11-08 07:15:55 UTC (2026-11-08 1:15:55 AM CST)** after Paste 1 on the rev 3 branch printed `E2E-OK scenarios=8`, `RUNBOOK-OK blocks=8`, **`SELF-TEST-OK`**. Installed `/root/m1s1b/module1-slice1c-boot.sh` sha256 `a501dbb7c49a611dd230f7c4fa09d6c1a7f8923f7302459180a197625ccc8c06`; `verify` passed and the paste ended **`M1S1C-VERIFY-DONE`** and **`M1S1C-NITS-REINSTALL-DONE`** (record under § Nits reinstall). The unit was not restarted, so the rev 3 fail-closed `start` path has **not yet run at a cold boot**; that proof is an optional later reboot + Paste 6 (the 2026-11-08 02:26 UTC cold boot passed on the rev 2 helper). Rev 4 doc fixes (fenced Paste 6 changed, scripts and pins unchanged): Paste 6's wait loop no longer sleeps after its last sample, so the `active` check uses a fresh sample taken at the 120 s mark (still fail closed); Paste 5's prose now matches Paste 6's wait behaviour. Rev 3 text follows unchanged except where marked.

Rev 3, 2026-11-07 America/Chicago. Status: **slice 1c nits fix DRAFTED, NOT APPLIED** (branch `claude/module1-slice1c-nits` off `origin/claude/practical-ritchie-4c6vvf` base `e383c4f`). Fixes the four parked follow-ups below: `module1-slice1c-boot.sh` now stops on a boot-wait timeout (sha256 `a501dbb7c49a611dd230f7c4fa09d6c1a7f8923f7302459180a197625ccc8c06`, was `f05e7ac425ed78837ab57880f483ed42eeea431c5037da09248e11eea6a580bc`); Paste 6 gates its done token on the ordering-cycle check and waits up to 120 s for the unit to be `active`; the Rollback block prints its done token only when `status` shows no XDP attach and the unit inactive. Unit, object, attach and detach helpers are unchanged. Johnny still runs the rev 2 boot helper until AJ runs the **Nits reinstall** paste below. Rev 2 text follows unchanged except where marked.

Rev 2, 2026-11-08 UTC (2026-11-07 America/Chicago). Status: **applied on Johnny.** AJ ran Pastes 1–6 from rock-box; the cold reboot (Paste 5, `M1S1C-REBOOT-ISSUED`) came back with `johnny-capture-xdp.service` attaching `j_xdp_observe` unattended (`xdpdrv`, `prog_id=75`, `M1S1C-START-BEGIN DATE-UTC 2026-11-08T02:26:28Z`), and the Paste 6 rerun ended **`M1S1C-COLD-BOOT-VERIFY-DONE`**. Rollback was **not** run. Unit, boot helper, self-test, and every sha256 pin are **unchanged** from rev 1. Rev 1 (2026-11-06 America/Chicago, branch `claude/module1-slice1c-boot-unit` off `origin/claude/practical-ritchie-4c6vvf` base tip `e41c0db`, PR #26 with B1 fix `9024600`) was the draft (Status: **drafted, not applied.**).

## Applied on Johnny (cold boot 2026-11-08 ~02:26 UTC; 2026-11-07 ~20:26 America/Chicago)

**Tokens and run order.** AJ ran Pastes 1–4 and then Paste 5 (**`M1S1C-REBOOT-ISSUED`**). Per-token output for Pastes 1–4 was not supplied to this closeout **[not recorded here]**; that Paste 5 and 6 ran implies Paste 4 ended `M1S1C-ENABLE-THIS-BOOT-DONE` (the runbook says to roll back otherwise) **[Inference]**. Paste 6 ran twice:

- **First try: no done token.** `verify` ran about 20 s after boot while the unit's `start` still held the helper lock (unit still running its attach), so `verify` hit **`STOP-locked`** and the `&&` chain stopped before `M1S1C-COLD-BOOT-VERIFY-DONE`. Nothing was changed by the failed run. This is the Paste 6 race listed under Follow-ups.
- **Rerun at uptime 2 min: passed**, ending **`M1S1C-VERIFY-DONE`**, **`M1S1B-STATUS-DONE`**, **`M1S1C-STATUS-DONE`**, **`M1S1C-COLD-BOOT-VERIFY-DONE`**.

**Boot health.** `systemctl is-system-running` = `running`; `OK-no-ordering-cycle-warnings`.

**`johnny-capture-irq.service` (step 13, ran first).** `PIN-OK`, `ENO3-OK`, `CPU0-CLEAR`, `CAPTURE-CPUS 1 2 3 4`; `ice-eno1np0-TxRx-0..11` round-robin on CPUs 1–4.

**`johnny-capture-xdp.service` (journal, this boot).** `enabled`, `active (exited)` since 02:26:47 UTC, `status=0`. `M1S1C-START-BEGIN DATE-UTC 2026-11-08T02:26:28Z`; all hash checks OK (object `8be9877f…`, attach `f9f95ec6…`, rollback `f78ca14e…`, irq-helper `db58d7c7…`, cores `16fbd7d1…`, unit `2510bc97…`); `OK-link` 10000 `carrier=1` up; `ATTACHED xdpdrv prog_id=75`; `OBS-WINDOW xdp-pps=186`, `PASS-RATIO 87`, `nic-rx-dropped-delta=7` (NOTE; baseline window 0); `M1S1B-ATTACH-DONE`; `STATE attached by boot helper (xdpdrv prog_id=75)`; **`M1S1C-START-DONE`**. Start to `active` took about 19 s.

**Paste 6 `verify` (rerun).** `OK-unit johnny-capture-xdp.service enabled=enabled active=active`; `OK-tuning-service active`; `OK-xdp-mode driver id=75`; IRQ pins unchanged; partition `l3_diff=0 l4_diff=0`; `VERIFY-WINDOW xdp-pkts-delta=1182 tcpdump-kernel-drops=0 nic-rx-dropped-delta=0`; `PASS-RATIO 84`; `ETHTOOL-DROP-DELTAS none (checked=16)`; **`M1S1C-VERIFY-DONE`**.

**Paste 6 `status` read: `XDP-ATTACH driver id=75`, `PROG-XDP-COUNT 1`, `PROG-OURS 1 ids=75`, `PINS` all present, `IRQ-COUNT 12`, `IRQ-CAPTURE ok`, `IRQ-BASELINE same`, `STAT pkts 25189 trunc 0 vlan 0`, `PART diff 0`, `KERNEL 7.0.0-42-generic`; `M1S1B-STATUS-DONE`, `M1S1C-STATUS-DONE`, `M1S1C-COLD-BOOT-VERIFY-DONE`.**

**Program id.** Slice 1b's `prog_id=472` was a this-boot-only attach and is gone after the reboot. `prog_id=75` is now the boot-attached observer, attached by this unit. Program ids are assigned per boot, so the next boot will likely show a different id **[Inference]**.

**`nic-rx-dropped` observation (still open, no root cause claimed).** Boot-time attach window `nic-rx-dropped-delta=7` against `0` in its baseline window (slice 1b saw `4` in its attach window). The steady-state `verify` window after boot saw `0`, with `ETHTOOL-DROP-DELTAS none (checked=16)` and `tcpdump-kernel-drops=0`. **[Inference]** the drops cluster around the attach itself, not steady-state capture; one clean window does not prove it.

### Follow-ups (parked nits; fixed in rev 3, helper reinstalled 2026-11-08 07:15:55 UTC)

1. `wait_boot_ready || true` falls through: if the bounded boot wait times out, `start` proceeds instead of stopping. **Rev 3:** `start` now prints `STOP-boot-wait-timeout tries=30 step=2s` and exits `1` before any change (`NOTHING-CHANGED`, `M1S1C-START-STOPS`); the unit shows `failed` and nothing is attached. Chosen because the preflight after the wait does not re-check `eno1np0` link/flags/MTU, so falling through could attach to a link that is not ready. Fail closed matches the unit's other preflight stops; recovery is `sudo systemctl restart johnny-capture-xdp.service` once the link is up, or the next boot.
2. Paste 6's ordering-cycle `grep` does not gate the `M1S1C-COLD-BOOT-VERIFY-DONE` token. **Rev 3:** a match prints `STOP-ordering-cycle-warning` and stops the chain.
3. The Rollback block prints `M1S1C-ROLLBACK-DONE` even if the unit was never active. **Rev 3:** the token now needs `status` to exit `0` with `XDP-ATTACH none` and `UNIT johnny-capture-xdp.service ... active=inactive`; else `STOP-rollback-not-clean`. The old `reset-failed ... || true` precedence hole (it let a failed `disable --now` fall through to the token) is closed with braces.
4. Paste 6 should wait for the unit to reach `active` before `verify` (the `STOP-locked` race seen on the first Paste 6 try above). **Rev 3:** Paste 6 polls `systemctl is-active` every 5 s for up to 120 s while the unit is `inactive`/`activating`, then needs `active` (`OK-unit-active waited=Ns`) or prints `STOP-unit-not-active-after-wait`.

Fixes 1–4 shipped in rev 3. Fix 1 is live on Johnny since the Nits reinstall (2026-11-08 07:15:55 UTC) but has not yet run at a boot; fixes 2–4 are rock-box paste changes and take effect the next time Paste 6 or Rollback is run. Rev 4 tightens fix 4: the wait loop's final sample is taken after the last sleep, not before it.

## Purpose and scope

Slice 1b (`docs/tool-install/module1-slice1b-attach.md`, rev 2) attached the passive, observe-only native-XDP counter program (`j_xdp_observe`, `XDP_PASS` only) on `eno1np0` (`xdpdrv`, `prog_id=472`) for that boot only. Without this unit, a reboot cleared the attach and `/sys/fs/bpf/johnny_m1s1b/`. With the unit enabled, a reboot runs `johnny-capture-xdp.service`, which attaches the observer again.

Slice 1c adds **boot persistence** for that exact pinned observer without altering the slice 1b BPF object, attach script, or detach script:

| File | Repo path | Johnny path | Mode / owner | sha256 |
|---|---|---|---|---|
| Boot unit | `etc/systemd/system/johnny-capture-xdp.service` | `/etc/systemd/system/johnny-capture-xdp.service` | `0644 root:root` | `2510bc97f3604a1466177b22205e34c60c1cbc0b028d83bc0c0583c14dc1f0e0` |
| Boot helper | `docs/tool-install/module1-slice1c-boot.sh` | `/root/m1s1b/module1-slice1c-boot.sh` | `0700 root:root` | `a501dbb7c49a611dd230f7c4fa09d6c1a7f8923f7302459180a197625ccc8c06` |
| Self-test (rock-box only) | `docs/tool-install/module1-slice1c-self-test.sh` | *(not copied to Johnny)* | `0755` | *(checked on rock-box)* |
| Unchanged XDP object | `docs/tool-install/module1-xdp-observe.o` | `/root/m1s1b/module1-xdp-observe.o` | `0700 root:root` | `8be9877f51d0d588285089a108123941e59c5e0aa7802ad80da90a376747e77d` |
| Unchanged attach helper | `docs/tool-install/module1-slice1b-attach.sh` | `/root/m1s1b/module1-slice1b-attach.sh` | `0700 root:root` | `f9f95ec6bc4311d23dda4b4c35b96bdf92ef03b1c2238bdf945c50bd60a190fb` |
| Unchanged detach helper | `docs/tool-install/module1-slice1b-detach.sh` | `/root/m1s1b/module1-slice1b-detach.sh` | `0700 root:root` | `f78ca14ed226a37e23ee239d65ba183e3c8b5a541369326c73fff4b61ea4cc58` |
| Unchanged IRQ helper | `etc/johnny/irq-affinity.sh` | `/etc/johnny/irq-affinity.sh` | `0755 root:root` | `db58d7c72b5a58cbd0c2533caa819d397e4c205242e30e5defb0eae0f4ab59e4` |
| Unchanged capture cores | `etc/johnny/capture-cores` | `/etc/johnny/capture-cores` | `0644 root:root` | `16fbd7d1f18d2fedb247d73edc3bc6aa040f5ab99bd3b48c35b79e543d22179b` |

## Unit ordering and step 13 boot-race lessons

1. **Ordered after `johnny-capture-irq.service` (`After=network-online.target johnny-capture-irq.service`, `Wants=network-online.target johnny-capture-irq.service`).** Step 13 (`irq-affinity.sh`) refuses to run with `STOP-xdp-present` if an XDP program is already attached on `eno1np0`. Therefore `johnny-capture-irq.service` must finish pinning the twelve `ice-eno1np0-TxRx-0..11` IRQs onto CPUs `1..4` before `johnny-capture-xdp.service` starts ([systemd.unit(5)](https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html)).
2. **No ordering on `johnny-capture-tuning.service` (rev 89/90 cycle + step 13c B1 lesson).** `johnny-capture-tuning.service` has `After=multi-user.target`, while `johnny-capture-xdp.service` has `WantedBy=multi-user.target` (implicit `Before=multi-user.target`). Adding `After=johnny-capture-tuning.service` would recreate the rev 89/90 systemd ordering cycle, and polling for tuning to become `active` inside `ExecStart` would recreate the step 13c B1 boot deadlock. Neither the unit nor `module1-slice1c-boot.sh` waits on `johnny-capture-tuning.service`; its state is logged as `OK-tuning-service active` or `NOTE-johnny-capture-tuning.service <state>`.
3. **Bounded readiness wait (`wait_boot_ready`).** Following step 13d (`docs/tool-install/step-13-irq-affinity.md`), `module1-slice1c-boot.sh start` waits up to `30 × 2 s = 60 s` for `eno1np0` (`UP`+`PROMISC`+`NOARP`, speed `10000`, carrier `1` or oper `up`, MTU `1500`, no IPv4/IPv6 address), `eno3` (`192.168.50.152/` + default route), and `johnny-capture-irq.service` (`active`) before running preflight. Rev 3: if the wait times out, `start` stops with `STOP-boot-wait-timeout` (exit `1`, nothing changed) instead of falling through.
4. **Idempotent on this boot (`ALREADY-ATTACHED`) and clean on cold boot (`STATE attached by boot helper`).**
   - When `XDP-ATTACH none` (cold boot or after stop), `start` delegates to `/root/m1s1b/module1-slice1b-attach.sh attach`, then re-verifies all post-attach invariants (`driver` mode, `PROG-XDP-COUNT 1`, pins present, 12 queue IRQs unchanged on CPUs 1–4, `combined=12`, `eno3` intact, L3/L4 partition within tolerance) and prints `STATE attached by boot helper (xdpdrv prog_id=N)` and `M1S1C-START-DONE`.
   - When `XDP-ATTACH driver id=N` is already our `j_xdp_observe` (`PROG-OURS 1 ids=N`, as on Johnny right now from slice 1b), `start` verifies all invariants without re-attaching or bouncing the link, saves `/root/m1s1b/irq-baseline.txt` if absent, and prints `ALREADY-ATTACHED xdpdrv prog_id=N` and `M1S1C-START-DONE`.
   - On any failure after our program is loaded or attached, `finish_start` runs `/root/m1s1b/module1-slice1b-detach.sh detach` (`REVERTING-TO-CLEAN-UNATTACHED`) so a failed start never leaves a half-attached program. A foreign XDP program is never detached (`STOP-xdp-foreign-attached`, `NOTHING-CHANGED`).
5. **Per-reason `ethtool -S eno1np0` drop deltas in `verify`.** To gather data for the open slice 1b observation (`nic-rx-dropped-delta=4` in Paste 4's 10 s observe window while `tcpdump` had `0 packets dropped by kernel`), `module1-slice1c-boot.sh verify` snapshots `ethtool -S eno1np0` before and after its 5 s `tcpdump` window and prints `ETHTOOL-DROP-DELTA <counter>=<delta> (before=<b> after=<a>)` for any non-zero drop/error/discard/miss/fifo/alloc counter delta, or `ETHTOOL-DROP-DELTAS none (checked=N)` when all are zero. No root cause is claimed.

## Pastes (all typed on Rock Box; sudo only inside `ssh -t aj@192.168.50.152`)

Every paste below is typed on **Rock Box** (`aj-rock-box`) and labeled `***<u>Run on Rock Box</u>***`. Pastes that touch Johnny run over `ssh aj@192.168.50.152` or `ssh -t aj@192.168.50.152 'sudo -v && ...'`. Do not run any paste until the adversarial-reviewer approves this draft and AJ says go.

### Paste 1 — Rock-box self-test (no root, no SSH)

***<u>Run on Rock Box</u>***

```bash
cd /home/aj/Projects/strix-halo-johnny
echo "8be9877f51d0d588285089a108123941e59c5e0aa7802ad80da90a376747e77d  docs/tool-install/module1-xdp-observe.o
f9f95ec6bc4311d23dda4b4c35b96bdf92ef03b1c2238bdf945c50bd60a190fb  docs/tool-install/module1-slice1b-attach.sh
f78ca14ed226a37e23ee239d65ba183e3c8b5a541369326c73fff4b61ea4cc58  docs/tool-install/module1-slice1b-detach.sh
a501dbb7c49a611dd230f7c4fa09d6c1a7f8923f7302459180a197625ccc8c06  docs/tool-install/module1-slice1c-boot.sh
2510bc97f3604a1466177b22205e34c60c1cbc0b028d83bc0c0583c14dc1f0e0  etc/systemd/system/johnny-capture-xdp.service" | sha256sum -c - &&
bash docs/tool-install/module1-slice1c-self-test.sh
```

Expect five `OK` lines, `PINS-OK`, `SHELLCHECK-OK`, `UNIT-VERIFY-OK`, `STATIC-CHECKS-OK`, `GATES-OK`, `UNIT-TESTS-OK`, `E2E-OK scenarios=8`, `RUNBOOK-OK`, and **`SELF-TEST-OK`**.

### Paste 2 — Copy slice 1c unit and boot helper to Johnny

***<u>Run on Rock Box</u>***

```bash
ssh aj@192.168.50.152 'mkdir -p /home/aj/cis-audit'
scp /home/aj/Projects/strix-halo-johnny/docs/tool-install/module1-slice1c-boot.sh /home/aj/Projects/strix-halo-johnny/etc/systemd/system/johnny-capture-xdp.service aj@192.168.50.152:/home/aj/cis-audit/
ssh aj@192.168.50.152 'cd /home/aj/cis-audit && echo "a501dbb7c49a611dd230f7c4fa09d6c1a7f8923f7302459180a197625ccc8c06  module1-slice1c-boot.sh
2510bc97f3604a1466177b22205e34c60c1cbc0b028d83bc0c0583c14dc1f0e0  johnny-capture-xdp.service" | sha256sum -c - && echo M1S1C-COPY-DONE'
```

Ends **`M1S1C-COPY-DONE`**.

### Paste 3 — Install unit + boot helper, `daemon-reload`, and pre-enable status check

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
cd /home/aj/cis-audit &&
echo "a501dbb7c49a611dd230f7c4fa09d6c1a7f8923f7302459180a197625ccc8c06  module1-slice1c-boot.sh
2510bc97f3604a1466177b22205e34c60c1cbc0b028d83bc0c0583c14dc1f0e0  johnny-capture-xdp.service" | sha256sum -c - &&
echo "8be9877f51d0d588285089a108123941e59c5e0aa7802ad80da90a376747e77d  /root/m1s1b/module1-xdp-observe.o
f9f95ec6bc4311d23dda4b4c35b96bdf92ef03b1c2238bdf945c50bd60a190fb  /root/m1s1b/module1-slice1b-attach.sh
f78ca14ed226a37e23ee239d65ba183e3c8b5a541369326c73fff4b61ea4cc58  /root/m1s1b/module1-slice1b-detach.sh" | sudo sha256sum -c - &&
sudo install -m 0700 -o root -g root module1-slice1c-boot.sh /root/m1s1b/module1-slice1c-boot.sh &&
sudo install -m 0644 -o root -g root johnny-capture-xdp.service /etc/systemd/system/johnny-capture-xdp.service &&
echo "a501dbb7c49a611dd230f7c4fa09d6c1a7f8923f7302459180a197625ccc8c06  /root/m1s1b/module1-slice1c-boot.sh
2510bc97f3604a1466177b22205e34c60c1cbc0b028d83bc0c0583c14dc1f0e0  /etc/systemd/system/johnny-capture-xdp.service" | sudo sha256sum -c - &&
sudo systemctl daemon-reload &&
sudo systemd-analyze verify /etc/systemd/system/johnny-capture-xdp.service &&
sudo bash /root/m1s1b/module1-slice1c-boot.sh status &&
echo M1S1C-INSTALL-DONE'
```

Expect `M1S1C-STATUS-DONE` (`UNIT johnny-capture-xdp.service enabled=disabled active=inactive`, plus the live slice 1b status lines) followed by **`M1S1C-INSTALL-DONE`**.

### Paste 4 — Enable and start `johnny-capture-xdp.service` on this boot, then verify

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "8be9877f51d0d588285089a108123941e59c5e0aa7802ad80da90a376747e77d  /root/m1s1b/module1-xdp-observe.o
f9f95ec6bc4311d23dda4b4c35b96bdf92ef03b1c2238bdf945c50bd60a190fb  /root/m1s1b/module1-slice1b-attach.sh
f78ca14ed226a37e23ee239d65ba183e3c8b5a541369326c73fff4b61ea4cc58  /root/m1s1b/module1-slice1b-detach.sh
a501dbb7c49a611dd230f7c4fa09d6c1a7f8923f7302459180a197625ccc8c06  /root/m1s1b/module1-slice1c-boot.sh
2510bc97f3604a1466177b22205e34c60c1cbc0b028d83bc0c0583c14dc1f0e0  /etc/systemd/system/johnny-capture-xdp.service" | sudo sha256sum -c - &&
sudo systemctl enable --now johnny-capture-xdp.service &&
sudo journalctl -b -u johnny-capture-xdp.service --no-pager &&
sudo bash /root/m1s1b/module1-slice1c-boot.sh verify &&
echo M1S1C-ENABLE-THIS-BOOT-DONE'
```

What to expect on this boot:
- If slice 1b is still attached (`prog_id=472`), `journalctl -b -u johnny-capture-xdp.service` shows `ALREADY-ATTACHED xdpdrv prog_id=472` and `M1S1C-START-DONE`. If unattached, it runs the full attach and shows `STATE attached by boot helper (xdpdrv prog_id=N)` and `M1S1C-START-DONE`.
- `verify` runs a 5 s `tcpdump` + `ethtool -S eno1np0` window and prints `OK-unit johnny-capture-xdp.service enabled=enabled active=active`, `VERIFY-WINDOW ...`, `PASS-RATIO ...`, `ETHTOOL-DROP-DELTA ...` (or `ETHTOOL-DROP-DELTAS none (checked=N)`), `OK-xdp-pass-tcpdump-sees-traffic`, twelve `IRQ-VERIFY` lines on CPUs `1..4`, `STAT` / `STAT-RXQ` / `PART`, **`M1S1C-VERIFY-DONE`**, and **`M1S1C-ENABLE-THIS-BOOT-DONE`**.
- Because `systemctl enable --now` enables the unit before starting it, if `start` or `verify` fails (`M1S1C-ENABLE-THIS-BOOT-DONE` not printed), run the Rollback block below to disable and remove the unit before rebooting.

### Paste 5 — Cold reboot to prove unattended boot persistence (separate paste per AGENTS.md)

Have AMT KVM ready and the LUKS recovery passphrase at hand in case TPM unlock needs console attention.

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v && echo M1S1C-REBOOT-ISSUED && sudo systemctl reboot'
```

Wait ~60–90 s for Johnny to reboot and complete the boot oneshots, then run Paste 6. Paste 6 itself polls `johnny-capture-xdp.service` every 5 s for up to 120 s while it is `inactive` or `activating`, and runs `verify` only once the unit is `active`, so the unit's `start` has released the helper lock by then. (The applied 2026-11-08 first try predates this wait: `verify` ran while `start` still held the lock and stopped at `STOP-locked`.) If Paste 6 prints `STOP-unit-not-active-after-wait state=failed`, read the `journalctl` output above it: with the rev 3 helper a `STOP-boot-wait-timeout` there means the unit failed closed with nothing attached (recover with `sudo systemctl restart johnny-capture-xdp.service` once `eno1np0` is up, or the next boot). If it prints `STOP-unit-not-active-after-wait state=activating`, the unit's `start` was still running at 120 s; wait 30–60 s and re-run Paste 6. `STOP-locked` from `verify` now means some other helper run (for example a manual `status` or `verify` in another shell) held the lock; let it finish and re-run Paste 6.

### Paste 6 — Post-reboot verify (unattended boot attach + `ethtool -S` drop deltas + cycle check)

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
uptime &&
{ systemctl is-system-running || true; } &&
cyc=$(sudo journalctl -b -p warning..emerg --no-pager) &&
if printf "%s\n" "$cyc" | grep -Ei "ordering cycle"; then echo STOP-ordering-cycle-warning; false; else echo OK-no-ordering-cycle-warnings; fi &&
sudo journalctl -b -u johnny-capture-irq.service -u johnny-capture-xdp.service -u johnny-capture-tuning.service --no-pager &&
for w in $(seq 0 5 120); do ac=$(systemctl is-active johnny-capture-xdp.service || true); case "$ac" in inactive|activating) if [ "$w" -lt 120 ]; then sleep 5; fi ;; *) break ;; esac; done &&
if [ "$ac" = active ]; then echo "OK-unit-active waited=${w}s"; else echo "STOP-unit-not-active-after-wait state=$ac waited=${w}s"; false; fi &&
sudo bash /root/m1s1b/module1-slice1c-boot.sh verify &&
sleep 10 &&
sudo bash /root/m1s1b/module1-slice1c-boot.sh status &&
echo M1S1C-COLD-BOOT-VERIFY-DONE'
```

What to look for after cold reboot:
- `OK-no-ordering-cycle-warnings` (no rev 89/90 systemd ordering cycle). Rev 3: any `ordering cycle` line is printed, then `STOP-ordering-cycle-warning`, and the chain stops before `M1S1C-COLD-BOOT-VERIFY-DONE`.
- Rev 3: `OK-unit-active waited=Ns` (the paste polls every 5 s, up to 120 s, while the unit is `inactive` or `activating`). Rev 4: no sleep follows the last sample, so the final state is read at the 120 s mark (`waited=120s`), not 5 s before it. Any other end state (`failed`, still `inactive`/`activating` at 120 s) prints `STOP-unit-not-active-after-wait state=... waited=...s` and stops before `verify`.
- `journalctl -b` shows `johnny-capture-irq.service` finished before `johnny-capture-xdp.service` started, and `johnny-capture-xdp.service` logged `M1S1B-ATTACH-DONE` (the unchanged pinned `module1-slice1b-attach.sh` still prints its slice 1b `attached for this boot only` note right before `M1S1B-ATTACH-DONE`), followed by `STATE attached by boot helper (xdpdrv prog_id=N)` and `M1S1C-START-DONE` with no manual start.
- `verify` ends **`M1S1C-VERIFY-DONE`**, and the unpiped `status` read 10 s later prints the full status transcript ending **`M1S1C-STATUS-DONE`** with advancing `STAT pkts` / `STAT bytes`, gated on `status` exiting `0` before **`M1S1C-COLD-BOOT-VERIFY-DONE`**.

### Nits reinstall (rev 3) — APPLIED 2026-11-08 07:15:55 UTC

Replaces only `/root/m1s1b/module1-slice1c-boot.sh` on Johnny with the rev 3 helper. It does not restart the unit, so the attached observer is not touched; the new `start` code runs at the next boot (or next unit start). First re-run Paste 1 on this branch and get **`SELF-TEST-OK`**. Do not run until the adversarial-reviewer approves and AJ says go.

**Applied record (rev 4).** AJ ran this paste at **2026-11-08 07:15:55 UTC (1:15:55 AM CST)**. Paste 1 first: `E2E-OK scenarios=8`, `RUNBOOK-OK blocks=8`, **`SELF-TEST-OK`**. Hashes OK; installed helper sha256 `a501dbb7c49a611dd230f7c4fa09d6c1a7f8923f7302459180a197625ccc8c06`. `verify`: `OK-xdp-mode driver id=75` before and after the install (the observer was not re-attached), IRQ pins unchanged, partitions `l3_diff=0 l4_diff=0`, 5 s window `xdp=443 tcpdump=345 pct=77` with `NOTE-pass-ratio-low`, kernel drops `0`, NIC drops `0`, `ETHTOOL-DROP-DELTAS none`, **`M1S1C-VERIFY-DONE`**, **`M1S1C-NITS-REINSTALL-DONE`**. The 77 % pass ratio is one observed 5 s window (earlier windows: 90, 87, 84); it is a NOTE, not a gate, and is not claimed to be the normal value or proof of lossless capture. Zero kernel and NIC drops were measured in that window only. No root cause for the gap is claimed. The rev 3 `start` path (fail-closed boot wait) has not run yet: the unit was not restarted, and no reboot since the reinstall has been reported. An optional later reboot + Paste 6 would prove it at cold boot; it is not required to close this reinstall.

***<u>Run on Rock Box</u>***

```bash
cd /home/aj/Projects/strix-halo-johnny &&
echo "a501dbb7c49a611dd230f7c4fa09d6c1a7f8923f7302459180a197625ccc8c06  docs/tool-install/module1-slice1c-boot.sh" | sha256sum -c - &&
scp /home/aj/Projects/strix-halo-johnny/docs/tool-install/module1-slice1c-boot.sh aj@192.168.50.152:/home/aj/cis-audit/ &&
ssh -t aj@192.168.50.152 'sudo -v &&
cd /home/aj/cis-audit &&
echo "a501dbb7c49a611dd230f7c4fa09d6c1a7f8923f7302459180a197625ccc8c06  module1-slice1c-boot.sh" | sha256sum -c - &&
echo "8be9877f51d0d588285089a108123941e59c5e0aa7802ad80da90a376747e77d  /root/m1s1b/module1-xdp-observe.o
f9f95ec6bc4311d23dda4b4c35b96bdf92ef03b1c2238bdf945c50bd60a190fb  /root/m1s1b/module1-slice1b-attach.sh
f78ca14ed226a37e23ee239d65ba183e3c8b5a541369326c73fff4b61ea4cc58  /root/m1s1b/module1-slice1b-detach.sh
2510bc97f3604a1466177b22205e34c60c1cbc0b028d83bc0c0583c14dc1f0e0  /etc/systemd/system/johnny-capture-xdp.service" | sudo sha256sum -c - &&
sudo install -m 0700 -o root -g root module1-slice1c-boot.sh /root/m1s1b/module1-slice1c-boot.sh &&
echo "a501dbb7c49a611dd230f7c4fa09d6c1a7f8923f7302459180a197625ccc8c06  /root/m1s1b/module1-slice1c-boot.sh" | sudo sha256sum -c - &&
sudo systemctl daemon-reload &&
sudo bash /root/m1s1b/module1-slice1c-boot.sh verify &&
echo M1S1C-NITS-REINSTALL-DONE'
```

Expect one `OK` hash line for the rock-box file, one for the copy on Johnny, four for the unchanged files, one for the installed helper, then `verify` output ending **`M1S1C-VERIFY-DONE`** and **`M1S1C-NITS-REINSTALL-DONE`**. If any hash fails, nothing was installed past that line. If `verify` fails after the install, the observer is still attached by the rev 2 start; report the STOP line. **[Assumption]** `verify` from the rev 3 helper reads the same live state as rev 2 (only `start`'s wait handling changed). The cold-boot proof of fix 1 is a later reboot + Paste 6, not part of this paste.

## Rollback / disable (not part of the paste sequence above)

Run this block only to stop and disable the boot persistence unit, detach `j_xdp_observe` from `eno1np0`, remove `/etc/systemd/system/johnny-capture-xdp.service`, and return Johnny to the unattached state while keeping `/root/m1s1b/` intact.

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "f78ca14ed226a37e23ee239d65ba183e3c8b5a541369326c73fff4b61ea4cc58  /root/m1s1b/module1-slice1b-detach.sh" | sudo sha256sum -c - &&
bh=$(sudo sha256sum /root/m1s1b/module1-slice1c-boot.sh) &&
bh=${bh%% *} &&
case "$bh" in a501dbb7c49a611dd230f7c4fa09d6c1a7f8923f7302459180a197625ccc8c06) echo "OK-boot-hash rev3 $bh" ;; f05e7ac425ed78837ab57880f483ed42eeea431c5037da09248e11eea6a580bc) echo "OK-boot-hash rev2 $bh" ;; *) echo "STOP-boot-hash $bh"; false ;; esac &&
sudo systemctl disable --now johnny-capture-xdp.service &&
sudo rm -f /etc/systemd/system/johnny-capture-xdp.service &&
sudo systemctl daemon-reload &&
{ sudo systemctl reset-failed johnny-capture-xdp.service 2>/dev/null || true; } &&
if st=$(sudo bash /root/m1s1b/module1-slice1c-boot.sh status); then printf "%s\n" "$st"; else printf "%s\n" "$st"; echo STOP-rollback-status-failed; false; fi &&
if printf "%s\n" "$st" | grep -qx "XDP-ATTACH none" && printf "%s\n" "$st" | grep -Eq "^UNIT johnny-capture-xdp[.]service .* active=inactive$"; then echo M1S1C-ROLLBACK-DONE; else echo STOP-rollback-not-clean; false; fi'
```

Because `ExecStop=/bin/bash /root/m1s1b/module1-slice1c-boot.sh stop` runs on `systemctl disable --now`, stopping the unit invokes the pinned detach helper (`M1S1B-DETACH-DONE` + `M1S1C-STOP-DONE`), removes `/sys/fs/bpf/johnny_m1s1b/`, verifies `XDP-ATTACH none` and `IRQ-CAPTURE ok`, and ends **`M1S1C-ROLLBACK-DONE`**. Rev 3: the boot helper hash check accepts the rev 3 hash or the rev 2 hash (Johnny has run the rev 3 helper since the Nits reinstall on 2026-11-08 07:15:55 UTC; the rev 2 hash stays accepted for older states), and the token prints only when `status` exits `0` and shows `XDP-ATTACH none` and `UNIT johnny-capture-xdp.service ... active=inactive`; else `STOP-rollback-status-failed` or `STOP-rollback-not-clean` (then run `sudo bash /root/m1s1b/module1-slice1b-detach.sh detach` and re-check `status`).

## What each STOP means

| STOP line | Meaning and action |
|---|---|
| `STOP-host`, `STOP-not-root`, `STOP-kernel <v>`, `STOP-no-iface eno1np0`, `STOP-args`, `STOP-locked` | Host/root/kernel/interface/arg/lock gate fired before any change. |
| `STOP-<what>-not-root-owned-or-missing`, `STOP-<what>-hash` | File in `/root/m1s1b/`, `/etc/johnny/`, or `/etc/systemd/system/johnny-capture-xdp.service` is missing, not `0:0`, group/world-writable, or does not match its pinned sha256. |
| `STOP-boot-wait-timeout tries=30 step=2s` | Rev 3: the bounded 60 s boot-ready wait (`eno1np0`, `eno3`, `johnny-capture-irq.service`) timed out; `start` stops before any change (`NOTHING-CHANGED`) and the unit shows `failed`. The `NOTE-wait-*` lines above it name what was not ready. |
| `STOP-suricata ...`, `STOP-irq-service-not-active ...`, `STOP-eno3-not-as-recorded` | Preflight environment check failed after the bounded 60 s boot-ready wait (`NOTHING-CHANGED`). |
| `STOP-ordering-cycle-warning`, `STOP-unit-not-active-after-wait ...` | Rev 3 Paste 6 gates: a systemd ordering cycle was logged this boot, or the unit did not reach `active` within 120 s. Read-only; no done token. |
| `STOP-boot-hash ...`, `STOP-rollback-status-failed`, `STOP-rollback-not-clean` | Rev 3 Rollback gates: helper hash is neither rev 3 nor rev 2 (nothing changed), or after disable `status` failed or still shows an attach or a non-`inactive` unit. |
| `STOP-xdp-foreign-progs-loaded`, `STOP-xdp-foreign-attached`, `STOP-xdp-foreign-or-unexpected` | A non-`j_xdp_observe` XDP program is loaded or attached; boot helper refuses without touching it (`NOTHING-CHANGED`). |
| `STOP-attach-helper-failed`, `STOP-attach-helper-missing-token`, `STOP-xdp-mode-not-driver`, or any `STOP-*-post-start` / `STOP-*-already-attached` | Attach or invariant check failed; `finish_start` prints `REVERTING-TO-CLEAN-UNATTACHED`, runs `/root/m1s1b/module1-slice1b-detach.sh detach`, and ends `M1S1C-START-STOPS`. If `eno1np0` flags (`PROMISC`) and IRQ pins both moved, restore `UP`/`PROMISC`/`NOARP` flags before running `sudo /etc/johnny/irq-affinity.sh apply`. |
| `STOP-unit-not-enabled`, `STOP-unit-not-active`, `STOP-tcpdump-verify-failed`, `STOP-observer-no-count`, `STOP-no-traffic-verify`, `STOP-pass-broken-verify` | Read-only `verify` check failed. |

## Tokens AJ sends back

1. Paste 1 (Rock Box): **`SELF-TEST-OK`**
2. Paste 2 (Rock Box): **`M1S1C-COPY-DONE`**
3. Paste 3 (Rock Box → Johnny): **`M1S1C-STATUS-DONE`** and **`M1S1C-INSTALL-DONE`**
4. Paste 4 (Rock Box → Johnny, this boot): **`M1S1C-START-DONE`**, **`M1S1C-VERIFY-DONE`**, and **`M1S1C-ENABLE-THIS-BOOT-DONE`** (plus the `VERIFY-WINDOW` and `ETHTOOL-DROP-DELTA` / `ETHTOOL-DROP-DELTAS` lines)
5. Paste 5 (Rock Box → Johnny): **`M1S1C-REBOOT-ISSUED`**
6. Paste 6 (Rock Box → Johnny, after cold reboot): **`M1S1C-START-DONE`** (in journal), **`M1S1C-VERIFY-DONE`**, **`M1S1C-STATUS-DONE`**, and **`M1S1C-COLD-BOOT-VERIFY-DONE`**
7. Nits reinstall (rev 3, applied 2026-11-08 07:15:55 UTC): **`M1S1C-VERIFY-DONE`** and **`M1S1C-NITS-REINSTALL-DONE`**
8. Rollback (only if run): **`M1S1C-ROLLBACK-DONE`**

## Assumptions and sources

- **[Assumption]** `ethtool -S eno1np0` on Johnny's `ice` driver prints `key: value` counter lines where drop/discard/error/miss/fifo/alloc counters match `(drop|disc|err|miss|over|fifo|oob|fail|alloc|crc|csum|jabber|undersize|oversize|frag|unknown)`. If `ethtool -S` is unavailable or returns no matching lines, `verify` prints `NOTE-ethtool-S-unavailable` or `ETHTOOL-DROP-DELTAS none (checked=0)` without failing.
- **[Assumption]** 60 s (`WAIT_BOOT_TRIES=30` × `WAIT_STEP=2`) is sufficient on cold boot for `eno1np0` carrier, `eno3` DHCP (`192.168.50.152`), and `johnny-capture-irq.service` (`After=johnny-capture-irq.service` already orders the unit after the IRQ oneshot; the loop covers link/DHCP settle). Rev 3: if it is not sufficient, the unit fails closed with `STOP-boot-wait-timeout` rather than attaching.
- Sources: [systemd.unit(5)](https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html), [systemd.service(5)](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html), `docs/tool-install/module1-slice1b-attach.md` rev 2, `docs/tool-install/step-13-irq-affinity.md`.
