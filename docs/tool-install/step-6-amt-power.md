# Step 6 — AMT power retest and DMT rotation (applied)

Rev 3, 2026-11-05 ~10:25 CT. Grok 4.7 wrote the draft (rev 1), the applied closeout (rev 2), and the review nits (rev 3). AJ ran the power clicks and the rotate on rock-box. This file does not store passwords. No secret value is recorded below.

## Applied (2026-11-05 America/Chicago)

AJ ran this from rock-box. MeshCommander `meshcommander@0.9.5-a`, Digest/TLS, to AMT `192.168.51.10`. The admin password was accepted. Nothing in this closeout changes Johnny's live config, the MeshCommander install, or DMT `config.yml`.

**Soft-reset is don't-use on Johnny.** CIM PowerState 14. The UI said "Power action completed" and the OS did not reboot. That is a no-op. Johnny has no LMS/ISM, and this step does not install an agent. Do not choose Soft-reset again.

**Reset (10) PASS, boot time only.** Boot moved to 2026-11-05 15:59 UTC (~09:59 CT). There was no `OK-*` post-check on that boot. AJ was not on Remote Desktop for the whole Reset. Later, MeshCommander Remote Desktop showed `johnny login:` and no LUKS prompt. **[Inference]** that is the TPM unlock path. It is not a PCR read. A Computer header of None while the session says Connected is cosmetic.

**Power cycle (5) PASS.** Boot 2026-11-05 16:07 UTC (~10:07 CT). This is the boot with the post-check: `HOST johnny`, `OK-eno3`, `OK-eno1-up`, `OK-promisc`, `OK-eno2`, `TUNING-ACTIVE active`, `TUNING-ENABLED enabled`. Ableton `PROBE-514` printed `NOTE-514`. That note is not a rollback and does not authorize an edit on Johnny or on ABLETON_BOX.

**Pass criterion.** Boot time, uptime, or KVM. Not the MeshCommander success string. In this package, `powerActionResponse4` treats HTTP 200 as success and ignores `ReturnValue`.

**Local deviation, not in git.** Under `~/meshcommander-step6`, in the package directory the paste starts (`node_modules/meshcommander`): `public/default.htm` prefers `qop` `auth` over `auth-int`, and `interceptor.js` `GetAuthArgs` is quote-aware. That patch is not committed. The rollback `rm -rf /home/aj/meshcommander-step6` deletes it with the install.

**MeshCommander cleanup is closed** (handoff rev 77, AJ 2026-11-05). The computer was deleted, the node was killed, and Chrome site data for `http://127.0.0.1:3000` was cleared. The step 8 draft did not watch that desktop. It is not a follow-up.

**DMT rotate done.** AJ ran `docs/tool-install/step-6-dmt-rotate.sh`, said the password rotate was confirmed, then `--shred-backup`. The script printed `SHRED-OK 1`. `jwtKey` and `adminPassword` were rotated. The backups were shredded. The password-manager copy is the runbook step before shred. **[Assumption]** that copy was made. A Devices-page login proof was not stated in chat and is not recorded. **[Assumption]** `ADMIN-USER` is still `standalone`. The values are not in this repo and are not repeated here.

CIS L1 totals are unchanged: **225 PASS, 18 PASS (manual), 31 N/A, 0 FAIL** (274/274). As of handoff rev 77, step 8 thermal soak is drafted and not applied. Next open after that run: 9 EDAC, 12 signed UKI, and IRQ affinity later.

The sections below are the rev 1 runbook, with the power-action choice corrected to the result above. AJ decides any later rerun.

Platform owns `oob-console` (`docs/agent-team.md`). This runbook does not change Johnny, the CRS309, or AMT provisioning. The 2026-11-05 apply did not either.

## What this step does

1. From rock-box, confirm AMT is still the host already recorded: ping `192.168.51.10`, TCP 16993 and 16995 open, TLS certificate fingerprint unchanged.
2. Install MeshCommander `meshcommander@0.9.5-a` on rock-box and use it as the remote power and KVM client. Bind it to `127.0.0.1` only.
3. Watch the console, then send **Reset** (10) or **Power cycle** (5). **Soft-reset** (14) is don't-use on Johnny: the 2026-11-05 run completed in the UI and did not reboot the OS. Power down is not the test.
4. After the OS is back, read-only checks from rock-box: SSH to Johnny, `eno3` still `192.168.50.152/24`, capture port flags, `eno2np1` down, `johnny-capture-tuning.service` still active and enabled, Ableton TCP 514 probe.
5. Before any reuse of Intel DMT Console, rotate `auth.jwtKey` and `auth.adminPassword` in the rock-box config. The script prints lengths, not values.

## What this step does not do

- No GRUB, BIOS, MEBx, PCR 7, or AMT re-provision. No switch or isolation change. No new address on Johnny.
- No sudo on Johnny. No `apt` on Johnny. Do not run `docs/tool-install/step-11-revert.sh`. Step 11 stays applied.
- Does not start DMT until the rotation below has printed `ROTATE-OK`. DMT's Power Off / Soft Reset / Ctrl+Alt+Del buttons are the ones that failed in the bench test. They are not the retest.
- Does not run `rpc` / `rpc-go`. See below.
- Does not print, commit, or echo the AMT admin password, the MEBx password, the DMT admin password, `jwtKey`, or the LUKS passphrase.

## Why MeshCommander, and why not rpc-go

The bench failure (2026-10-29, Intel DMT Console v1.47.0 on rock-box) was: KVM worked, and Power Off / Soft Reset / Ctrl+Alt+Del printed "Device did not respond", while AMT stayed reachable. The handoff sent the retest to MeshCommander or `rpc-go`. Those are not the same kind of tool.

`rpc-go` v2.52.8 is the file `~/rpc/rpc` on Johnny only. sha256 `52953302c12e8679b77ac58342340f3b21b30970200d04f1200818538dbf5269`. It talks to AMT through HECI/MEI on the managed host. Upstream describes that binary as local activation, configuration, deactivation, and status (`amtinfo`, `activate`, `configure`, `deactivate`, `version`, `diagnostics`). There is no power subcommand in that command list. The release tag is [v2.52.8](https://github.com/device-management-toolkit/rpc-go/releases/tag/v2.52.8). The command list cited here is current upstream [CLAUDE.md](https://github.com/device-management-toolkit/rpc-go/blob/main/CLAUDE.md), not a `--help` captured from Johnny. **[Assumption]** the Johnny binary matches that shape. This draft did not execute it.

Bare `rpc` or `rpc --help` on rock-box, or without elevation on a machine that is not the AMT host, fails `HECIDriverNotDetected`. It is not a remote WS-MAN client from rock-box to `192.168.51.10`. This runbook has no `rpc` command, and no `-h` / `-u` power flags, because those flags are not how this binary works. An on-Johnny HECI power path is out of scope. Do not sudo `~/rpc/rpc` to "see if power works."

Power-action numbers in the Device Management Toolkit docs (2 power on, 5 power cycle, 8 power down, 10 reset, 14 soft reset, and the rest) are the console / MPS REST model. They are not flags on `rpc`. MeshCommander's own dialog uses those same numbers behind labels. AJ clicks the label. Nobody types the number.

MeshCommander is the remote tool. npm package `meshcommander@0.9.5-a`, description "MeshCommander web server", Apache-2.0, integrity `sha512-RneCQXwu1Nuqu69+EPHIpDkrOcMcWaacM4T8Jibk0MkcquxF2iILX5bB6joCuNHHVr1I+9fPlYQoCjN1K22deg==` ([registry](https://registry.npmjs.org/meshcommander/0.9.5-a)). The package readme (`readme.txt` in that tarball) says:

- Default listen address is `127.0.0.1`. `--any` binds every interface. This step does not pass `--any`.
- Default port is 3000. `--port` changes it. This step does not pass `--port`.
- This edition does not check the Intel AMT TLS certificate.

The UI in `public/default.htm` of that same package:

- Add Computer → Auth / Security `Digest / TLS` uses TCP 16993 (and redirection 16995). `Digest / None` uses 16992, which is closed on this AMT. Hostname `192.168.51.10` with no scheme and no port. A colon in the hostname field replaces the default port (`portsFromHost`).
- Power Actions, when the OS is on and the AMT version is greater than 9 (ME 19 is): **Reset** (10), **Power cycle** (5), **Power down** (8), and also **Soft-reset** (14), **Soft-off** (12), Sleep, Hibernate. **Reset to BIOS** is a different row. Do not click it.
- The button labeled Restart on the screen-recording controls is not a power action. Ctrl-Alt-Del in the desktop view sends keys (`sendCAD`). That is the DMT failure mode, not this test.

Intel's note on the MeshCommander repo says support was discontinued. This step still uses `meshcommander@0.9.5-a` because it is a remote TLS client that runs on rock-box. Do not install MeshCentral or MeshCmd instead. MeshCmd's `amtpower` would put the AMT password on a command line. Do not.

**[Assumption]** rock-box already has `node`, `npm`, `python3`, and `openssl`, and Node can speak TLS 1.2 to ME 19. Paperclip on rock-box has used npm. If `node` or `npm` is missing, stop. Do not `apt-get install` Node in this step. If the UI times out immediately, stop and record `node --version`. Do not add a TLS 1.0 flag and do not switch to Digest / None.

## Prerequisites

- rock-box is the machine with `192.168.51.2/24` on the AMT out-of-band NIC (`enp11s0` when that address was recorded). Johnny `eno3` cannot reach AMT. The 2026-10-30 negative test stays as recorded. Do not put a `192.168.51.0/24` address on Johnny.
- Checkout that contains this file, at `/home/aj/Projects/strix-halo-johnny` on rock-box. **[Assumption]** that is still the rock-box checkout from `docs/agent-team.md` and from step 11. If `docs/tool-install/step-6-dmt-rotate.sh` is not there, stop. Do not clone somewhere else in this step.
- Two SSH sessions from rock-box to Johnny, open before the reset:

```bash
# rock-box, two terminals. Both drop when the OS reboots. That drop is expected if KVM then shows the boot.
ssh aj@192.168.50.152
```

- LUKS recovery passphrase at hand, not in the repo and not in the transcript. This step does not change PCR 7. **[Assumption]** TPM unlock still works. If KVM shows the passphrase prompt, type the recovery passphrase there. Do not edit GRUB or BIOS.
- AMT admin password, typed only into the MeshCommander password box. Username in that box stays `admin` (the dialog default). The MEBx password is a different secret in the handoff. Do not try a list of usernames.
- DMT stays stopped until the rotation section. Do not double-click Johnny KVM. Do not open `https://localhost:8181/`.

## Read-only checks (rock-box)

Stop if ping fails, either TCP check fails, the fingerprint hex differs, or DMT port 8181 is open. If 8181 is open, that is the DMT console: close the Johnny KVM terminal (Ctrl-C). Do not use it for power. Re-run this block. The hex must be `8C:D6:65:E9:E5:0C:49:00:65:D3:D9:D3:13:5B:66:97:5C:E3:89:4F:F5:04:48:B0:75:BC:44:5C:47:35:3D:0A`. OpenSSL may print `sha256` or `SHA256` before `Fingerprint=`. Anything else after the equals sign is a stop. Do not type the AMT password.

```bash
# rock-box, read-only
ping -c 3 -W 1 192.168.51.10
python3 -c 'import socket; s=socket.create_connection(("192.168.51.10",16993),5); s.close(); print("TCP-16993-OK")'
python3 -c 'import socket; s=socket.create_connection(("192.168.51.10",16995),5); s.close(); print("TCP-16995-OK")'
echo | openssl s_client -connect 192.168.51.10:16993 -servername 192.168.51.10 2>/dev/null | openssl x509 -noout -fingerprint -sha256
python3 - <<'PY'
def listening(port):
    needle = "%04X" % port
    for name in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(name, encoding="utf-8")
        except FileNotFoundError:
            continue
        for i, line in enumerate(lines):
            if i == 0:
                continue
            parts = line.split()
            if len(parts) < 4:
                continue
            if parts[3] == "0A" and parts[1].rsplit(":", 1)[-1].upper() == needle:
                return True
    return False
print("DMT-8181-OPEN" if listening(8181) else "DMT-8181-CLOSED")
PY
```

`DMT-8181-CLOSED` is required before the install paste and again before the rotate paste.

Baseline on Johnny, still before any power click. Run it again after SSH returns. Same block both times.

```bash
# rock-box, read-only on Johnny. No sudo.
ssh -o ConnectTimeout=8 aj@192.168.50.152 'bash -s' <<'EOF'
echo "HOST $(hostname)"
addr=$(ip -4 -br addr show eno3)
printf 'ENO3 %s\n' "$addr"
eno1=$(ip -br link show eno1np0)
printf 'ENO1 %s\n' "$eno1"
eno2=$(ip -br link show eno2np1)
printf 'ENO2 %s\n' "$eno2"
case "$eno1" in
  *" UP "*) echo OK-eno1-up ;;
  *) echo STOP-eno1-up ;;
esac
case "$eno1" in
  *PROMISC*NOARP*|*NOARP*PROMISC*) echo OK-promisc ;;
  *) echo STOP-promisc ;;
esac
case "$addr" in
  *192.168.50.152/24*) echo OK-eno3 ;;
  *) echo STOP-eno3 ;;
esac
case "$eno2" in
  *" UP "*) echo STOP-eno2 ;;
  *" DOWN "*) echo OK-eno2 ;;
  *) echo STOP-eno2 ;;
esac
echo "TUNING-ACTIVE $(systemctl is-active johnny-capture-tuning.service || true)"
echo "TUNING-ENABLED $(systemctl is-enabled johnny-capture-tuning.service || true)"
if timeout 5 bash -c 'echo >/dev/tcp/192.168.50.211/514'; then
  echo PROBE-514-OK
else
  echo NOTE-514
fi
EOF
```

Before the reset, expect `OK-eno1-up`, `OK-promisc`, `OK-eno3`, `OK-eno2`, `TUNING-ACTIVE active`, `TUNING-ENABLED enabled`. `PROBE-514-OK` was still true on 2026-11-04. `NOTE-514` before the reset is a note, not a reason to power-cycle. Do not change ABLETON_BOX from this step unless that probe failed and AJ chooses to look. The look is read-only:

```powershell
# ABLETON_BOX, only if the probe printed NOTE-514. Read-only. Do not stop the task.
Get-ScheduledTask JohnnySyslogCollector | Select-Object State -ExpandProperty Triggers
Get-NetTCPConnection -LocalPort 514 -State Listen
```

## Paste — MeshCommander on rock-box

One block. No sudo. It installs into `/home/aj/meshcommander-step6` (not the git repo) and then replaces the shell with the server. Leave that terminal open. Ctrl-C stops it. It does not pass `--any` or `--port`. A second rock-box terminal is for SSH and the post-check.

Expected lines before the server takes the terminal: `ADDR-OK`, `INTEGRITY-OK`, `PORT-3000-FREE`, then `MeshCommander running on http://127.0.0.1:3000`. Open that URL in Chrome on rock-box. Not `https`. Not a LAN address of rock-box.

```bash
# rock-box bash. No sudo. Does not SSH to Johnny.
set -euo pipefail
if [[ "$(id -u)" -eq 0 ]]; then echo STOP-root; exit 1; fi
hn=$(hostname)
hn_lc=${hn,,}
case "$hn_lc" in johnny|johnny.*) echo "STOP-host $hn"; exit 1;; esac
if ! command -v ip >/dev/null 2>&1; then echo STOP-no-ip; exit 1; fi
if ! ip -4 -o addr show | grep -q 'inet 192.168.51.2/'; then echo STOP-not-rock-box; exit 1; fi
echo "HOST $hn"
echo ADDR-OK
if ! command -v node >/dev/null 2>&1; then echo STOP-no-node; exit 1; fi
if ! command -v npm >/dev/null 2>&1; then echo STOP-no-npm; exit 1; fi
if ! command -v python3 >/dev/null 2>&1; then echo STOP-no-python3; exit 1; fi
echo "NODE $(node --version)"
echo "NPM $(npm --version)"
install_dir=/home/aj/meshcommander-step6
if [[ -e "$install_dir" ]]; then echo STOP-exists; exit 1; fi
mkdir -m 0700 "$install_dir"
cd "$install_dir"
npm install --ignore-scripts --no-audit --no-fund --save-exact meshcommander@0.9.5-a
node <<'JS'
const fs = require("fs");
if (!fs.existsSync("package-lock.json")) {
  console.error("STOP-no-lock");
  process.exit(1);
}
const pkg = JSON.parse(fs.readFileSync("node_modules/meshcommander/package.json", "utf8"));
if (pkg.version !== "0.9.5-a") {
  console.error("STOP-version");
  process.exit(1);
}
const lock = JSON.parse(fs.readFileSync("package-lock.json", "utf8"));
const want = "sha512-RneCQXwu1Nuqu69+EPHIpDkrOcMcWaacM4T8Jibk0MkcquxF2iILX5bB6joCuNHHVr1I+9fPlYQoCjN1K22deg==";
let got = null;
if (lock.packages && lock.packages["node_modules/meshcommander"]) {
  got = lock.packages["node_modules/meshcommander"].integrity || null;
} else if (lock.dependencies && lock.dependencies.meshcommander) {
  got = lock.dependencies.meshcommander.integrity || null;
}
if (got !== want) {
  console.error("STOP-integrity");
  process.exit(1);
}
console.log("MESHCOMMANDER " + pkg.version);
console.log("INTEGRITY-OK");
JS
python3 - <<'PY'
port = 3000
needle = "%04X" % port
for name in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        lines = open(name, encoding="utf-8")
    except FileNotFoundError:
        continue
    for i, line in enumerate(lines):
        if i == 0:
            continue
        parts = line.split()
        if len(parts) < 4:
            continue
        if parts[3] == "0A" and parts[1].rsplit(":", 1)[-1].upper() == needle:
            raise SystemExit("STOP-port-3000")
print("PORT-3000-FREE")
PY
cd /home/aj/meshcommander-step6/node_modules/meshcommander
exec node meshcommander.js
```

`STOP-exists` means this directory is already there. Do not delete it from inside the paste. If a previous run already printed `INTEGRITY-OK`, start the same server again with no extra flags:

```bash
# rock-box. Same bind as the package default: 127.0.0.1 port 3000. No --any. No --port.
cd /home/aj/meshcommander-step6/node_modules/meshcommander
exec node meshcommander.js
```

`STOP-integrity` or `STOP-version` means do not start the server by hand. The rollback section removes a bad install.

npm talks to `registry.npmjs.org`. That is the install. The lockfile integrity line is the pin.

## Connect, watch, Reset or Power cycle

In Chrome at `http://127.0.0.1:3000/`:

1. Add Computer. Friendly name can be `Johnny AMT`. Hostname is `192.168.51.10` only. Auth / Security is `Digest / TLS`. Username stays `admin`. Type the AMT admin password into the password box. OK.
2. Connect on that row. MeshCommander does not check the certificate. The openssl line above is the check. If the fingerprint was wrong, do not do this step.
3. Open Remote Desktop. Confirm the headless Ubuntu console is visible (HDMI dummy is already in; step 5). If the picture is black, stop. Do not power-cycle to chase video.
4. Power Actions. Do not choose **Soft-reset** (CIM PowerState 14). On 2026-11-05 the UI said "Power action completed" and the OS stayed up. Johnny has no LMS/ISM. Do not install an agent to make Soft-reset work. Choose **Reset** (10) or **Power cycle** (5). Both passed on 2026-11-05. Do not choose Power down, Soft-off, Sleep, Hibernate, Reset to BIOS, Power up to BIOS, or Secure Erase.
5. The dialog warns that the desktop session may drop. The UI string is not the pass. `powerActionResponse4` treats HTTP 200 as success and ignores `ReturnValue`. Open Remote Desktop again, or read the boot time after SSH returns. A passphrase prompt is the LUKS recovery passphrase. A login prompt with no passphrase prompt is **[Inference]** of the TPM unlock path (the expected path). It is not a PCR read. A Computer header of None while Connected is cosmetic.
6. The two SSH sessions drop when the OS goes down. That drop, a newer boot time, or the login prompt on KVM is the reboot. A session that stays up is not a reboot, even if the dialog says the action completed.

If Reset or Power cycle leaves the OS up, stop. Record the UI text and whether `uptime` or the boot timestamp moved. Do not Power down. Do not run `rpc`. Do not re-provision AMT. Do not retry Soft-reset.

If the only useful row is **Power up**, the box is off. Choose Power up only as recovery, confirm SSH with the post-check, and stop. Record `RECOVERY-POWER-UP`. Do not follow it with another reset in the same pass.

## Post-boot verify

From a second rock-box terminal, after KVM shows the login prompt, run the same Johnny read-only block as the baseline.

Pass: `HOST johnny`, `OK-eno1-up`, `OK-promisc`, `OK-eno3`, `OK-eno2`, `TUNING-ACTIVE active`, `TUNING-ENABLED enabled`. `PROBE-514-OK` is the Ableton note. `NOTE-514` does not roll back the reboot and does not authorize an edit on Johnny or on ABLETON_BOX. The optional ABLETON_BOX commands are above.

A `STOP-*` line on capture or on `eno3` is a stop. Do not run the step 11 revert unless AJ asks in a later step. This reboot is not a capture rollback.

Then stop MeshCommander. In the UI, Disconnect, then Delete that computer. Do not use Save. Ctrl-C the terminal that printed `MeshCommander running`. The package readme says the computer list, including the password, stays in the browser cache. In Chrome open `chrome://settings/content/all`, remove `http://127.0.0.1:3000`, and do not paste anything from that page into chat.

**Not confirmed on 2026-11-05.** The power tests and the DMT shred were recorded. Disconnect, Delete, Ctrl-C, and clearing `http://127.0.0.1:3000` site data were not. That cleanup stays open on rock-box.

## Paste — rotate DMT secrets (rock-box)

**Done 2026-11-05.** AJ ran the script, confirmed the password rotate, then `--shred-backup` (`SHRED-OK 1`). Do not run it again on this config. A second run would rotate the new `jwtKey` and admin password and would find no step-6 backup to shred. Chat records that confirmation and the shred. It does not record a Devices-page visit. The password-manager copy below is the runbook step. **[Assumption]** AJ made that copy before shred. The steps below are the record of what that paste does.

Do this before any DMT reuse only when the exposed key is still the live key. If the session stops before a needed rotation, leave DMT stopped.

The script is safer than a hand edit: it refuses to print the new password or `jwtKey`, it rewrites only those two lines, and it keeps a mode `0600` backup. It expects the current lengths (admin password 16, `jwtKey` 44). It does not change `adminUsername`. **[Assumption]** that username is still `standalone`, which is what the 2026-11-03 reconstruction recorded. The script prints `ADMIN-USER` and the name. It does not print the password.

`8181` must be closed. The script exits `STOP-console-up` if it is not. It also exits `STOP-not-rock-box` unless `192.168.51.2/` is on the machine, and `STOP-host` if the hostname is `johnny`.

```bash
# rock-box. No sudo. Does not print the new password or jwtKey.
bash /home/aj/Projects/strix-halo-johnny/docs/tool-install/step-6-dmt-rotate.sh
```

Pass is `ROTATE-OK`, `ADMIN-PASSWORD-LEN 16`, `JWTKEY-LEN 44`, `CONFIG-MODE 600`, plus `BACKUP` and `ROLLBACK` paths under `/home/aj/dmt-console/dist/linux/config/`. Those files stay on rock-box. Do not copy them into the repo. Do not `cat`, `grep`, or `echo` the config or the backup.

Open the config in an editor on rock-box. Copy `auth.adminPassword` into a password manager. Close the editor. Do not paste the value into chat, git, or a transcript. `auth.jwtKey` does not need to be copied anywhere. It only has to stop being the key from the 2026-10-29 transcript.

Login proof, still on rock-box, after the password is stored. On 2026-11-05 a Devices-page visit was not recorded. AJ confirmed the rotate, then shredded. Do not backfill that page:

1. Start DMT the usual way: double-click Johnny KVM (`~/Desktop/Johnny-KVM.desktop` → `~/bin/johnny-kvm`) or run `~/bin/johnny-kvm`. It listens on 8181 on all interfaces. That is unchanged and is why it does not stay up.
2. Chrome, `https://localhost:8181/`, past the self-signed console certificate warning. Log in with `ADMIN-USER` from the script output and the new password from the editor. Do not use the old password.
3. Devices shows Johnny Mgmt. That is the proof. Do not open KVM. Do not click Power, Reset, or Ctrl+Alt+Del in DMT.
4. Ctrl-C the launcher so 8181 closes.

Then delete the backups, which still hold the exposed `jwtKey` until they are shredded:

```bash
# rock-box. The runbook order is: password-manager copy, then login proof, then this.
# 2026-11-05: AJ confirmed the rotate, then this printed SHRED-OK 1.
# A Devices-page visit was not recorded. Do not add one after the fact.
bash /home/aj/Projects/strix-halo-johnny/docs/tool-install/step-6-dmt-rotate.sh --shred-backup
```

`SHRED-OK` and a count. The live `config.yml` stays. It is what the console reads. The operator copy of the new admin password is the password manager. Rollback is gone after this command. On 2026-11-05 the shred followed AJ's "password rotate confirmed". Devices-page login proof is not recorded.

## Success

Recorded 2026-11-05. These are the lines that closed the step. A later rerun uses the same list.

- MeshCommander connected with Digest / TLS to `192.168.51.10`. The admin password was accepted in the UI. The password is not written down here.
- Soft-reset (14) is not a pass. On Johnny it completed in the UI and did not reboot the OS. Use Reset (10) or Power cycle (5).
- The pass is a moved boot time, a dropped SSH session that comes back, or KVM showing POST or `johnny login:`. The MeshCommander "Power action completed" string is not the pass (`powerActionResponse4` / HTTP 200 / `ReturnValue` ignored).
- Reset PASS, boot time only: 2026-11-05 15:59 UTC (~09:59 CT). No `OK-*` post-check on that boot. Later KVM: `johnny login:` and no LUKS prompt. **[Inference]** TPM unlock path. Not a PCR read.
- Power cycle PASS: boot 2026-11-05 16:07 UTC (~10:07 CT). This boot has the post-check: `HOST johnny`, `OK-eno3`, `OK-eno1-up`, `OK-promisc`, `OK-eno2`, `TUNING-ACTIVE active`, `TUNING-ENABLED enabled`. `eno3` still `192.168.50.152/24`.
- `PROBE-514` printed `NOTE-514` on that Power cycle post-check. That is a note, not a rollback.
- DMT: AJ confirmed the rotate, then `--shred-backup` printed `SHRED-OK 1`. `jwtKey` and `adminPassword` rotated. Backups shredded. Password-manager copy is the runbook step. **[Assumption]** it was made. Devices-page login proof is not recorded. **[Assumption]** `ADMIN-USER` is still `standalone`. No value in git.
- MeshCommander cleanup (Disconnect, Delete, Ctrl-C, clear `http://127.0.0.1:3000`) was not part of the step 6 pass. Handoff rev 77 records it closed (AJ, 2026-11-05): computer deleted, node killed, Chrome site data cleared. The step 8 draft did not watch that desktop.
- No secret in the transcript. Step 11 was not reverted. No BIOS, GRUB, MEBx, or AMT provisioning change. No Johnny live config change in the closeout.

There is no single `STEP6-DONE` line. The closeout is the Reset boot time, the Power cycle boot time and its `OK-*` lines, and `SHRED-OK 1`. MeshCommander cleanup is closed in handoff rev 77.

## Stop

- Fingerprint mismatch, or ping / 16993 / 16995 failure. Do not type the AMT password.
- `STOP-not-rock-box`, `STOP-no-ip`, `STOP-host`, `STOP-root`, `STOP-no-node`, `STOP-no-npm`, `STOP-no-python3`. Do not install Node here and do not add the `192.168.51.2/24` address from this step. That address is already supposed to be persistent (`/etc/netplan/60-johnny-amt-oob.yaml` on rock-box). If it is missing, stop.
- `STOP-integrity`, `STOP-version`, `STOP-no-lock`, `STOP-port-3000`. Do not pass `--any` to dodge a busy port.
- KVM picture black, or Reset and Power cycle both leave the OS up. Record the text. Stop. Soft-reset leaving the OS up is the known no-op, not a reason to Power down. Do not run `rpc`.
- KVM shows a LUKS passphrase prompt. Type the recovery passphrase. After boot, stop and record that TPM unlock did not happen. Do not change PCR 7 in this step.
- Post-check `STOP-eno3` or `STOP-promisc` or `STOP-eno2` or tuning not active. Stop. Do not revert step 11 from this runbook.
- Rotate script prints `STOP-console-up`, `STOP-length`, `STOP-count-adminPassword`, `STOP-count-jwtKey`, `STOP-git`, or `STOP-symlink`. The live file is unchanged on those count, git, and symlink stops. Do not hand-edit the YAML in the terminal.

A failed power test does not by itself roll back DMT, because DMT was not the client. Leave DMT stopped, or rotate before the next open. Do not start DMT on the old `jwtKey`.

## Rollback

MeshCommander is only on rock-box. Removing it does not change AMT or Johnny. Ctrl-C first. Then, only if this directory is the step 6 install. This also deletes the uncommitted `qop=auth` patch (`public/default.htm` and `interceptor.js`):

```bash
# rock-box
rm -rf /home/aj/meshcommander-step6
```

If a power action left the box off, MeshCommander **Power up**, then the post-check, then stop. That is recovery, not a pass.

DMT, console stopped (`DMT-8181-CLOSED`), before `--shred-backup`:

```bash
# rock-box. Puts the pre-rotation file back, including the exposed jwtKey. Leave DMT stopped after this.
bash /home/aj/Projects/strix-halo-johnny/docs/tool-install/step-6-dmt-rotate.sh --restore
```

`RESTORE-OK` means the backup bytes are the live file again. Do not start the console on that restored key. A later rotation has to happen before any reuse. `--restore` refuses a pointer that is not a same-directory `config.yml.bak-step6-` name, and it refuses to run while 8181 is open.

Do not restore by `cat` or by copying the backup into the repo. Do not run `/root/step11-revert.sh`.

## Applied record

The 2026-11-05 rock-box run is the apply. Rev 1 of this file did not claim a session. Rev 2 recorded the run. Rev 3 corrects the nits: Reset PASS is boot time only; the `OK-*` lines are the Power cycle post-check; TPM unlock is an inference from `johnny login:` with no LUKS prompt; AJ confirmed the DMT rotate and then shredded (`SHRED-OK 1`); Devices-page login proof is not recorded; the password-manager copy is the runbook step (**[Assumption]** it was made); MeshCommander cleanup was still open at rev 3 and is closed in handoff rev 77; the `qop=auth` patch is `public/default.htm` plus quote-aware `GetAuthArgs` in `interceptor.js`, and `rm -rf` destroys it. The self-test of the rotate script (`bash docs/tool-install/step-6-dmt-rotate.sh --self-test`) prints `SELF-TEST-OK` on a temp directory. It is not the rock-box paste.
