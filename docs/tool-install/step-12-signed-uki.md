# Step 12 — signed UKI research (draft, not applied)

Drafted 2026-11-05 ~13:05 CT. Grok 4.7 wrote it. Claude reviews and does not edit. Nothing in this step has been run on Johnny, on rock-box, or on ABLETON_BOX.

Platform owns the boot chain (`docs/agent-team.md` §4). This file is research plus one read-only inventory. It does not switch the lab off option A.

## Machines

| Machine | What this step does |
|---|---|
| Johnny (`johnny`, `192.168.50.152`) | The only host the inventory paste may run on. Ubuntu Server 26.04.1 (`resolute`), kernel `7.0.0-42-generic`. Lab TPM unlock stays PCR 7 only. |
| rock-box (`aj-rock-box`) | SSH client only. Do not run the paste on rock-box. |
| ABLETON_BOX | Windows helper (`docs/hosts/ableton_box.md`). No UKI, no TPM enroll, no Secure Boot change. Do not run this paste there. |

From rock-box, the SSH command is `ssh -o ServerAliveInterval=30 aj@192.168.50.152`. That line is not part of the Johnny paste.

## Goal

Record what option D is, what Ubuntu 26.04 actually ships for it, and what would have to be true before a fleet autoinstall uses it. If AJ chooses to run the paste, collect a read-only inventory on Johnny and print `STEP12-RESEARCH-DONE`.

Lab policy is unchanged: option A, PCR 7 only. The residual in `docs/os-handoff.md` stays accepted for the lab. Fleet still wants option D. This draft does not promote the lab to the fleet target.

## What this step does not do

- It does not enroll, wipe, or re-enroll a LUKS slot. It does not call `systemd-cryptenroll`.
- It does not install `systemd-ukify`, `systemd-boot`, `sbsigntool`, `pesign`, or any other package. It does not run `apt-get` or `apt install`.
- It does not run `ukify`, `dracut --uefi`, or `update-initramfs`. It does not generate a UKI.
- It does not sign a PE binary and does not create a Secure Boot key or a PCR signing key.
- It does not import a MOK, change `db` / `dbx` / `KEK` / `PK`, or change Secure Boot state.
- It does not edit GRUB, `/etc/default/grub.d/johnny.cfg`, `crypttab`, shim holds, or the kernel command line.
- It does not reboot, power-cycle, or run `/root/step11-revert.sh`.
- It does not draft IRQ affinity.
- It does not run on rock-box or on ABLETON_BOX.

## Options, as already decided

The handoff records the choice. This step does not reopen it.

| Option | What it binds | Status |
|---|---|---|
| A | TPM unlock to PCR 7 only. Slot 0 stays the recovery passphrase. | Chosen for the lab. Accepted residual: `/boot` is plaintext and the initrd is unsigned and unmeasured in PCR 7, so a physical attacker who edits the initrd, or boots other media from the boot menu, can receive the key. No GRUB password yet (CIS 1.4.1): a kernel command line such as `init=` at the GRUB menu does not touch PCR 7. That path is understood and untested. |
| B | A PIN in addition to the TPM. | Rejected. |
| C | PCR 7 and PCR 9. PCR 9 moves when the kernel or initrd changes, so every update re-enrolls. | Rejected. |
| D | A signed UKI, plus a signed PCR 11 policy, so a kernel update can be signed ahead of time instead of re-enrolling the TPM on every update. | Fleet target. 26.04 support was unverified. This file is that research. Not applied. |

Cite: `docs/os-handoff.md`, Known gaps, "PCR-7-only binding (option A, chosen)." The same residual is `docs/compliance/risk-register.md`, "PCR 7 binding."

Live facts this research does not re-decide: Ubuntu 26.04.1 (`resolute`); hostname `johnny`; kernel `7.0.0-42-generic` only; Secure Boot enabled; kernel lockdown active; PK is MINISFORUM PK; `db` is MS UEFI CA 2011, MS UEFI CA 2023, Option ROM UEFI CA 2023, Windows UEFI CA 2023, Windows PCA 2011, and MINISFORUM OWN CA; `dbx` 20260707; LUKS slot 0 passphrase, slot 1 TPM2 PCR 7; PCR 7 baseline `B6D0F97FA80D8614711B20726D7FB7B00D77D52F24C3C0251630F925BA07F3FF`; holds on `shim-signed` and `secureboot-db`; `unattended-upgrades` security-only, no auto reboot; `pcie_aspm=off` in `/etc/default/grub.d/johnny.cfg`. CIS L1 totals stay **225 PASS, 18 PASS (manual), 31 N/A, 0 FAIL** (274/274). Steps 6, 8, 9, and 11 stay applied.

## What option D is

Two different signatures. They are not the same key.

1. **Secure Boot signature on the UKI.** A UKI is one PE binary. It holds the kernel, the initrd, and the command line. The firmware or shim verifies that one file. Editing the initrd inside it breaks the signature, so the machine does not boot that file. The resolute `ukify` man page is [ukify(1)](https://manpages.ubuntu.com/manpages/resolute/man1/ukify.1.html). The section layout is [systemd-stub(7)](https://manpages.ubuntu.com/manpages/resolute/man7/systemd-stub.7.html) and [UAPI.5](https://uapi-group.org/specifications/specs/unified_kernel_image/).
2. **PCR policy signature.** `systemd-stub` measures UKI sections into PCR 11. `ukify` can ask `systemd-measure` to pre-calculate that PCR 11 value, sign it, and store the signature in the UKI (`.pcrsig`, with the public key in `.pcrpkey`). `systemd-cryptenroll` can bind a LUKS slot to that public key. A later UKI signed by the same PCR key unseals without a new enroll. The resolute pages are [systemd-measure(1)](https://manpages.ubuntu.com/manpages/resolute/man1/systemd-measure.1.html) and [systemd-cryptenroll(1)](https://manpages.ubuntu.com/manpages/resolute/man1/systemd-cryptenroll.1.html).

Option A does neither. The installed boot path is shim, then GRUB, then a separate `vmlinuz` and a separate `/boot/initrd.img-7.0.0-42-generic`. PCR 7 is the Secure Boot policy registers, not the initrd.

## Ubuntu 26.04 support

Searched 2026-11-05. The inventory paste is what Johnny's own apt and filesystem say. The citations below are the archive and the man pages, not a claim that a package is installed.

### Packages

| Package | Where it is documented | Role |
|---|---|---|
| `systemd-ukify` | [packages.ubuntu.com resolute](https://packages.ubuntu.com/resolute/systemd-ukify), universe. Launchpad lists `259.9-0ubuntu0.1` in resolute updates and `259.5-0ubuntu3.4` in security ([Launchpad](https://launchpad.net/ubuntu/resolute/+package/systemd-ukify)). | Ships `ukify`. Depends on `python3`, `python3-pefile`, `python3-zstandard`. Recommends `python3-cryptography`, `sbsigntool` or `pesign`, `systemd-boot-efi`, `systemd-repart` (which ships `systemd-sbsign`). |
| `systemd` | Handoff SBOM: `259.9-0ubuntu0.1`, already installed. | `systemd-cryptenroll` and `/usr/lib/systemd/systemd-measure` are part of systemd. The measure man page names that path. `systemd-ukify` is a separate binary package. |
| `systemd-boot`, `systemd-boot-efi`, `systemd-boot-tools` | [package search](https://packages.ubuntu.com/systemd-boot). Resolute-updates `259.9-0ubuntu0.1`, universe. | `systemd-boot-efi` on resolute-updates amd64 ships `/usr/lib/systemd/boot/efi/linuxx64.efi.stub`, `addonx64.efi.stub`, and `systemd-bootx64.efi` ([file list](https://packages.ubuntu.com/resolute-updates/amd64/systemd-boot-efi/filelist)). |
| `systemd-boot-efi-signed` | The resolute `systemd-boot` dependency line says this package is **not available**, and the alternative is the unsigned `systemd-boot-efi` ([systemd-boot in resolute](https://packages.ubuntu.com/resolute/systemd-boot)). | There is no archive-signed systemd-boot binary to put next to shim. |
| `sbsigntool` | [source package in resolute](https://packages.ubuntu.com/en/source/resolute/sbsigntool), `0.9.4-3.1ubuntu9`. | `ukify` defaults `--signtool=sbsign` ([ukify(1)](https://manpages.ubuntu.com/manpages/resolute/man1/ukify.1.html)). |
| `dracut` | Handoff SBOM: `110-11ubuntu0.1`. [dracut(8)](https://manpages.ubuntu.com/manpages/resolute/man8/dracut.8.html), [dracut.conf(5)](https://manpages.ubuntu.com/manpages/resolute/man5/dracut.conf.5.html). | `--uefi` builds a UKI. `uefi=` defaults to no. `--ukify` is the default when `--uefi` is on. `uefi_secureboot_cert` and `uefi_secureboot_key` want `sbsign`. |

**[Inference]** A later install on Johnny should match the installed systemd `259.9-0ubuntu0.1`, not the older security-pocket `259.5-0ubuntu3.4`, because `systemd-boot` depends on an equal `systemd` version. The paste records the candidate apt sees and prints `NOTE-ukify-version-skew` when the `systemd-ukify` candidate differs from the installed `systemd` version. It does not install either one.

Universe is where `systemd-ukify` is published. Whether Johnny's apt lists have universe enabled is not assumed. `NOTE-no-candidate` from the paste is the answer.

### The default install is not a UKI

Ubuntu's own note on systemd UKIs: the initrd is inside the signed image, so it cannot be regenerated on the machine the way Ubuntu packages expect. That is why the arm64 stub work did not adopt a full UKI ([stubble spec](https://discourse.ubuntu.com/t/spec-stubble-a-secure-boot-friendly-device-tree-loading-efi-stub/66278)). The same post says Ubuntu Core and TPM FDE are the places Ubuntu already uses a systemd UKI.

Desktop "hardware-backed" encryption is a different product. It wants a UKI and a TPM ([hardware-backed disk encryption](https://ubuntu.com/desktop/docs/en/26.04/explanation/hardware-backed-disk-encryption/), [requirements](https://ubuntu.com/desktop/docs/en/latest/reference/hardware-backed-disk-encryption-requirements/)). The security overview says TPM FDE is supported on Ubuntu Core and Ubuntu Desktop, and that the UKI holds the kernel and the initramfs ([Full disk encryption](https://documentation.ubuntu.com/security/security-features/storage/encryption-full-disk/)). Snapd 2.74.1 is what delivers that TPM FDE on resolute classic systems, using kernel and gadget snaps ([snapd 2.74.1](https://forum.snapcraft.io/t/snapd-2-74-1-release-update/50694)). This repo does not use snaps. Fleet option D does not mean "turn on the desktop installer checkbox" and it does not mean installing snapd.

Johnny today rebuilds a separate initrd with `update-initramfs` (dracut's wrapper, handoff) and keeps `pcie_aspm=off` in a GRUB drop-in. **[Inference]** A stock kernel upgrade refreshes `/boot/vmlinuz-*` and `/boot/initrd.img-*` and GRUB. It does not, by itself, build or sign a UKI. `dracut.conf(5)` defaults `uefi=` to no. The paste looks for EFI files instead of assuming the ESP is empty of UKIs.

## Secure Boot, MOK, and the vendor db

Johnny's `db` trusts Microsoft and Minisforum certificates. It does not contain a key AJ controls. Ubuntu's stock kernel boots because shim (Microsoft-signed, package `shim-signed`, held) verifies Canonical's signature on GRUB and on the kernel. A UKI built on the machine is a new PE. Wrapping the already-signed `vmlinuz` into that PE covers Canonical's signature with new bytes, so shim will not accept the UKI on Canonical's kernel signature.

`ukify` can sign the finished PE with `--secureboot-private-key` and `--secureboot-certificate` ([ukify(1)](https://manpages.ubuntu.com/manpages/resolute/man1/ukify.1.html)). Something in the boot chain still has to trust that certificate:

- Enrolling it in firmware `db` changes the Secure Boot policy. PCR 7 changes. The lab's PCR 7 slot would stop unsealing until a passphrase boot and a re-enroll. This step does not enroll anything.
- Enrolling it as a MOK lets the current shim verify the UKI without a firmware `db` write. Shim's TPM notes: MokList is extended into PCR 14, and a certificate that actually verifies a loaded binary (including MokListRT) is extended into PCR 7. SBAT and MokSBState also go to PCR 7 ([shim README.tpm](https://github.com/rhboot/shim/blob/main/README.tpm)). The handoff already says a MOK change can change PCR 7. That operational warning stands. **[Assumption]** `shim-signed` `1.59+15.8-0ubuntu2` follows that README's split. The paste does not dump the TPM event log and does not import a MOK.

`systemd-bootx64.efi` from `systemd-boot-efi` is unsigned in this archive (`systemd-boot-efi-signed` is not published). Putting it in the boot chain has the same trust problem as the UKI. Shim can chainload one MOK-signed UKI directly. Whether fleet uses that, or shim plus a locally signed systemd-boot, is an open question below. This step does not change `Boot0000`.

With Secure Boot on, `systemd-stub` ignores a command line passed from outside the UKI when `.cmdline` is present. An override that the stub does accept is measured into PCR 12, not PCR 11 ([systemd-stub(7)](https://manpages.ubuntu.com/manpages/resolute/man7/systemd-stub.7.html)). `pcie_aspm=off` has to be inside `.cmdline` on a UKI boot. The GRUB drop-in does not apply to a UKI that GRUB never loads.

Addons (`.addon.efi` next to the UKI, or under `/loader/addons/`) can add a command line or an extra initrd. Secure Boot must verify the addon (firmware `db`, shim's vendor db, or MOK). The stub measures addons into PCR 12. The file name is not covered by the PE signature, so a rename can change order ([same systemd-stub page](https://manpages.ubuntu.com/manpages/resolute/man7/systemd-stub.7.html)). **[Inference]** A policy that signs only PCR 11 still unseals if a trusted addon appends an initrd, because PCR 11 stays the signed UKI and PCR 12 moves. That is a residual for the later design, not a lab change. The open questions ask whether PCR 12 is in scope. This paste does not create an addon directory and does not delete one.

## PCR 11 and the signed policy

`systemd-stub` measures the UKI's kernel, os-release, cmdline, initrd, and the other listed sections into PCR 11. It does not measure `.pcrsig` into PCR 11, because that section is the signature of the measurement ([systemd-stub(7)](https://manpages.ubuntu.com/manpages/resolute/man7/systemd-stub.7.html)). The firmware also measures the whole PE into PCR 4. The kernel measures initrds it receives into PCR 9. Option C, which bound PCR 9, stays rejected. This research does not add PCR 9.

`systemd-measure` starts PCR 11 from zero and replays the stub's measurement. The resolute man page still says the tool is experimental. Default phases are `enter-initrd`, then that plus `leave-initrd`, `sysinit`, and `ready` ([systemd-measure(1)](https://manpages.ubuntu.com/manpages/resolute/man1/systemd-measure.1.html)). LUKS unlock happens in the initrd, so a signature that omitted `enter-initrd` would not help the boot that needs the key. `ukify` calls `systemd-measure` when `--pcr-private-key` is set. The man page says to use `ukify` rather than calling `systemd-measure` by hand to build an image. This step does not call either for a build. The paste may run `systemd-measure status` if the binary is already installed. `status` only reads PCR 11.

`systemd-cryptenroll` on resolute:

- `--tpm2-pcrs=` binds to the current numeric PCR values. If the option is omitted, the man page says the default is no literal PCRs at all ([systemd-cryptenroll(1)](https://manpages.ubuntu.com/manpages/resolute/man1/systemd-cryptenroll.1.html)). Johnny's slot 1 was enrolled with an explicit PCR 7. A later command that forgot `--tpm2-pcrs=7` would drop that literal bind. This paste does not enroll, so it cannot make that mistake. A future apply must not copy a short example from the man page onto the root volume.
- `--tpm2-public-key=` with `--tpm2-public-key-pcrs=` binds to any PCR values the key has signed. If the PCR list is omitted, the default is PCR 11.
- `--tpm2-signature=` is a safety check against the PCR values on the machine at enroll time. If the signature does not match, cryptenroll writes no slot. If no signature file is given, that check is skipped. On today's GRUB boot, PCR 11 is not a UKI prediction. **[Inference]** The safety check would refuse a UKI signature until the machine has actually booted that UKI. Skipping the check could write a slot that does not unseal. The recovery passphrase is the way back. This step does not try either path.
- The man page's general advice is a combination of PCRs 7, 11, and 14 when shim or MOK is used. PCR 14 is `shim-policy` (MOK list). That sentence is upstream advice inside the Ubuntu man page. It is not a decision for Johnny. See the open questions.

The man page documents `--tpm2-pcrs` and `--tpm2-public-key` as separate options. It does not show one command line that passes both. **[Inference]** They can be combined, because they configure different policy pieces, and a literal PCR 7 bind can sit next to a signed PCR 11 policy. A later step would prove that on a non-root volume. Not on Johnny's root, and not in this step.

Signed PCR policy does not remove slot 0. The handoff recovery passphrase stays the recovery path. An attacker who can get a passphrase typed into a prompt they control is outside what PCR 11 signs.

## Whether PCR 7 stays

Option D, as the handoff names it, is "signed UKI + signed PCR 11 policy." It does not say "drop PCR 7."

Keeping a literal PCR 7 bind next to the signed PCR 11 policy preserves today's behavior for `db` / `dbx` / `KEK` / `PK`, a shim CA change, and an SBAT bump: those still fall back to the passphrase, then need the existing re-enroll procedure. The signed PCR 11 policy is what closes the option A hole (edited initrd, or other boot media, with PCR 7 unchanged).

Dropping the literal PCR 7 bind means a `dbx` update would not, by itself, force a passphrase. The UKI still has to verify under Secure Boot, and PCR 11 still has to match a signature from the PCR key. The cryptenroll default, if `--tpm2-pcrs` is omitted, is that drop. That default is why a later apply has to say the PCR 7 choice in the command instead of relying on the tool default.

This draft does not choose. The lab stays PCR 7 only until AJ chooses otherwise in a later step.

## Pass

The main paste passes when it prints `STEP12-RESEARCH-DONE`. That line is printed only when all of these are true:

1. The shell is not root (`id -u` is not 0).
2. `hostname --short` is `johnny` and `uname -r` is `7.0.0-42-generic`.
3. The shell user is `aj`.
4. The inventory files were written under `/home/aj/cis-audit/step12-signed-uki/`.

These are recorded and do not withhold `STEP12-RESEARCH-DONE`:

- `PKG … NOT-INSTALLED` and `NOTE-no-candidate`. Expected for `systemd-ukify` until a later step installs it. This step does not install it.
- `NOTE-ukify-version-skew`. The apt candidate does not match the installed `systemd` version.
- `NOTE-hold-missing`. `shim-signed` or `secureboot-db` is not in `apt-mark showhold`. Bring it back. Do not unhold or re-hold from this step.
- `NOTE-pcr-unreadable` or `NOTE-no-tpm2-pcrread`. Reason to run the optional sudo paste. Not a failed inventory.
- `NOTE-pcr7-baseline`. PCR 7 sha256 matches the handoff baseline.
- `NOTE-pcr7-diff`. PCR 7 sha256 does not match the baseline. Bring the summary back. Do not re-enroll.
- `NOTE-pcr11-zero`. PCR 11 sha256 is all zeros. **[Inference]** that is what a boot that never ran `systemd-stub` looks like. It is not proof by itself, and it is not a cue to build a UKI.
- `NOTE-pcr11-nonzero`. Bring the summary back. Do not enroll.
- `NOTE-efi-extra`. An EFI file whose name is not `shimx64.efi`, `grubx64.efi`, `mmx64.efi`, `fbx64.efi`, or `BOOTX64.EFI`. Bring the path back. Do not delete it.
- `NOTE-efi-errors`. `find` wrote names and also wrote an error. The optional paste lists `/boot` again with sudo. Do not delete a file.
- `NOTE-crypttab-diff` or `NOTE-crypttab-keyfile`. The live `crypttab` is not the single expected line. A third field other than `none` or `-` is not printed.
- `NOTE-cmdline-no-aspm` or `NOTE-grub-no-aspm`. The recorded `pcie_aspm=off` setting was not found. Do not edit GRUB.
- `SLOTS-DONE` is not required for the pass. It only means the optional sudo paste finished.

## Logs

Directory on Johnny: `/home/aj/cis-audit/step12-signed-uki`. If that path already exists, the main paste renames it with a UTC timestamp and starts clean. `aj` can `scp` it. The main paste never calls sudo.

| File | Contents |
|---|---|
| `transcript.txt` | The terminal transcript |
| `summary.txt` | The lines to bring back |
| `packages.txt` | `dpkg-query` versions |
| `policy.txt` | `apt-cache policy` for the UKI-related packages |
| `holds.txt` | `apt-mark showhold` |
| `efi-files.txt` | EFI binaries found under `/boot/efi/EFI` and `/boot` |
| `pcr.txt` | `tpm2_pcrread` sha256 banks 7, 11, and 14, if the unprivileged read worked |
| `luks-slots.txt` | Only if the optional paste ran. Filtered header lines. No digest and no salt. |

Do not commit the raw files.

## Paste on Johnny

Not run. The block below is the whole unprivileged inventory. It does not prompt for a password.

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
if ! command -v timeout >/dev/null 2>&1; then
  printf '%s\n' STOP-no-timeout
  exit 1
fi

OUT=/home/aj/cis-audit/step12-signed-uki
if [ -e "$OUT" ]; then
  mv "$OUT" "/home/aj/cis-audit/step12-signed-uki.prev.$(date -u +%Y%m%dT%H%M%SZ)"
fi
mkdir -p /home/aj/cis-audit
mkdir -p "$OUT"

exec > >(tee -a "$OUT/transcript.txt") 2>&1

note() { printf '%s\n' "$*" | tee -a "$OUT/summary.txt"; }

note "HOST $h"
note "KERNEL $k"
note "DATE-UTC $(date -u +%Y-%m-%dT%H:%M:%SZ)"
note "EUID $(id -u)"
note "USER $(id -un)"
note "GROUPS $(id -nG | tr ' ' ',')"

if [ -r /sys/kernel/security/lockdown ]; then
  note "LOCKDOWN $(tr -d '\n' < /sys/kernel/security/lockdown)"
else
  note NOTE-no-lockdown
fi

cmd=$(tr -d '\n' < /proc/cmdline)
note "CMDLINE $cmd"
case "$cmd" in
  *pcie_aspm=off*) note NOTE-cmdline-aspm ;;
  *) note NOTE-cmdline-no-aspm ;;
esac

if [ -r /etc/default/grub.d/johnny.cfg ]; then
  if grep -q 'pcie_aspm=off' /etc/default/grub.d/johnny.cfg; then
    note NOTE-grub-aspm
  else
    note NOTE-grub-no-aspm
  fi
else
  note NOTE-grub-unreadable
fi

: > "$OUT/packages.txt"
sysd=
for p in systemd systemd-ukify systemd-boot systemd-boot-efi systemd-boot-efi-signed systemd-boot-tools systemd-repart sbsigntool pesign python3-pefile python3-zstandard python3-cryptography mokutil shim-signed secureboot-db grub-efi-amd64-signed grub-efi-amd64-bin tpm2-tools dracut dracut-core cryptsetup cryptsetup-bin; do
  st=$(dpkg-query -W -f '${db:Status-Status}' "$p" 2>/dev/null || true)
  if [ "$st" = installed ]; then
    ver=$(dpkg-query -W -f '${Version}' "$p" 2>/dev/null || true)
    note "PKG $p $ver"
    printf 'PKG %s %s\n' "$p" "$ver" >> "$OUT/packages.txt"
    if [ "$p" = systemd ]; then
      sysd=$ver
    fi
  else
    note "PKG $p NOT-INSTALLED"
    printf 'PKG %s NOT-INSTALLED\n' "$p" >> "$OUT/packages.txt"
  fi
done

: > "$OUT/policy.txt"
ukify_cand=
for p in systemd-ukify systemd-boot systemd-boot-efi systemd-boot-efi-signed sbsigntool pesign systemd-repart; do
  if ! timeout 15 apt-cache policy "$p" </dev/null >"$OUT/policy-one.txt" 2>"$OUT/policy-one.err"; then
    note "NOTE-policy-failed $p"
    continue
  fi
  cat "$OUT/policy-one.txt" >> "$OUT/policy.txt"
  cand=$(awk '/^[[:space:]]+Candidate:/ { print $2; exit }' "$OUT/policy-one.txt")
  if [ -z "${cand:-}" ] || [ "$cand" = "(none)" ]; then
    note "POLICY $p NONE"
    cand=
  else
    note "POLICY $p $cand"
  fi
  if [ "$p" = systemd-ukify ]; then
    ukify_cand=$cand
  fi
done
if [ -z "${ukify_cand:-}" ]; then
  note NOTE-no-candidate
elif [ -z "$sysd" ]; then
  note "NOTE-ukify-version-skew systemd=absent ukify=$ukify_cand"
elif [ "$ukify_cand" != "$sysd" ]; then
  note "NOTE-ukify-version-skew systemd=$sysd ukify=$ukify_cand"
else
  note NOTE-ukify-candidate-match
fi

apt-mark showhold </dev/null | sort >"$OUT/holds.txt" || true
note "HOLDS $(tr '\n' ',' < "$OUT/holds.txt" | sed 's/,$//')"
for hold in shim-signed secureboot-db; do
  if ! grep -qx "$hold" "$OUT/holds.txt"; then
    note "NOTE-hold-missing $hold"
  fi
done

for f in /usr/lib/systemd/systemd-measure /usr/lib/systemd/boot/efi/linuxx64.efi.stub /usr/lib/systemd/boot/efi/systemd-bootx64.efi /usr/bin/ukify; do
  if [ -e "$f" ]; then
    note "FILE present $f"
  else
    note "FILE absent $f"
  fi
done

if command -v mokutil >/dev/null 2>&1; then
  if timeout 15 mokutil --sb-state </dev/null >"$OUT/sb-state.txt" 2>"$OUT/sb-state.err"; then
    note "SB-STATE $(tr '\n' ' ' < "$OUT/sb-state.txt" | sed 's/[[:space:]]*$//')"
  else
    note NOTE-sb-state-failed
  fi
else
  note NOTE-no-mokutil
fi

if command -v bootctl >/dev/null 2>&1; then
  note BOOTCTL present
  if ! timeout 15 bootctl status --no-pager </dev/null >"$OUT/bootctl.txt" 2>"$OUT/bootctl.err"; then
    note NOTE-bootctl-failed
  else
    note BOOTCTL-STATUS-OK
  fi
else
  note NOTE-no-bootctl
fi

if command -v efibootmgr >/dev/null 2>&1; then
  if timeout 15 efibootmgr </dev/null >"$OUT/efibootmgr.txt" 2>"$OUT/efibootmgr.err"; then
    note EFIBOOTMGR-OK
    grep -E '^BootCurrent:|^BootOrder:|^Boot0000' "$OUT/efibootmgr.txt" | while IFS= read -r line; do note "EFI $line"; done || true
  else
    note NOTE-efibootmgr-failed
  fi
else
  note NOTE-no-efibootmgr
fi

: > "$OUT/efi-files.txt"
: > "$OUT/efi-files.err"
if [ -d /boot ]; then
  find_rc=0
  find /boot -maxdepth 5 \( -name '*.efi' -o -name '*.efi.signed' \) -printf '%p\n' </dev/null >"$OUT/efi-files.txt" 2>"$OUT/efi-files.err" || find_rc=$?
  if [ "$find_rc" -ne 0 ] && [ ! -s "$OUT/efi-files.txt" ]; then
    note NOTE-efi-unreadable
  elif [ -s "$OUT/efi-files.err" ]; then
    note NOTE-efi-errors
  fi
else
  note NOTE-efi-unreadable
fi
efi_n=$(wc -l < "$OUT/efi-files.txt" | tr -d '[:space:]')
note "EFI-FILES ${efi_n:-0}"
while IFS= read -r path; do
  [ -n "$path" ] || continue
  base=$(basename "$path")
  note "EFI-FILE $path"
  case "$base" in
    shimx64.efi|grubx64.efi|mmx64.efi|fbx64.efi|BOOTX64.EFI) ;;
    *) note "NOTE-efi-extra $path" ;;
  esac
done < "$OUT/efi-files.txt"

if [ -r /etc/crypttab ]; then
  : > "$OUT/crypttab-kept.txt"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|\#*) continue ;;
    esac
    printf '%s\n' "$line" >> "$OUT/crypttab-kept.txt"
  done < /etc/crypttab
  n=$(wc -l < "$OUT/crypttab-kept.txt" | tr -d '[:space:]')
  exp='dm_crypt-0 UUID=a6d02318-e79b-4a4c-bafa-0097695493db none luks,tpm2-device=auto'
  if [ "$n" = 1 ] && [ "$(cat "$OUT/crypttab-kept.txt")" = "$exp" ]; then
    note CRYPTTAB-MATCH
  else
    note NOTE-crypttab-diff
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      set -f
      set -- $line
      set +f
      keyfield=${3:-}
      case "$keyfield" in
        none|-)
          note "CRYPTTAB-LINE $line"
          ;;
        *)
          note "NOTE-crypttab-keyfile $1 $2"
          ;;
      esac
    done < "$OUT/crypttab-kept.txt"
  fi
else
  note NOTE-crypttab-unreadable
fi

if [ -x /usr/lib/systemd/systemd-measure ]; then
  note MEASURE-BIN present
  if timeout 15 /usr/lib/systemd/systemd-measure status --bank=sha256 --no-pager </dev/null >"$OUT/measure-status.txt" 2>"$OUT/measure-status.err"; then
    note MEASURE-STATUS-OK
  else
    note NOTE-measure-status
  fi
else
  note NOTE-no-systemd-measure
fi

parse_pcr() {
  awk -v i="$1" '
    {
      gsub(/:/, "", $1)
      if ($1 == i) {
        for (n = 1; n <= NF; n++) if ($n ~ /^0[xX][0-9A-Fa-f]+$/) { print $n; exit }
      }
    }
  ' "$OUT/pcr.txt" | tr '[:lower:]' '[:upper:]' | sed 's/^0X//'
}

if command -v tpm2_pcrread >/dev/null 2>&1; then
  if timeout 15 tpm2_pcrread sha256:7,11,14 </dev/null >"$OUT/pcr.txt" 2>"$OUT/pcr.err"; then
    note PCR-READ-OK
    v7=$(parse_pcr 7 || true)
    v11=$(parse_pcr 11 || true)
    v14=$(parse_pcr 14 || true)
    note "PCR-7 ${v7:-PARSE-FAIL}"
    note "PCR-11 ${v11:-PARSE-FAIL}"
    note "PCR-14 ${v14:-PARSE-FAIL}"
    base=B6D0F97FA80D8614711B20726D7FB7B00D77D52F24C3C0251630F925BA07F3FF
    if [ -z "${v7:-}" ]; then
      note NOTE-pcr-parse
    elif [ "$v7" = "$base" ]; then
      note NOTE-pcr7-baseline
    else
      note NOTE-pcr7-diff
    fi
    if [ -z "${v11:-}" ]; then
      note NOTE-pcr-parse
    else
      z=$(printf '%s' "$v11" | tr -d '0')
      if [ -z "$z" ]; then
        note NOTE-pcr11-zero
      else
        note NOTE-pcr11-nonzero
      fi
    fi
  else
    note NOTE-pcr-unreadable
  fi
else
  note NOTE-no-tpm2-pcrread
fi

note STEP12-RESEARCH-DONE
EOF
```

## Optional sudo paste on Johnny

Run this only after the main paste has printed `STEP12-RESEARCH-DONE`. It is not required for the pass. It reads PCR banks when the unprivileged read failed, lists EFI files when that listing failed, retries `efibootmgr` when that failed, and reads LUKS slot types. `sudo -v` is first so the password prompt happens before the script.

It does not call `systemd-cryptenroll`. It does not wipe a slot. It does not enroll. The filtered `luksDump` drops digest and salt lines.

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
if ! command -v timeout >/dev/null 2>&1; then
  printf '%s\n' STOP-no-timeout
  exit 1
fi
if ! id aj >/dev/null 2>&1; then
  printf '%s\n' STOP-no-aj
  exit 1
fi
OUT=/home/aj/cis-audit/step12-signed-uki
if [ ! -f "$OUT/summary.txt" ] || ! grep -qx 'STEP12-RESEARCH-DONE' "$OUT/summary.txt"; then
  printf '%s\n' STOP-no-probe
  exit 1
fi
if grep -qx 'SLOTS-DONE' "$OUT/summary.txt"; then
  printf '%s\n' STOP-slots-already
  exit 1
fi

link=/dev/disk/by-uuid/a6d02318-e79b-4a4c-bafa-0097695493db
if [ ! -e "$link" ]; then
  printf '%s\n' STOP-no-luks-dev
  exit 1
fi

exec > >(tee -a "$OUT/transcript.txt") 2>&1
note() { printf '%s\n' "$*" | tee -a "$OUT/summary.txt"; }

dev=$(readlink -f "$link")
note "LUKS-DEV $dev"
if cryptsetup luksDump --batch-mode "$dev" </dev/null >"$OUT/luks-dump.txt" 2>"$OUT/luks-dump.err"; then
  awk '
    length($0) > 200 { next }
    /^Version:/ { print }
    /^Keyslots:/ { print }
    /^Data segments:/ { print }
    /^Tokens:/ { print }
    /^[[:space:]]+[0-9]+:/ { print }
    /Priority:/ { print }
    /Cipher:/ { print }
    /Mode:/ { print }
    /systemd-tpm2/ { print }
    /tpm2-pcrs/ { print }
    /Keyslot:/ { print }
  ' "$OUT/luks-dump.txt" | tee "$OUT/luks-slots.txt" | while IFS= read -r line; do note "LUKS $line"; done || true
else
  note NOTE-luks-dump-failed
fi

parse_pcr() {
  awk -v i="$1" '
    {
      gsub(/:/, "", $1)
      if ($1 == i) {
        for (n = 1; n <= NF; n++) if ($n ~ /^0[xX][0-9A-Fa-f]+$/) { print $n; exit }
      }
    }
  ' "$2" | tr '[:lower:]' '[:upper:]' | sed 's/^0X//'
}

if grep -Eq '^(NOTE-pcr-unreadable|NOTE-no-tpm2-pcrread|NOTE-pcr-parse)$' "$OUT/summary.txt"; then
  if timeout 15 tpm2_pcrread sha256:7,11,14 </dev/null >"$OUT/pcr-sudo.txt" 2>"$OUT/pcr-sudo.err"; then
    note PCR-SUDO-OK
    v7=$(parse_pcr 7 "$OUT/pcr-sudo.txt" || true)
    v11=$(parse_pcr 11 "$OUT/pcr-sudo.txt" || true)
    v14=$(parse_pcr 14 "$OUT/pcr-sudo.txt" || true)
    note "PCR-7-SUDO ${v7:-PARSE-FAIL}"
    note "PCR-11-SUDO ${v11:-PARSE-FAIL}"
    note "PCR-14-SUDO ${v14:-PARSE-FAIL}"
    base=B6D0F97FA80D8614711B20726D7FB7B00D77D52F24C3C0251630F925BA07F3FF
    if [ "${v7:-}" = "$base" ]; then
      note NOTE-pcr7-baseline
    elif [ -n "${v7:-}" ]; then
      note NOTE-pcr7-diff
    else
      note NOTE-pcr-parse
    fi
    if [ -n "${v11:-}" ]; then
      z=$(printf '%s' "$v11" | tr -d '0')
      if [ -z "$z" ]; then
        note NOTE-pcr11-zero
      else
        note NOTE-pcr11-nonzero
      fi
    fi
  else
    note NOTE-pcr-sudo-failed
  fi
fi

if grep -Eq '^(NOTE-efi-unreadable|NOTE-efi-errors)$' "$OUT/summary.txt"; then
  if find /boot -maxdepth 5 \( -name '*.efi' -o -name '*.efi.signed' \) -printf '%p\n' </dev/null >"$OUT/efi-files-sudo.txt" 2>"$OUT/efi-files-sudo.err"; then
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      note "EFI-FILE-SUDO $path"
    done < "$OUT/efi-files-sudo.txt"
  else
    note NOTE-efi-sudo-failed
  fi
fi

if grep -qx 'NOTE-efibootmgr-failed' "$OUT/summary.txt"; then
  if timeout 15 efibootmgr </dev/null >"$OUT/efibootmgr-sudo.txt" 2>"$OUT/efibootmgr-sudo.err"; then
    grep -E '^BootCurrent:|^BootOrder:|^Boot0000' "$OUT/efibootmgr-sudo.txt" | while IFS= read -r line; do note "EFI-SUDO $line"; done || true
  else
    note NOTE-efibootmgr-sudo-failed
  fi
fi

note SLOTS-DONE
chown -R aj:aj "$OUT" || note NOTE-chown-failed
EOF
```

## Stop lines

| Line | Meaning |
|---|---|
| `STOP-root` | The main paste was started as root. Run it as `aj`. |
| `STOP-host` | The shell is not on `johnny`. Do not continue on rock-box or any other host. |
| `STOP-kernel` | `uname -r` is not `7.0.0-42-generic`. |
| `STOP-user` | The main paste is not running as `aj`. |
| `STOP-no-timeout` | `timeout` is missing, so the paste will not start a read it cannot bound. |
| `STOP-no-aj` | The optional paste cannot see account `aj`. |
| `STOP-no-probe` | The optional paste ran before `STEP12-RESEARCH-DONE`. |
| `STOP-slots-already` | `SLOTS-DONE` is already in the summary. Do not append a second sudo pass. |
| `STOP-no-luks-dev` | `/dev/disk/by-uuid/a6d02318-e79b-4a4c-bafa-0097695493db` is missing. Do not point `luksDump` at another disk. |
| `STEP12-RESEARCH-DONE` | The unprivileged inventory finished. |
| `SLOTS-DONE` | The optional sudo read finished. Not required for the pass. |
| `NOTE-chown-failed` | `SLOTS-DONE` was written, then `chown` to `aj` failed. Do not run the optional paste again. |

`NOTE-pcr7-diff` is a finding. It is not a cue to re-enroll. `NOTE-efi-extra` is a finding. It is not a cue to delete a boot file.

## Collect

On rock-box, after the paste returns:

```bash
mkdir -p /home/aj/johnny-step12
scp -r aj@192.168.50.152:/home/aj/cis-audit/step12-signed-uki /home/aj/johnny-step12/
```

Bring back `summary.txt`. Do not commit the raw directory. Do not treat `STEP12-RESEARCH-DONE` as an apply.

## Fleet implications

Option D is a fleet-autoinstall question. It is not a change to the lab image that is already enrolled.

Before an autoinstall image adopts it, all of the following have to be true:

1. The image build can install `systemd-ukify` at the same version as `systemd`, plus a signer (`sbsigntool` or `systemd-sbsign` from `systemd-repart`). Those packages are universe components in the citations above. The lab paste has to have shown the candidate, or the image build has to enable the component on purpose.
2. A key ceremony exists for two keys, kept off the ESP and out of git. One signs the UKI for Secure Boot (MOK or `db`). One signs PCR 11 predictions. The PCR private key is what lets a UKI unseal every disk that trusts the matching public key. A shared fleet key and a per-machine key are different risks. Not chosen here.
3. The UKI `.cmdline` contains the fleet command line, including `pcie_aspm=off` for this hardware class. A GRUB drop-in is not that command line.
4. The embedded initrd still carries the Johnny dracut policy that matters at boot: `tpm2-tss` present, `thunderbolt` omitted, `dyn-netconf` omitted. A UKI that was built from a generic initrd would boot a different early userspace.
5. Every kernel or initrd change rebuilds the UKI and signs it twice (Secure Boot, then the PCR prediction). The TPM slot is not re-enrolled when the same PCR key signs the new prediction. The stock `update-initramfs` plus GRUB path does not do this rebuild. An image hook has to. `shim-signed` and `secureboot-db` stay held until a planned console boot. A UKI signed by a new MOK does not require unholding those packages. Enrolling the MOK, or changing `db`, still moves PCR 7 and still needs the passphrase if a literal PCR 7 bind remains.
6. Slot 0 remains a recovery passphrase, tested before any TPM enroll. The cryptenroll safety check is used only after a boot of the UKI that is being enrolled, or the enroll is not done.
7. The boot entry that can unseal is the UKI path. A leftover GRUB entry that boots the separate unsigned initrd must not be able to satisfy the PCR 11 signature. Slot 0 would still open that path if someone types the passphrase. That is the recovery path, and it is also the remaining prompt risk.
8. Addon files and PCR 12 are decided (open question below) before the image creates `/loader/addons` or `*.efi.extra.d`.
9. The desktop snap TPM-FDE installer is not the image. No snaps.

`systemd-boot-efi-signed` being absent from resolute means the image cannot apt-install a signed systemd-boot. It signs its own UKI, and it signs systemd-boot only if the open question chooses that bootloader.

## Open questions

AJ decides these later. This draft does not pick.

1. Keep a literal PCR 7 bind beside the signed PCR 11 policy, or use the signed PCR 11 policy alone? The handoff's name for option D does not drop PCR 7. The cryptenroll default omits literal PCRs when `--tpm2-pcrs` is left off.
2. Also bind PCR 14 (shim MOK list), as the cryptenroll man page suggests when MOK is in use? Not chosen. Binding it means a MOK list change needs a re-enroll, which is the brittleness option D is trying to avoid for kernel updates.
3. One PCR signing key for the fleet, or one key per machine?
4. Where the Secure Boot private key and the PCR private key live. Not on the ESP. Not in this repo.
5. Boot chain: shim chainloads the UKI, or shim chainloads a locally signed systemd-boot which chainloads the UKI?
6. Does the old GRUB plus separate-initrd entry stay as a passphrase-only recovery path?
7. Is an addon / PCR 12 policy in scope before autoinstall, or is the rule "no addon directory"?
8. Whether to run the inventory paste on Johnny. The paste is ready. It has not been run.

IRQ affinity stays later. It is not one of these questions.

## Rollback

No Johnny config change. No package install. No key. No slot write. Ctrl-C leaves a partial directory and does not print `STEP12-RESEARCH-DONE`. There is no revert script. Do not run `/root/step11-revert.sh`. Do not unhold `shim-signed` or `secureboot-db`. Do not wipe the TPM slot.

## After the run

Not run. When AJ has run it, bring `summary.txt` back. `STEP12-RESEARCH-DONE` means the inventory finished. It does not mean option D is in use. The lab stays option A until a later step AJ chooses. CIS L1 totals stay **225 PASS, 18 PASS (manual), 31 N/A, 0 FAIL** (274/274). IRQ affinity stays later.
