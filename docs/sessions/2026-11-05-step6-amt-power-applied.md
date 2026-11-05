# Step 6 — AMT power retest (applied)

Applied 2026-11-05 America/Chicago. Handoff rev 76 (nits on rev 75). No secret values are in this note. AJ ran the power clicks and the DMT rotate on rock-box. This closeout does not change Johnny's live config, the MeshCommander tree, or DMT `config.yml`.

MeshCommander cleanup was still open in this note. Handoff rev 77 records it **closed** (AJ, 2026-11-05): computer deleted, node killed, Chrome site data for `http://127.0.0.1:3000` cleared. The step 8 draft did not watch that desktop.

## Result

MeshCommander `meshcommander@0.9.5-a` on rock-box, Digest/TLS, to AMT `192.168.51.10`. The admin password was accepted. The value is not recorded.

Soft-reset (CIM PowerState 14) is **don't-use** on Johnny. The UI said "Power action completed" and the OS did not reboot. That is a no-op. Johnny has no LMS/ISM. Do not install an agent to make Soft-reset work.

Reset (10) **PASS, boot time only**. Boot moved to 2026-11-05 15:59 UTC (~09:59 CT). There was no `OK-*` post-check on that boot. AJ was not on Remote Desktop for the whole Reset. Later, MeshCommander Remote Desktop showed `johnny login:` and no LUKS prompt. **[Inference]** that is the TPM unlock path. It is not a PCR read. A Computer header of None while Connected is cosmetic.

Power cycle (5) **PASS**. Boot 2026-11-05 16:07 UTC (~10:07 CT). This is the boot with the post-check: `HOST johnny`, `OK-eno3`, `OK-eno1-up`, `OK-promisc`, `OK-eno2`, `TUNING-ACTIVE active`, `TUNING-ENABLED enabled`. Ableton `PROBE-514` printed `NOTE-514`. That is not a rollback.

Pass criterion is boot time, uptime, or KVM. MeshCommander `powerActionResponse4` treats HTTP 200 as success and ignores `ReturnValue`, so the UI string is not the pass.

Local patch, not in git, under `~/meshcommander-step6` (package directory `node_modules/meshcommander`, where the paste runs `node meshcommander.js`): `public/default.htm` prefers `qop` `auth` over `auth-int`. `interceptor.js` `GetAuthArgs` is quote-aware. The rollback `rm -rf /home/aj/meshcommander-step6` destroys that patch with the install.

MeshCommander cleanup was not confirmed when this note was written. Handoff rev 77 records it closed (AJ, 2026-11-05): computer deleted, node killed, Chrome site data for `http://127.0.0.1:3000` cleared. The step 8 draft did not watch that desktop.

DMT: AJ ran `docs/tool-install/step-6-dmt-rotate.sh`, confirmed the password rotate, then `--shred-backup`. Output `SHRED-OK 1`. `jwtKey` and `adminPassword` were rotated. The backups were shredded. The password-manager copy is the runbook step before shred. **[Assumption]** that copy was made. A Devices-page login proof was not stated and is not recorded. **[Assumption]** `ADMIN-USER` is still `standalone`. `config.yml` is what the console reads. It is not the operator's only copy. Do not echo the values. Do not run the rotate again on this config.

`rpc-go` on Johnny was not the power client. Step 11 was not reverted.

## Unchanged

CIS L1 totals stay **225 PASS, 18 PASS (manual), 31 N/A, 0 FAIL** (274/274). As of handoff rev 77, step 8 thermal soak is drafted and not applied. Next open after that run: 9 EDAC, 12 signed UKI (option D), and IRQ affinity later. MeshCommander cleanup is closed in that revision, not a new numbered step.

## Record

- Runbook: `docs/tool-install/step-6-amt-power.md` (rev 3)
- Rotate script (unchanged by this closeout): `docs/tool-install/step-6-dmt-rotate.sh`
- Draft, now historical: `docs/sessions/2026-11-05-step6-amt-power-draft.md`
- Session CSV: `docs/sessions/Johnny_Step6_Session_Log_2026-11-05.csv`
