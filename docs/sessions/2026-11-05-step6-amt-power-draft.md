# Step 6 — AMT power retest (draft, historical)

**Historical.** Superseded 2026-11-05 by the applied closeout: `docs/sessions/2026-11-05-step6-amt-power-applied.md` and handoff rev 75. The text below is the rev 74 draft, written before AJ ran the step. Do not treat "not applied" in this file as current state.

Not applied at the time of this draft. Current state at draft time was `docs/os-handoff.md` rev 74. Nothing had been run yet on Johnny, rock-box, or ABLETON_BOX.

## Where it stands

Step 11 is applied (`STEP11-DONE` 2026-11-05 ~08:26 CT). CIS L1 totals are unchanged: 225 PASS, 18 PASS (manual), 31 N/A, 0 FAIL (274/274). This session only drafts the next open handoff item, step 6.

The bench result is unchanged: Intel DMT Console v1.47.0 on rock-box could do KVM, and Power Off / Soft Reset / Ctrl+Alt+Del printed "Device did not respond" while AMT stayed reachable. The handoff named MeshCommander or `rpc-go` for the retest. Those are not interchangeable.

`rpc-go` v2.52.8 at `~/rpc/rpc` on Johnny (sha256 `52953302c12e8679b77ac58342340f3b21b30970200d04f1200818538dbf5269`) is a local HECI/MEI client. Upstream's command list is `amtinfo`, `activate`, `configure`, `deactivate`, `version`, `diagnostics` ([rpc-go CLAUDE.md](https://github.com/device-management-toolkit/rpc-go/blob/main/CLAUDE.md); release [v2.52.8](https://github.com/device-management-toolkit/rpc-go/releases/tag/v2.52.8)). No power subcommand is documented there. Bare `rpc` on rock-box fails `HECIDriverNotDetected`. It is not a remote client for `192.168.51.10`. The on-Johnny HECI power path is out of scope. **[Assumption]** the Johnny binary matches that upstream shape. This draft did not execute it.

The remote tool in the runbook is npm `meshcommander@0.9.5-a` (integrity `sha512-RneCQXwu1Nuqu69+EPHIpDkrOcMcWaacM4T8Jibk0MkcquxF2iILX5bB6joCuNHHVr1I+9fPlYQoCjN1K22deg==`). Its readme binds `127.0.0.1:3000` unless `--any` is passed, and it does not check the AMT certificate. The UI labels in that package are **Soft-reset** and **Reset**. The runbook uses Soft-reset, then Reset if needed, and does not use Power down as the test. The openssl fingerprint check is the gate before the AMT password is typed into the UI.

DMT `jwtKey` and admin password stay unrotated until AJ runs the rotate script. The script refuses to print them.

## Record

- Runbook: `docs/tool-install/step-6-amt-power.md`
- Rotate / restore / shred: `docs/tool-install/step-6-dmt-rotate.sh`
- Self-test, this draft only: `bash docs/tool-install/step-6-dmt-rotate.sh --self-test` → `SELF-TEST-OK`
- On a machine that is not rock-box, the script with no arguments prints `STOP-no-ip` or `STOP-not-rock-box` and does not open the DMT config
- Session CSV: `docs/sessions/Johnny_Step6_Session_Log_2026-11-05.csv`

## Do not

These bullets were the draft's rules, before the 2026-11-05 apply. Step 6 is applied in handoff rev 75. Do not start DMT on the pre-rotation `jwtKey` (that key was rotated and the backups shredded). Do not run `~/rpc/rpc` as the power test. Do not undo step 11. Do not run the rotate script a second time.
