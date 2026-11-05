# Step 13 — IRQ affinity (draft)

Drafted 2026-11-05 ~13:51 CT. Handoff rev 84 at draft time. No command from this draft has run on Johnny, on rock-box, or on ABLETON_BOX.

## Status

Step 13 is **drafted, not applied**. Runbook: `docs/tool-install/step-13-irq-affinity.md`. The paste prints `STEP13-IRQ-DONE` only after it pins `eno1np0` MSI-X IRQs onto the CPUs in `/etc/johnny/capture-cores` and the checks pass. That line has not been printed. CIS L1 totals unchanged: **225 PASS, 18 PASS (manual), 31 N/A, 0 FAIL** (274/274). Steps 6, 8, 9, and 11 stay applied. Step 12 stays research-complete (`STEP12-RESEARCH-DONE`, `SLOTS-DONE`). Lab stays option A.

Handoff Next steps item 13 stays the finished Agent team note. This file is the tool-install step that replaces "IRQ affinity later".

## Scope in the draft

- Pin only `eno1np0`. `eno2np1` stays admin-down. Its masks are recorded and must not change. The policyscript bans that PCI device so an `irqbalance` restart does not move it. CPU 0 may still be in the `eno2np1` mask.
- Capture CPUs are the step 11 file, sha256 `16fbd7d1f18d2fedb247d73edc3bc6aa040f5ab99bd3b48c35b79e543d22179b` (`1` through `4`). CPU 0 is rejected.
- RPS, XPS, and RSS are not written. Queue count, rings, and offloads are not changed.
- `irqbalance` is not stopped and not masked. If the unit exists and matches Debian `1.9.4-3`'s `/etc/default/irqbalance`, the paste adds a policyscript and restarts only when the daemon is active and does not already have that argument. If the package is absent, the paste still pins and prints `NOTE-no-irqbalance`. It does not apt-install.
- Revert script is installed at `/root/step13-revert.sh` before mask saves and before the env-file edit. A nonzero exit after a change runs it. SIGHUP and SIGPIPE are ignored.
- `eno3` address and default route are gates before and after. No netplan edit. No reboot. No GRUB. No XDP program left attached. ABLETON_BOX has no command.

## Check on this draft

`bash -n` on the apply script, the revert script, the helper, the policyscript, and the self-test exited 0. `bash docs/tool-install/step-13-self-test.sh` printed `SELF-TEST-OK`. The apply script on this draft host printed `STOP-host` and exited 1 before opening a log. That host is not Johnny.

The self-test covers queue-to-CPU assignment (`TxRx-0` → CPU 1, `TxRx-5` → CPU 2, misc → CPU 1), rejection of CPU 0 in the core file, rejection of a mask that contains CPU 0, the policyscript banning the two ice BDFs and not `eno3`, and the `IRQBALANCE_ARGS` editor (append, unchanged, foreign args, banned CPU list). It does not write `/proc/irq`.

## Nits (still not applied)

Claude reviewed tip `df2ea53` APPROVE-WITH-NITS. The draft now:

- Reads masks after the 12 second wait and does not call the helper again. `IRQ-HELD` means they still matched. `STOP-irq-held` reverts.
- Skips `eno2np1` MSI vectors that have no `/proc/irq` entry. Save lines use `irq|mask|name`. An `eno1np0` vector in that state is `STOP-eno1-unrequested` before a write.
- Says why the apply script does not store its own sha256, and checks the helper hash before `source`. The helper remains `etc/johnny/irq-affinity.sh`.
- Writes the irqbalance unit dump under `/root` with `mktemp`. Rotates the apply log to `.1`. Prints `NO-CHANGE` when a first run stops before a change.
- Notes the boot oneshot does not retry, a non-queue IRQ name is `NOTE-irq-fallback` onto CPU 1, and rock-box `sudo -v` does not authenticate sudo on Johnny.

No new Johnny command. `STEP13-IRQ-DONE` is still not a result.

## Do not

- Treat this draft as applied.
- Run the paste before Claude reviews it.
- Stop or mask `irqbalance` by hand as a shortcut.
- Pin `eno2np1` onto CPUs 1–4 while it is admin-down.
- Change RSS, RPS, or XPS in the same sitting.
