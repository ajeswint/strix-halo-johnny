# Step 6 — AMT power retest (applied)

Applied 2026-11-05 America/Chicago. Handoff rev 75. No secret values are in this note. AJ ran the power clicks and the DMT rotate on rock-box. This closeout does not change Johnny's live config, the MeshCommander tree, or DMT `config.yml`.

## Result

MeshCommander `meshcommander@0.9.5-a` on rock-box, Digest/TLS, to AMT `192.168.51.10`. The admin password was accepted. The value is not recorded.

Soft-reset (CIM PowerState 14) is **don't-use** on Johnny. The UI said "Power action completed" and the OS did not reboot. That is a no-op. Johnny has no LMS/ISM. Do not install an agent to make Soft-reset work.

Reset (10) **PASS**. Boot moved to 2026-11-05 15:59 UTC (~09:59 CT). AJ was not on Remote Desktop for the whole Reset. Later, MeshCommander Remote Desktop showed `johnny login:`. That is the TPM unlock path, not a LUKS passphrase prompt. A Computer header of None while Connected is cosmetic.

Power cycle (5) **PASS**. Boot 2026-11-05 16:07 UTC (~10:07 CT). Post-check: `HOST johnny`, `OK-eno3`, `OK-eno1-up`, `OK-promisc`, `OK-eno2`, `TUNING-ACTIVE active`, `TUNING-ENABLED enabled`. Ableton `PROBE-514` printed `NOTE-514`. That is not a rollback.

Pass criterion is boot time, uptime, or KVM. MeshCommander `powerActionResponse4` treats HTTP 200 as success and ignores `ReturnValue`, so the UI string is not the pass.

A local patch on the rock-box install under `~/meshcommander-step6` preferred `qop=auth`. That patch is a local deviation. It is not committed.

DMT: AJ ran `docs/tool-install/step-6-dmt-rotate.sh`, confirmed the password rotate, then `--shred-backup`. Output `SHRED-OK 1`. `jwtKey` and `adminPassword` were rotated. The backups were shredded. Do not echo the values. Do not run the rotate again on this config.

`rpc-go` on Johnny was not the power client. Step 11 was not reverted.

## Unchanged

CIS L1 totals stay **225 PASS, 18 PASS (manual), 31 N/A, 0 FAIL** (274/274). Next open items stay 8 thermal soak, 9 EDAC, 12 signed UKI (option D), and IRQ affinity later.

## Record

- Runbook: `docs/tool-install/step-6-amt-power.md` (rev 2, applied)
- Rotate script (unchanged by this closeout): `docs/tool-install/step-6-dmt-rotate.sh`
- Draft, now historical: `docs/sessions/2026-11-05-step6-amt-power-draft.md`
- Session CSV: `docs/sessions/Johnny_Step6_Session_Log_2026-11-05.csv`
