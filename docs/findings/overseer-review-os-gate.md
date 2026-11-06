# Overseer review package: OS phase gate (README step 3)

Status: **DRAFT readiness package. AJ has not signed.** Written by the code-writer seat (Sonnet). Not an adversarial review: the adversarial-reviewer reads this next. Base tip `b9acdc4` (`claude/practical-ritchie-4c6vvf`, handoff rev 93). Branch `claude/overseer-review-os-gate`. Date 2026-11-06 UTC (2026-11-05 evening America/Chicago). Docs only: no sudo, no apt, no Johnny change, no Module 1 work, no architecture-logic decision.

AJ is the Overseer here (`docs/agent-team.md` §1 lists the Overseer as an external reviewer; this package gives AJ one place to sign). The decision lines are at the end and are blank.

## 1. Bottom line

The OS phase work is applied and recorded, with these exceptions the Overseer should weigh before closing it:

1. **Step 13f is live on Johnny and the repo says it is a draft.** Johnny's helper is the 13f blob. AJ ran `step-13f-helper-nits.sh` under sudo at 01:54:05Z (journal). The runbook, handoff rev 93 (helper row) and the 13f commit message still say "not applied, not reviewed". No `STEP13B-HELPER-NITS-FIXED` token or review verdict is in the repo. See §3, step 13f.
2. **Review evidence for steps 6–13 is not in git.** `docs/findings/` holds reviews for CIS batches 1–4, AIDE and apparmor-utils only. The step reviews live in PR threads (not readable from rock-box: `gh` is not installed) and in untracked `tools/relay/logs/` (PRs #2, #4, #6 only). Per-step review verdicts are **unknown** here, apart from the verdicts quoted in the repo (PR #11 `APPROVE-WITH-NITS` in its merge subject).
3. **The step 8 thermal result is not in the risk register.** Soak max 92 °C with `NOTE-throttled`. No limit was set and AJ has not accepted or rejected it as a risk.
4. **The risk register's PCR 7 entry is stale on the GRUB password.** It says there is no GRUB password yet (CIS 1.4.1). The CSV records 1.4.1 PASS from batch 10 (2026-11-04). The register is Governance's and AJ's text; I did not edit it.
5. **Agent-team doc drift** (§4 below): §6 still names Grok 4.7 as writer; §4 `etc/` row says "all 15 files"; capture units' owner glob does not match the real unit names.
6. Raw step logs stay on Johnny only (`/home/aj/cis-audit/`, `/root/`). Nothing in git proves the raw output; the repo holds summaries and hashes.

Nothing found here is a CIS failure or a live fault. Johnny read clean on 2026-11-06 02:54Z: no failed units, `johnny-capture-irq.service` `active`/`enabled`/`Result=success`, TxRx IRQs on CPUs `1 2 3 4 1 2 3 4 1 2 3 4`.

## 2. Evidence method and limits

Read-only SSH to Johnny as `aj` (key auth), 2026-11-06 ~02:54Z (journal host clock; boot 0 began 01:55:57Z). Commands: `sha256sum`, `stat`, `systemctl is-*`/`show`, `dpkg-query -W`, `apt-mark showhold`, `ip -d link show`, `networkctl list`, `ss -lntu`, `journalctl` (as `aj`), `free`, `/proc/meminfo`. Plus repo reads, the CSV, and local script counts for §8.

Not done, not possible as `aj`:
- `/root/*` logs and `/etc/netplan/00-installer-config.yaml` are unreadable (permission denied). The netplan hash `83a6b8be…` in the handoff was **not** re-read.
- `apt update` was not run; no package currency claim beyond `dpkg-query` of installed versions.
- No PCR, LUKS or TPM read (needs sudo). PCR 7 baseline is as recorded in the handoff (re-read 2026-11-05 by step 12, `NOTE-pcr7-baseline`).
- No traffic test on `eno1np0`. Link state only.
- My first multi-name `ip -br link show eno1np0 eno2np1 …` call failed (iproute2 takes one device); link state came from `networkctl list` and per-device `ip`.
- 26.04 specifics here are cited from the repo's earlier runbooks, not re-searched, except where a URL is given.

## 3. OS sequence checklist (README steps 1–3; handoff Next steps 6–13)

Legend: **DONE** = applied and recorded with a token or hash; **DONE-note** = done with an open note; **UNREC** = live state differs from the repo record.

| Step | State | Evidence (token, hash, path) | Overseer note |
|---|---|---|---|
| 1–5 lab, cabling, mirror, DHCP, HDMI/KVM | DONE | handoff Next steps 1–5; `docs/network-map.md`; KVM verified 2026-11-03 (AJ screenshot) | Physical cabling is the truth. 1G LAN by design. |
| 6 AMT power retest | DONE-note | `docs/tool-install/step-6-amt-power.md`; session `2026-11-05-step6-amt-power-applied.md`. Reset (10) PASS boot 2026-11-05 15:59Z; Power cycle (5) PASS boot 16:07Z with `OK-*` post-check | Soft-reset (14) is **don't-use**. Reset PASS is boot time only. Password-manager copy of the DMT admin password is **[Assumption]**. Local MeshCommander patch is not in git. |
| 7 tool install | DONE-note | `docs/tool-install/step-7-apt.md`; `STEP7-APT-DONE` 2026-11-04 ~23:12 CT; re-verified `STEP7-VERIFY-DONE` rev 93 | 17 tools. SBOM at tip: 16 of 17 match; `bind9-dnsutils` `…ubuntu0.5` (unattended upgrade 2026-11-05 06:48:18Z). `suricata` `disabled`/`inactive` (re-read 02:54Z); **who ran `disable --now` is not recorded**. Zeek is not installed (`dpkg-query` found no package); step 7 option C was core tools plus Suricata. |
| 8 thermal soak | DONE-note | `STEP8-DONE`; `docs/tool-install/step-8-thermal-soak.md`; raw `/home/aj/cis-audit/step8-thermal-soak/` on Johnny | Soak max CoreTmp/PkgTmp 92 °C, PkgWatt 121.06, CoreThr 4484, PKG_% 6.76. `NOTE-throttled`, `NOTE-throttle-sysfs-changed`. **No temperature limit; not in the risk register.** |
| 9 EDAC | DONE-note | `STEP9-DONE` 2026-11-05T18:15:40Z, `LOGS-DONE`; `docs/tool-install/step-9-edac.md` | `NOTE-no-mc`, `ECC-UNAVAILABLE` (non-ECC single-channel DIMM, per the 2026-10-28 record). IBECC not evaluated. ECC buy is parked, not decided. |
| 10 compliance baseline (CIS L1) | DONE | `docs/cis-26.04-l1-results.csv` (blob sha256 `4e34de669684eabf8961ccbd96c2150e1bd338c3147fdbd9703c6e64a8a4ce91`, last commit `c8a55e9`): re-counted today: **225 PASS, 18 PASS (manual), 31 N/A, 0 FAIL, 274 rows** | Matches the handoff. 31 N/A are separate-partition rules (1.1.2.3.x–1.1.2.7.x), GDM/XDMCP (1.7.x), timesyncd (2.3.2.x), `at` (2.4.2.1), IPv6 sysctls (3.3.2.x), journal-remote (6.1.1.1.2). **Level 2 – Server (+76) is not started** and is gated on a log volume; the OS gate is L1 only (handoff step 10). Audit method is hand-check, not CIS-CAT (CIS-CAT Lite does not cover 26.04). I did not re-run any audit command; the CSV is the record. |
| 11 E810 capture config | DONE | `STEP11-DONE` 2026-11-05 ~08:26 CT; `docs/tool-install/step-11-e810-capture.md`. Live today: `eno1np0` `UP` `PROMISC`+`NOARP`, 10000, carrier 1, no address; `eno2np1` operstate `down`; `eno3` `192.168.50.152/24`; no XDP program attached | Hashes read today match the repo and the handoff: `60-johnny-capture.conf` `78939fd5…`, `capture-cores` `16fbd7d1…`, `capture-tuning.sh` `1aa19b9f…`, tuning unit `64b3045c…`. |
| 12 signed-UKI research | DONE (research only) | `STEP12-RESEARCH-DONE` 2026-11-05T19:24:09Z, `SLOTS-DONE`; `docs/tool-install/step-12-signed-uki.md` | Lab stays option A (PCR 7). **Option D is not applied.** No UKI built, no enroll. |
| 13 IRQ affinity (13, 13b, cycle fix, 13c, 13d) | DONE | `STEP13-IRQ-DONE`, `STEP13B-NAME-MATCH-DONE`, `STEP13B-IRQ-UNIT-CYCLE-FIXED`, `STEP13B-ENO1-WAIT-FIXED`, `STEP13B-ENO3-WAIT-FIXED` (the last AJ-reported). Cold reboot 2026-11-06 01:20:40Z passed | Unit sha256 `6084be53…` matches the repo (read today). Spread 3/3/3/3. |
| **13f helper lint** | **UNREC** | Live helper sha256 `db58d7c72b5a58cbd0c2533caa819d397e4c205242e30e5defb0eae0f4ab59e4` (mtime 2026-11-06 01:54:06Z); `/var/lib/johnny/step13f-prev/irq-affinity.sh` is `807f5a55…` (the 13d blob), mtime 01:54:06Z. Journal boot -1: `sudo[3280]: aj … COMMAND=/usr/bin/bash /home/aj/cis-audit/step-13f-helper-nits.sh` at 01:54:05Z; oneshot restarted, `PIN-OK`, no `Broken pipe`. Reboot at 01:55:40Z. Boot 0 (01:55:57Z): `PIN-OK` at 01:56:13Z, 0 `Broken pipe` lines (boot -1 had 11) | **Applied, by journal.** Not recorded: the token, any review verdict, the `/root/step13f-<UTC>.log` (unreadable as `aj`). The repo mirror `etc/johnny/irq-affinity.sh` is the 13f blob and equals live, so the `etc/` rule holds. What is stale: runbook "Step 13f" heading ("draft, not applied, not reviewed"), handoff Config row for the helper, the 13f commit message. **[Inference]** the script ran to its end because the prev-copy, install and the post-restart `PIN-OK` all show; the script's own final line was not seen. |

Other checks today (read-only, 2026-11-06 ~02:54Z):

| Check | Result |
|---|---|
| Kernel / failed units | `7.0.0-42-generic`; `systemctl --failed` empty |
| Holds | `secureboot-db`, `shim-signed` |
| `/run/reboot-required` | absent |
| Lockdown | `none [integrity] confidentiality` |
| Firewall / AIDE | `ufw` active (`ENABLED=yes`); `dailyaidecheck.timer` enabled |
| Listeners (`ss -lntu`, as `aj`, owners not shown) | tcp 0.0.0.0:22; resolved stub 127.0.0.53/54:53; chrony udp 127.0.0.1/[::1]:323; networkd udp `eno3`:68. Same set AJ approved for CIS 2.1.23. No `[::]:22` line, which fits AJ's no-IPv6 policy (not otherwise verified here). |
| `rp_filter` | `all` 1, `eno1np0` 2, `log_martians` `all` 1. AJ left per-NIC at 2 (batch 4 close). |
| `systemd-networkd-wait-online` | `inactive` (skipped; the architecture-pass item) |
| SBOM base rows | 22 package rows from the rev 3 table re-read with `dpkg-query`: all match (kernel `7.0.0-42.42`, systemd `259.9-0ubuntu0.1`, netplan `1.2-1ubuntu5.1`, dracut `110-11ubuntu0.1`, cryptsetup `2:2.8.4-1ubuntu4`, shim-signed `1.59+15.8-0ubuntu2`, secureboot-db `1.9build2`, grub-efi-amd64-signed `1.215+2.14-2ubuntu1`, fwupd `2.1.1-1ubuntu3.1`, mokutil `0.7.2-2`, tpm2-tools `5.7-1build1`, aide/aide-common `0.19.2-3`, apparmor-utils `5.0.2-0ubuntu1~26.04.1`, ufw `0.36.2-9build1`, chrony `4.8-2ubuntu1`, thermald `2.5.11-0ubuntu1.1`). `libtss2-*` are `4.1.3-6` under `…t64` names; the SBOM table writes them without `t64` (naming only, no version drift). Last dpkg activity on the box is the 2026-11-05 06:48Z unattended run. |
| Disk | `/` 5% of 460G, `/boot` 5% |

## 4. agent-team §8 review checklist

Method for items 1–2 (reproducible; my scripts are scratch, not in the repo): parse §5 rows and compare to the bullet titles in `docs/Enterprise Security Software Team Roles.md`; count backtick skill bullets under §2. §3 says titles, skills and practices are "checked by script (§8)", but **no such script is in the repo** (`tests/` holds only `cis-batch4/`). That is a finding for Assurance, not a fail of the items.

| # | Item | Verdict | Evidence |
|---|---|---|---|
| 1 | 127 titles, each to exactly one destination | **PASS** | §5 table counts sum to 127; listed titles 127, unique 127; set-equal to the 127 bullets in the roles doc (normalised), no duplicates, none missing. Run 2026-11-06. |
| 2 | 78 skills, no repeats; 8 each for Architect and every arm, 6 Brain | **PASS** | §2: Brain 6, Architect 8, eight arms 8 each = 78; 78 unique names. |
| 3 | 19 SSDF v1.1 practices each have an owner; PW.5, PW.6, PW.9 split by path | **PASS** (structure) | §8 table has 19 rows. Checked against NIST SP 800-218 text fetched 2026-11-06 (<https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-218.pdf>): PO.1–5, PS.1–3, PW.1, 2, 4–9, RV.1–3 are the practices; PW.3 appears only as "Moved to PO.1.3 / PW.4.4". PW.5, PW.6, PW.9 are split by path, with one exception noted at item 4. |
| 4 | Every repo path has one owner (§4) | **PASS by catch-all, with ambiguities** | The "everything not listed" Platform row catches all tracked paths. Ambiguous or stale: (a) `etc/systemd/system/johnny-capture.*` (Fast Path) does not match the real `johnny-capture-irq.service` and `johnny-capture-tuning.service` (hyphen, not dot), so they fall to Platform although the skill `e810-capture-tuning` is Fast Path's; (b) `paperclip/brain.md` has no row (handoff already says it falls to Platform); (c) `tools/relay/` has no row; (d) the Platform row says "today: all 15 files", and `etc/` now holds 56 tracked files; (e) `tests/cis-batch4/` is Assurance by the `tests/` row; its name suggests CIS batch 4 verification (Governance's area). I did not read it. Brain-owned file; not edited here. |
| 5 | No agent holds an authority title; AJ holds all 16 | **PASS** | §5 lists the 16 titles under AJ. A case-insensitive search of every `.claude/agents/*.md` (11 files, including `code-writer` and `adversarial-reviewer`) for CEO, CISO, authoriz*, decision authority and system owner found 0 hits. |
| 6 | Every §3 "looks shared" place has a split rule | **PASS** | §3 table: 9 rows, each with a split. |
| 7 | PO.2.1 Example 3 role list covered in §5 | **PASS, note** | Checklist text matches the NIST wording (same fetch as item 3). Mapping: cybersecurity staff → Not a role; security champions → Dropped; project managers and leads → Brain; senior management → Not a role; developers → Daemon; testers, software assurance leads and staff → Assurance; product owners → AJ; operations and platform engineers → Platform. Three of the nine are dispositioned as Not a role or Dropped rather than owned. §5 gives reasons; the Overseer may want to confirm that reading of PO.2.1. |

Other drift found while checking (listed, not fixed; Brain's file):
- `docs/agent-team.md` §6 "Model seats" still names **Grok 4.7** as writer and Claude Code as reviewer. Rev 10 header, §1 and `AGENTS.md` say two Claude Code seats (Sonnet, medium). `AGENTS.md` is the standing pin.
- §8 intro says "For the Overseer and Grok."
- `README.md` line 3 says "AJ designs, Grok builds, Claude reviews."

### SSDF practice table (owner defined; practice evidence observed in this repo)

"Observed" means a path exists today. "None yet" means no code or artifact exists, which is expected at this phase. This is a read of the repo, not an assurance verdict.

| Practice | Owner (§8) | Owner defined | Evidence observed |
|---|---|---|---|
| PO.1 requirements | Governance | pass | CIS 26.04 L1 CSV; `docs/compliance/risk-register.md` |
| PO.2 roles | Brain | pass | `docs/agent-team.md`, `.claude/agents/` (11 files) |
| PO.3 toolchains | Platform | pass | `docs/tool-install/` runbooks and self-tests; step 7 SBOM |
| PO.4 security-check criteria | Assurance | pass | tokens and pass lines in each runbook; `docs/findings/cis-batch-*-review.md` |
| PO.5 dev environments | Platform | pass | thin: rock-box is the dev host; Paperclip trial notes in the handoff; no build environment record (`dev-toolchain` skill has no artifact) |
| PS.1 protect code | Platform | pass | git on GitHub, PRs merged by AJ; `.git` read-only in Paperclip sandbox (handoff). No branch-protection record in repo. |
| PS.2 release integrity | Governance | pass | none yet (no release) |
| PS.3 archive and SBOM | Governance | pass | SBOM in `docs/os-handoff.md` with `.deb` hashes for aide and apparmor sets; the proposed move to `docs/compliance/sbom.md` is not done |
| PW.1 design | Architect | pass | none yet; architecture pass deferred (§7) |
| PW.2 design review | Assurance | pass | none yet |
| PW.4 reuse secure software | Governance | pass | `docs/findings/aide-vetting.md`, `docs/compliance/apparmor-utils-vetting.md` (two vettings; no vetting doc for the step 7 packages is in the repo) |
| PW.5 secure coding | by path | pass | none yet (`bpf/`, `daemon/`, `slm/`, `common/` do not exist); shell helpers under `etc/johnny/` were shellcheck-linted (13f) |
| PW.6 build config | by path | pass | `docs/tool-install/xdp_pass_count.c` and `.o` (clang 18.1.3 command in the step 11 runbook) |
| PW.7 code review | Assurance | pass | adversarial-reviewer reviews per PR; verdicts not in git (§1 item 2) |
| PW.8 test code | Assurance | pass | `step-11-self-test.sh`, `step-13-self-test.sh`; `tests/cis-batch4/` |
| PW.9 secure defaults | by path | pass | CIS L1 fix pass; Suricata and iperf3 disabled; capture units pinned by hash |
| RV.1 identify vulnerabilities | Governance | pass | R-AIDE-1 advisories; `unattended-upgrades` security-only |
| RV.2 assess and remediate | Governance | pass | risk register (4 entries) |
| RV.3 root cause | Assurance | pass | boot-race root cause in the step 13 runbook (journal timestamps) |

## 5. Module 1 (eBPF fast path) entry

"Ready" means a recorded fact. It is not a design decision. Module 1 is not started.

**Ready (recorded)**
- **E810 capture path.** `eno1np0` UP, `PROMISC`+`NOARP`, 10000 Mb/s, no address, `optional: true`; mirror target SFP+7; SFP+8 DAC out. `eno2np1` admin-down. E810 NVM 4.70, DDP "ICE OS Default" 1.3.43.0, Gen4 x4 by slot wiring (~50 Gb/s usable, **[estimate]** per the handoff).
- **IRQ pins.** Twelve `ice-eno1np0-TxRx-N` on CPUs 1–4 (3 each), aux on CPU 1, `irdma` left on `0-23`. Survives a cold boot with no manual start (2026-11-06 01:20:40Z and 01:55:57Z). Capture cores file `1 2 3 4`. RPS/XPS `000000`; RSS, RPS, XPS tuning is **deferred**. `eno2np1` IRQs unpinned.
- **CPU tuning.** EPP `performance` and deep idle off on CPUs 1–4 (`johnny-capture-tuning.service`); CPU 0 unchanged.
- **XDP probe history.** Step 11 attached the pass-counter `docs/tool-install/xdp-pass-count.o` in native `xdpdrv` only (mode `driver`), counter rose, detached and unpinned before `XDP-OK`. No program is attached now (`prog/xdp` count 0). Earlier step 11 re-pastes stopped before any change on a flag gate, a `comm` exit, and a C1 name mismatch (revs 70–72). AF_XDP was not opened; zero-copy is untested. MTU 1500 (ice blocks XDP above ~3 KB: <https://www.kernel.org/doc/html/latest/networking/device_drivers/ethernet/intel/ice.html>).
- **Lockdown notes.** Integrity lockdown active. eBPF/XDP load as root worked under it. Out-of-tree modules (Intel OOT `ice`, PF_RING, DPDK kmods) need MOK signing; `bpf_probe_write_user` blocked; `setpci` writes believed blocked (untested). No Johnny change touched lockdown.
- **Toolchain on the box.** `bpftool` 7.7.0, `bpftrace` 0.25.0, `bpfcc-tools` 0.35.0, `tcpdump`, `tshark` 4.6.4, `tcpreplay` 4.5.2, `hping3`, `iperf3`, `stress-ng`. `dumpcap` has `cap_net_admin,cap_net_raw=eip`; `aj` in `wireshark`. Build toolchain (Rust, clang for BPF) is not recorded as installed on Johnny; the runbook says the `.o` was built on the drafting host with Ubuntu clang 18.1.3.
- **Thermal and power record.** Soak data in step 8 (above), as input to Module 1 sizing.

**Blocked or deferred (not resolved here)**
- **Endpoint vs network (agent-team §7.4).** The architecture summary's Module 1 is host-side (BPF-LSM exec, `vfs_write` entropy, CoW rollback); README says "eBPF fast path"; Johnny's first job is a passive SPAN sensor. Fast Path holds both skills. **AJ deferred to the architecture pass.** Entry to Module 1 needs that pick, or an explicit AJ scope for the first Module 1 slice.
- **`wait-online` / boot ordering.** `systemd-networkd-wait-online` is skipped, so `network-online.target` gates nothing. Root cause left for the architecture pass. The IRQ oneshot works around it with its own bounded wait and gates `multi-user.target` for up to 100 s if a NIC never comes up.
- **Memory 19–20% used at idle.** Handoff Parked hypothesis: ~5.7 GB direct kernel/driver allocation, "ice (48 queues) or GPU driver". **Not investigated.** One data point today: `free -m` used 6330 of 31064 MB (20.4%), Slab 213 MB, `Percpu` 21.5 MB, `PageTables` 16 MB. That does not explain 5.7 GB, and the live `ice` queue count is 12 (not 48), so the 48-queue part of the hypothesis needs re-reading before use. Needed "before Module 1 sizing" per the handoff.
- **Suricata stays disabled** until capture setup exists (no config, no capture point). Detection owns that config; `etc/suricata/` does not exist.
- **Fleet option D** (signed UKI plus signed PCR 11 policy) is research. Not applied; lab stays option A.
- **Per-NIC `rp_filter` is 2** (AJ chose leave). Re-check capture on `eno1np0` under strict `rp_filter` when Module 1 capture exists (batch 4 close note). Martian log lines: step 11 recorded 2475 → 2477; I did not re-measure on a comparable basis.
- **Inline mode, quarantine path, Wi-Fi visibility** are later (agent-team §7.6; README Design decisions). Passive first.
- **SLM budget.** On-box SLM is in the architecture with full function for now; its memory budget is not set. It competes for the 32 GB single-channel RAM.
- **No fallback kernel** until the next kernel update; recovery is the installer USB.

**Deferred to the architecture pass (agent-team §7; listed, not worked here)**
3. Tier 1 (global cloud, cross-tenant, MLS fleet keying).
4. Endpoint vs network.
5. CoW filesystem (summary names btrfs; root is XFS, FICLONE is same-filesystem only).
6. Automated quarantine path (OpenC2 `contain` to MAC ACL/VLAN; CRS309 is laptop-only on ether1).
7. Verdict model (K3 states are a draft).
Plus from the handoff: `wait-online` root cause, memory hypothesis, SLM limits, and the Parked ableton_box / Security Onion decisions.

## 6. Risk register snapshot (`docs/compliance/risk-register.md`, four entries)

| Entry | Status | Still applies? | Note |
|---|---|---|---|
| R-AIDE-1 | accepted, option A (AJ, 2026-11-03) | **Yes** | AIDE 0.19.2-3 (read today), two open detection-bypass advisories, no Ubuntu fix. Track for 0.19.5. `dailyaidecheck.timer` enabled. |
| PCR 7 binding | accepted for the lab, option A | **Yes, text partly stale** | `/boot` plaintext, initrd unsigned and unmeasured; physical attacker can edit it or boot MS-signed media. The register says no GRUB password; the CSV says 1.4.1 PASS (batch 10). Whether `init=` at the menu is still open under that password is **unknown** (understanding, untested). Fleet D is research. |
| ksmbd | accepted, option A (AJ, 2026-11-04) | **Yes** | loadable; no `ksmbd-tools`, no listener on 139/445 (the listener set read today has none). |
| R-AAU-1 | accepted, option A (AJ, 2026-11-04) | **Yes** | `apparmor-utils` `5.0.2-0ubuntu1~26.04.1` installed; `aa-disable`, `aa-complain`, `aa-teardown` not run without a decision. |

AJ choices recorded elsewhere that are **not** register entries (the Overseer may want to promote some):
- Non-ECC single-channel DIMM (`ECC-UNAVAILABLE`); ECC buy parked.
- Step 8: 92 °C soak peak, `NOTE-throttled`, no limit set.
- Per-NIC `rp_filter` 2 left as is (batch 4).
- AMT: ACM, TLS-only; port isolation is one-way; DMT console serves on all interfaces while it runs (stopped when idle); MeshCommander Soft-reset is don't-use.
- Boot: no fallback kernel; oneshot can stall boot up to 100 s.
- Suricata disable provenance unrecorded; unattended-upgrades is security-only with no auto-reboot (`/run/reboot-required` absent today).

## 7. Open items that are not blockers by themselves

- Record 13f: runbook heading, handoff Config row, session CSV, and a review verdict (or AJ's statement that none is wanted). Not done in this package beyond the handoff correction noted in the session CSV.
- Per-step review verdicts for PRs #6–#19 into `docs/findings/` or the PR record AJ points to.
- agent-team doc drift (§4, §6, §8 intro) and the missing §8 check script.
- Register text refresh (GRUB password) and possible new entries (thermal, ECC).
- Step 7: who disabled Suricata; apt lists last refreshed 2026-11-05 06:48Z.
- Raw logs on Johnny are not backed up to git by design; confirm that is acceptable for the gate.

## 8. AJ decision lines

Blank. The code-writer seat does not fill these.

```
OS phase closed (Overseer approves; Module 1 may start):   [ ]  AJ ____________  date ____________
Hold (name what is missing):                                [ ]  AJ ____________  date ____________
Rework (name the items):                                    [ ]  AJ ____________  date ____________

Step 13f recorded as applied (AJ ran it 2026-11-06 01:54Z):   [ ] yes  [ ] no
Thermal 92 C / NOTE-throttled: accept as register entry:      [ ] yes  [ ] no  [ ] later
First Module 1 slice scope (endpoint vs network):             [ ] defer to architecture pass  [ ] AJ names scope: ____________
Memory 19-20% idle investigated before Module 1 sizing:       [ ] required first  [ ] not required
Register text refresh (GRUB password) before close:           [ ] yes  [ ] no
```

## 9. Sources

- Repo: `docs/os-handoff.md` rev 93; `docs/agent-team.md` rev 10 §4–§9; `docs/compliance/risk-register.md`; `docs/cis-26.04-l1-results.csv`; `docs/tool-install/*`; `docs/sessions/`.
- NIST SP 800-218 SSDF v1.1: <https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-218.pdf>
- Intel `ice` driver (XDP frame limit, DDP safe mode): <https://www.kernel.org/doc/html/latest/networking/device_drivers/ethernet/intel/ice.html>
- Live reads: Johnny over SSH as `aj`, 2026-11-06 ~02:54Z.
