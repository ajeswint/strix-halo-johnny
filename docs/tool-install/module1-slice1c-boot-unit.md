# Module 1, slice 1c — boot persistence unit (`johnny-capture-xdp.service`) for `j_xdp_observe` on `eno1np0`

Rev 1, 2026-11-06 America/Chicago. Status: **drafted, not applied.** Branch `claude/module1-slice1c-boot-unit` off `origin/claude/practical-ritchie-4c6vvf` (base tip `e41c0db`). Nothing in this file has been run on Johnny.

## Purpose and scope

Slice 1b (`docs/tool-install/module1-slice1b-attach.md`, rev 2) attached the passive, observe-only native-XDP counter program (`j_xdp_observe`, `XDP_PASS` only) on `eno1np0` (`xdpdrv`, `prog_id=472`) for the current boot only. A reboot detaches it and clears `/sys/fs/bpf/johnny_m1s1b/`.

Slice 1c adds **boot persistence** for that exact pinned observer without altering the slice 1b BPF object, attach script, or detach script:

| File | Repo path | Johnny path | Mode / owner | sha256 |
|---|---|---|---|---|
| Boot unit | `etc/systemd/system/johnny-capture-xdp.service` | `/etc/systemd/system/johnny-capture-xdp.service` | `0644 root:root` | `2510bc97f3604a1466177b22205e34c60c1cbc0b028d83bc0c0583c14dc1f0e0` |
| Boot helper | `docs/tool-install/module1-slice1c-boot.sh` | `/root/m1s1b/module1-slice1c-boot.sh` | `0700 root:root` | `f05e7ac425ed78837ab57880f483ed42eeea431c5037da09248e11eea6a580bc` |
| Self-test (rock-box only) | `docs/tool-install/module1-slice1c-self-test.sh` | *(not copied to Johnny)* | `0755` | *(checked on rock-box)* |
| Unchanged XDP object | `docs/tool-install/module1-xdp-observe.o` | `/root/m1s1b/module1-xdp-observe.o` | `0700 root:root` | `8be9877f51d0d588285089a108123941e59c5e0aa7802ad80da90a376747e77d` |
| Unchanged attach helper | `docs/tool-install/module1-slice1b-attach.sh` | `/root/m1s1b/module1-slice1b-attach.sh` | `0700 root:root` | `f9f95ec6bc4311d23dda4b4c35b96bdf92ef03b1c2238bdf945c50bd60a190fb` |
| Unchanged detach helper | `docs/tool-install/module1-slice1b-detach.sh` | `/root/m1s1b/module1-slice1b-detach.sh` | `0700 root:root` | `f78ca14ed226a37e23ee239d65ba183e3c8b5a541369326c73fff4b61ea4cc58` |
| Unchanged IRQ helper | `etc/johnny/irq-affinity.sh` | `/etc/johnny/irq-affinity.sh` | `0755 root:root` | `db58d7c72b5a58cbd0c2533caa819d397e4c205242e30e5defb0eae0f4ab59e4` |
| Unchanged capture cores | `etc/johnny/capture-cores` | `/etc/johnny/capture-cores` | `0644 root:root` | `16fbd7d1f18d2fedb247d73edc3bc6aa040f5ab99bd3b48c35b79e543d22179b` |

## Unit ordering and step 13 boot-race lessons

1. **Ordered after `johnny-capture-irq.service` (`After=network-online.target johnny-capture-irq.service`, `Wants=network-online.target johnny-capture-irq.service`).** Step 13 (`irq-affinity.sh`) refuses to run with `STOP-xdp-present` if an XDP program is already attached on `eno1np0`. Therefore `johnny-capture-irq.service` must finish pinning the twelve `ice-eno1np0-TxRx-0..11` IRQs onto CPUs `1..4` before `johnny-capture-xdp.service` starts ([systemd.unit(5)](https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html)).
2. **No ordering on `johnny-capture-tuning.service` (rev 89/90 cycle + step 13c B1 lesson).** `johnny-capture-tuning.service` has `After=multi-user.target`, while `johnny-capture-xdp.service` has `WantedBy=multi-user.target` (implicit `Before=multi-user.target`). Adding `After=johnny-capture-tuning.service` would recreate the rev 89/90 systemd ordering cycle, and polling for tuning to become `active` inside `ExecStart` would recreate the step 13c B1 boot deadlock. Neither the unit nor `module1-slice1c-boot.sh` waits on `johnny-capture-tuning.service`; its state is logged as `OK-tuning-service active` or `NOTE-johnny-capture-tuning.service <state>`.
3. **Bounded readiness wait (`wait_boot_ready`).** Following step 13d (`docs/tool-install/step-13-irq-affinity.md`), `module1-slice1c-boot.sh start` waits up to `30 × 2 s = 60 s` for `eno1np0` (`UP`+`PROMISC`+`NOARP`, speed `10000`, carrier `1` or oper `up`, MTU `1500`, no IPv4/IPv6 address), `eno3` (`192.168.50.152/` + default route), and `johnny-capture-irq.service` (`active`) before running preflight.
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
f05e7ac425ed78837ab57880f483ed42eeea431c5037da09248e11eea6a580bc  docs/tool-install/module1-slice1c-boot.sh
2510bc97f3604a1466177b22205e34c60c1cbc0b028d83bc0c0583c14dc1f0e0  etc/systemd/system/johnny-capture-xdp.service" | sha256sum -c - &&
bash docs/tool-install/module1-slice1c-self-test.sh
```

Expect five `OK` lines, `PINS-OK`, `SHELLCHECK-OK`, `UNIT-VERIFY-OK`, `STATIC-CHECKS-OK`, `GATES-OK`, `UNIT-TESTS-OK`, `E2E-OK scenarios=7`, `RUNBOOK-OK`, and **`SELF-TEST-OK`**.

### Paste 2 — Copy slice 1c unit and boot helper to Johnny

***<u>Run on Rock Box</u>***

```bash
ssh aj@192.168.50.152 'mkdir -p /home/aj/cis-audit'
scp /home/aj/Projects/strix-halo-johnny/docs/tool-install/module1-slice1c-boot.sh /home/aj/Projects/strix-halo-johnny/etc/systemd/system/johnny-capture-xdp.service aj@192.168.50.152:/home/aj/cis-audit/
ssh aj@192.168.50.152 'cd /home/aj/cis-audit && echo "f05e7ac425ed78837ab57880f483ed42eeea431c5037da09248e11eea6a580bc  module1-slice1c-boot.sh
2510bc97f3604a1466177b22205e34c60c1cbc0b028d83bc0c0583c14dc1f0e0  johnny-capture-xdp.service" | sha256sum -c - && echo M1S1C-COPY-DONE'
```

Ends **`M1S1C-COPY-DONE`**.

### Paste 3 — Install unit + boot helper, `daemon-reload`, and pre-enable status check

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
cd /home/aj/cis-audit &&
echo "f05e7ac425ed78837ab57880f483ed42eeea431c5037da09248e11eea6a580bc  module1-slice1c-boot.sh
2510bc97f3604a1466177b22205e34c60c1cbc0b028d83bc0c0583c14dc1f0e0  johnny-capture-xdp.service" | sha256sum -c - &&
echo "8be9877f51d0d588285089a108123941e59c5e0aa7802ad80da90a376747e77d  /root/m1s1b/module1-xdp-observe.o
f9f95ec6bc4311d23dda4b4c35b96bdf92ef03b1c2238bdf945c50bd60a190fb  /root/m1s1b/module1-slice1b-attach.sh
f78ca14ed226a37e23ee239d65ba183e3c8b5a541369326c73fff4b61ea4cc58  /root/m1s1b/module1-slice1b-detach.sh" | sudo sha256sum -c - &&
sudo install -m 0700 -o root -g root module1-slice1c-boot.sh /root/m1s1b/module1-slice1c-boot.sh &&
sudo install -m 0644 -o root -g root johnny-capture-xdp.service /etc/systemd/system/johnny-capture-xdp.service &&
echo "f05e7ac425ed78837ab57880f483ed42eeea431c5037da09248e11eea6a580bc  /root/m1s1b/module1-slice1c-boot.sh
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
f05e7ac425ed78837ab57880f483ed42eeea431c5037da09248e11eea6a580bc  /root/m1s1b/module1-slice1c-boot.sh
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

Wait ~60–90 s for Johnny to reboot and complete the boot oneshots, then run Paste 6 (if Paste 6 runs while `johnny-capture-irq.service` or `johnny-capture-xdp.service` is still finishing its boot readiness wait and stops at `STOP-unit-not-active`, wait another 30–60 s and re-run Paste 6).

### Paste 6 — Post-reboot verify (unattended boot attach + `ethtool -S` drop deltas + cycle check)

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
uptime &&
systemctl is-system-running || true &&
sudo journalctl -b -p warning..emerg --no-pager | grep -Ei "ordering cycle" || echo OK-no-ordering-cycle-warnings &&
sudo journalctl -b -u johnny-capture-irq.service -u johnny-capture-xdp.service -u johnny-capture-tuning.service --no-pager &&
sudo bash /root/m1s1b/module1-slice1c-boot.sh verify &&
sleep 10 &&
sudo bash /root/m1s1b/module1-slice1c-boot.sh status &&
echo M1S1C-COLD-BOOT-VERIFY-DONE'
```

What to look for after cold reboot:
- `OK-no-ordering-cycle-warnings` (no rev 89/90 systemd ordering cycle).
- `journalctl -b` shows `johnny-capture-irq.service` finished before `johnny-capture-xdp.service` started, and `johnny-capture-xdp.service` logged `M1S1B-ATTACH-DONE` (the unchanged pinned `module1-slice1b-attach.sh` still prints its slice 1b `attached for this boot only` note right before `M1S1B-ATTACH-DONE`), followed by `STATE attached by boot helper (xdpdrv prog_id=N)` and `M1S1C-START-DONE` with no manual start.
- `verify` ends **`M1S1C-VERIFY-DONE`**, and the unpiped `status` read 10 s later prints the full status transcript ending **`M1S1C-STATUS-DONE`** with advancing `STAT pkts` / `STAT bytes`, gated on `status` exiting `0` before **`M1S1C-COLD-BOOT-VERIFY-DONE`**.

## Rollback / disable (not part of the paste sequence above)

Run this block only to stop and disable the boot persistence unit, detach `j_xdp_observe` from `eno1np0`, remove `/etc/systemd/system/johnny-capture-xdp.service`, and return Johnny to the unattached state while keeping `/root/m1s1b/` intact.

***<u>Run on Rock Box</u>***

```bash
ssh -t aj@192.168.50.152 'sudo -v &&
echo "f78ca14ed226a37e23ee239d65ba183e3c8b5a541369326c73fff4b61ea4cc58  /root/m1s1b/module1-slice1b-detach.sh
f05e7ac425ed78837ab57880f483ed42eeea431c5037da09248e11eea6a580bc  /root/m1s1b/module1-slice1c-boot.sh" | sudo sha256sum -c - &&
sudo systemctl disable --now johnny-capture-xdp.service &&
sudo rm -f /etc/systemd/system/johnny-capture-xdp.service &&
sudo systemctl daemon-reload &&
sudo systemctl reset-failed johnny-capture-xdp.service 2>/dev/null || true &&
sudo bash /root/m1s1b/module1-slice1c-boot.sh status &&
echo M1S1C-ROLLBACK-DONE'
```

Because `ExecStop=/bin/bash /root/m1s1b/module1-slice1c-boot.sh stop` runs on `systemctl disable --now`, stopping the unit invokes the pinned detach helper (`M1S1B-DETACH-DONE` + `M1S1C-STOP-DONE`), removes `/sys/fs/bpf/johnny_m1s1b/`, verifies `XDP-ATTACH none` and `IRQ-CAPTURE ok`, and ends **`M1S1C-ROLLBACK-DONE`**.

## What each STOP means

| STOP line | Meaning and action |
|---|---|
| `STOP-host`, `STOP-not-root`, `STOP-kernel <v>`, `STOP-no-iface eno1np0`, `STOP-args`, `STOP-locked` | Host/root/kernel/interface/arg/lock gate fired before any change. |
| `STOP-<what>-not-root-owned-or-missing`, `STOP-<what>-hash` | File in `/root/m1s1b/`, `/etc/johnny/`, or `/etc/systemd/system/johnny-capture-xdp.service` is missing, not `0:0`, group/world-writable, or does not match its pinned sha256. |
| `STOP-suricata ...`, `STOP-irq-service-not-active ...`, `STOP-eno3-not-as-recorded` | Preflight environment check failed after the bounded 60 s boot-ready wait (`NOTHING-CHANGED`). |
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
7. Rollback (only if run): **`M1S1C-ROLLBACK-DONE`**

## Assumptions and sources

- **[Assumption]** `ethtool -S eno1np0` on Johnny's `ice` driver prints `key: value` counter lines where drop/discard/error/miss/fifo/alloc counters match `(drop|disc|err|miss|over|fifo|oob|fail|alloc|crc|csum|jabber|undersize|oversize|frag|unknown)`. If `ethtool -S` is unavailable or returns no matching lines, `verify` prints `NOTE-ethtool-S-unavailable` or `ETHTOOL-DROP-DELTAS none (checked=0)` without failing.
- **[Assumption]** 60 s (`WAIT_BOOT_TRIES=30` × `WAIT_STEP=2`) is sufficient on cold boot for `eno1np0` carrier, `eno3` DHCP (`192.168.50.152`), and `johnny-capture-irq.service` (`After=johnny-capture-irq.service` already orders the unit after the IRQ oneshot; the loop covers link/DHCP settle).
- Sources: [systemd.unit(5)](https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html), [systemd.service(5)](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html), `docs/tool-install/module1-slice1b-attach.md` rev 2, `docs/tool-install/step-13-irq-affinity.md`.
