# Step 12 — signed UKI research (draft)

**Historical.** Superseded 2026-11-05 by the inventory closeout: `docs/sessions/2026-11-05-step12-signed-uki-inventory.md` and handoff rev 83. AJ ran the main paste from tip `058fc60`. The "not applied" lines below are the draft, written before that run. Option D is still not applied. The inventory is done.

Drafted 2026-11-05 ~13:05 CT. Handoff rev 82 at draft time. No command from the draft session had run yet on Johnny, on rock-box, or on ABLETON_BOX.

## Status

Step 12 is **drafted, not applied**. Runbook: `docs/tool-install/step-12-signed-uki.md`. Lab TPM unlock stays option A (PCR 7 only). Fleet option D (signed UKI + signed PCR 11 policy) is research only. AJ has not run the inventory. CIS L1 totals unchanged: **225 PASS, 18 PASS (manual), 31 N/A, 0 FAIL** (274/274). Steps 6, 8, 9, and 11 stay applied. IRQ affinity stays later.

The main paste is unprivileged. It refuses root (`STOP-root`), any host other than `johnny` (`STOP-host`), any kernel other than `7.0.0-42-generic` (`STOP-kernel`), and any user other than `aj` (`STOP-user`). It does not install a package, run `ukify` or `dracut`, sign a PE, import a MOK, or call `systemd-cryptenroll`. `STEP12-RESEARCH-DONE` means the inventory finished. It does not mean option D is in use.

The optional sudo paste is not required for that line. It runs only after `STEP12-RESEARCH-DONE`. It reads LUKS slot types with `cryptsetup luksDump` and, when the unprivileged read failed, PCR banks 7, 11, and 14. It does not enroll or wipe. A second run prints `STOP-slots-already`.

rock-box is the SSH client. ABLETON_BOX is Windows and is not a UKI target.

## Check on this draft

The two Johnny pastes were extracted and `bash -n` exited 0 on each. A scan of those pastes found no `apt-get`, `apt install`, `systemd-cryptenroll`, `wipe-slot`, `update-grub`, `update-initramfs`, or `mokutil --import`. The names `systemd-ukify` and `dracut` appear only as `dpkg-query` and `apt-cache policy` arguments, and `/usr/bin/ukify` is an existence check.

On a host whose short name is not `johnny`, the main paste printed `STOP-host` and exited 1 before creating a log directory. The same file under `sudo -n` printed `STOP-root` and exited 1.

A copy of the main paste with the host, kernel, and user gates opened, writing under `/tmp`, printed `STEP12-RESEARCH-DONE`. Installed `systemd` kept its version. Packages that `dpkg-query` reports as `not-installed` with exit 0 printed `NOT-INSTALLED`, not a blank version. `apt-cache policy` per name printed `POLICY systemd-ukify NONE` and `NOTE-no-candidate`. That host is not Johnny.

A copy of the optional paste with those gates opened printed `STOP-no-probe` when the summary lacked `STEP12-RESEARCH-DONE`, then `STOP-no-luks-dev` when the LUKS uuid link was missing. With the link pointed at a 64-byte file that is not a LUKS volume, it printed `NOTE-luks-dump-failed`, then `SLOTS-DONE`. A second run printed `STOP-slots-already`. `chown` to `aj` printed `NOTE-chown-failed` on that copy because the copy was not root and the account `aj` is not this machine. The Johnny paste is `sudo bash`, so that `chown` runs as root.

A PCR line fixture `7 : 0xB6D0F97F…F3FF` parsed to the handoff baseline with the `0x` prefix removed. A crypttab fixture whose third field was a key path printed `NOTE-crypttab-keyfile` and the name and UUID only. The `none` third field printed as `none`.

That check did not read Johnny's TPM and did not write a LUKS slot.

## Nits (same draft, before any closeout)

Claude's four non-blocking nits on `058fc60` are in the runbook. AJ was cleared to run the main paste from that tip. If his transcript is from `058fc60`, that is the paste that ran. These nits do not replace a `STEP12-RESEARCH-DONE` he already printed.

1. The raw `luksDump` goes to a mode 600 file under `/root` and is removed before `SLOTS-DONE`. The audit directory keeps `luks-slots.txt` and `luks-dump.err`. Collect's `scp` does not include `/root`.
2. Both `find` calls use `-iname`, so `BOOTX64.EFI` is listed and matches the allow-list.
3. The ESP is treated as root-only. `NOTE-efi-errors` or `NOTE-efi-unreadable` from the main paste is expected. The optional sudo paste is the EFI listing.
4. `NOTE-crypttab-keyfile` uses `${1:-}` and `${2:-}`, so a short `crypttab` line does not trip `set -u` before `STEP12-RESEARCH-DONE`.

## Nit check

`bash -n` on both pastes exited 0. The unmodified main paste printed `STOP-host` and, under `sudo -n`, `STOP-root`. A one-field line under `set -u` printed `NOTE-crypttab-keyfile` and continued. A fixture file `BOOTX64.EFI` was listed by `find -iname` and missed by `find -name`. The allow-list matched `BOOTX64.EFI`.

The optional copy, gates opened, run with `sudo -n` so `mktemp` under `/root` could run, printed `NOTE-luks-dump-failed` and `SLOTS-DONE` for a file that is not a LUKS volume. The audit directory contained `luks-dump.err` and no raw header. No `/root/step12-luks-dump.*` file remained. A second run printed `STOP-slots-already`. `NOTE-chown-failed` is this VM: it has no account `aj`. The Johnny paste is `sudo bash` on a host where `aj` exists.

That check did not read Johnny's TPM and did not write a LUKS slot.

## Do not

- Run `ukify`, `dracut --uefi`, or `systemd-cryptenroll` from this draft.
- Treat `STEP12-RESEARCH-DONE` as an apply.
- Unhold `shim-signed` or `secureboot-db`.
- Switch the lab off option A.
