REQUEST-CHANGES

Review 1 of PR #39 tip `cc4caec` against `ded80c6`. Docs-only diff, six `.md` files. Read-only. No repo edits, no SSH, no sudo, no contact with 192.168.50.152. `bash docs/tool-install/module1-slice2b-self-test.sh` on this host exited 0: `PINS-OK`, `SHELLCHECK-OK`, `STATIC-CHECKS-OK`, `READER-TESTS-OK`, `E2E-OK scenarios=15`, `OUTSIDE-FENCE-DIFF-OK blocks=17`, `RUNBOOK-OK blocks=22`, `SELF-TEST-OK`. All 22 ` ```bash ` fences in `docs/tool-install/module1-slice2b-boot-unit.md` are byte-identical to `ded80c6`. `git diff --name-only ded80c6..HEAD` is only `.md`. No secrets (no passwords, keys, or tokens beyond the operational ids the handoff already records).

Holding (do not churn):
- Items A–F and Decisions 1–6 each end with `AJ decides.` Options inside each item are distinct.
- §4 asks eight code-shape questions and does not answer them inside that section. The violations are outside §4 (B4).
- `docs/agent-team.md` §7 note and §9 item 4 say the pass started and every item is still AJ decision pending.
- Runbook N2 is prose only: rev/status line and purpose items 2 and 5. The Decisions section and every bash fence are untouched.
- Nothing in the diff tells AJ to run a command on Johnny before 2026-11-21 15:33 CT. The LSM and free-space checks are explicitly after the week test and read-only. Milestone 1 is after that clock.
- Handoff rev 115 contains the required apply facts: baseline `21:32:11Z` on 2026-11-14, `boot_id e9476f51-151b-4593-aa88-811e397794d1`, records prog id 78, InvocationID `502eed3ad10a42abab7c05ce28607223`, NRestarts 0, PASS-RATIO 83, VERIFY-DROPS 0/0/0, WINDOW secs=60 seen-delta=32812 emitted-delta=32812 with drop deltas 0, cfg `1000000`/`100000` (rev 114 body, `docs/os-handoff.md:19-22`), Paste W only after 2026-11-21 15:33 CT (21:33Z), retention applied 2026-11-14 19:18Z. 15:33 CT in November is CST (UTC-6), so 21:33Z is the right conversion.
- These quotes match the cited lines: `docs/agent-team.md:54`, `:85`, `:97`, `:113`, `:260` (the `:260-261` quote is line 260; 261 is blank); `README.md:3`, `:8`, `:11`, `:25`, `:26`, `:28`; the `README.md:20` fragments that are actually quoted; `docs/network-map.md:8`, `:15`, `:22-23`, `:25`; `docs/JOHNNY_ Executive Architectural Summary.md:166`; `docs/findings/module1-slice2b/README.md:12`; `docs/tool-install/module1-slice2b-boot-unit.md:41`. The 80-byte `struct m2_rec` and `M2_REC_VERSION 1` are real (`module1_xdp_records.c:78`, `:133-165`). The ring is 4 MiB (`:80`, `(1 << 22)`). Cold-boot `:48` is `ATTACH records 78`. No FICLONE call exists under `*.c`, `*.py`, `*.sh`, or `*.rs`.

K3 in the repo, so the later findings are checkable: `docs/JOHNNY_ Executive Architectural Summary.md:4` and `:87-94` define Kleene strong three-valued logic as a per-process state, `KnownBad = -1`, `Unknown = 0`, `KnownGood = +1`, with inline deny, CoW journaling, and an outbound gate. The LTL at `:70-71` is `G( (S(p)=0 ∧ NetConnect(p, dst)) ⇒ (dst ∈ WhiteList ∨ X DropPacket(p)) )`. `docs/agent-team.md:54` and `:268` call that model a draft, not locked. The pass's "what the repo says" bullets at `architecture-pass.md:203-205` track that. The break is the paraphrase and the draft that follow (B3).

## B1. `j_xdp_records` is given the observer's BPF tag
`docs/architecture/architecture-pass.md:11`

The tag `b5b852630d7539c7` is `j_xdp_observe`, not `j_xdp_records`. It is the slice 1b observer (`docs/tool-install/module1-slice1b-attach.md:19`) and the slice 2b rollback fixture (`docs/os-handoff.md:81`: `138: xdp  name j_xdp_observe  tag b5b852630d7539c7`). No `j_xdp_records` tag is anywhere in the repo. The two citations on that sentence do not contain a tag: `module1_xdp_records.c:133-165` is the struct; `docs/findings/module1-slice2b/2026-11-12-cold-boot-verify.md:24` is `OK-object-hash a73c5bd2…` and `:48` is `ATTACH records 78`.

Fix: delete the tag. Prog id 78, the object hash prefix, `eno1np0`, and the 80-byte record can stay, cited to the lines that actually say them (`cold-boot-verify.md:24` for the hash, `:48` for id 78, `module1_xdp_records.c:78` and `:133-165` for version and size, `:80` for 4 MiB).

## B2. Cited lines do not contain the claimed text
Same commit inserts 13 lines at the top of `docs/os-handoff.md` and one line before agent-team §7 items 3–7, then cites the pre-insert numbers. Several cites were already aimed at the wrong sentence. A reader who opens the cited line gets a different fact, or a blank line.

Wrong now, and what that line actually is:

- `architecture-pass.md:30` and `:33` cite `docs/os-handoff.md:392` for the 6.2 GB idle figure. Line 392 is the Parked Security Onion item. The memory sentence is `:405`.
- `architecture-pass.md:36` cites `docs/os-handoff.md:101` for "CPUs 1–4 are pinned". Line 101 is "Mark assumptions…". The pin fact is `README.md:18` (twelve TxRx queues spread over CPUs 1–4).
- `architecture-pass.md:103` cites `docs/os-handoff.md:96` for kernel `7.0.0-42-generic` and calls it an Assumption. Line 96 is the Context sequence and does not contain `7.0.0-42-generic`. The installed-state row is `:109`, and it is a recorded fact, not an assumption. The same sentence cites `:98` as the proof that `BPF_SYSCALL`, `XDP_SOCKETS`, `ICE`, and `BTF` are present. Line 98 is empty. Those four symbols are inside the rev 98 probe sentence on `:81` (`kernel config BPF_SYSCALL, XDP_SOCKETS, ICE, BTF ok`). Leaving `CONFIG_BPF_LSM` and `lsm=bpf` as not documented is right. Do not "fix" that by inventing a config.
- `architecture-pass.md:130` and `:135` cite `docs/os-handoff.md:102` for the XFS root layout. Line 102 is the SSH access rule. The disk row is `:115`.
- `architecture-pass.md:131` cites `docs/os-handoff.md:313` for "XFS root (FICLONE same-FS only)". Line 313 is "Initramfs: no networking". The carried sentence is `:326`.
- `architecture-pass.md:13` cites `docs/os-handoff.md:23-28` for the retention numbers. Those lines are the `apply-cfg` / `mark-reader` / `week` / `window` / `do_verify` descriptions. The numbers are `:17` and `:36-39`. `docs/findings/module1-slice2b/README.md:12` is the one cite in that sentence that matches.
- `architecture-pass.md:14` cites `docs/os-handoff.md:3-16` for `rate=1000000 burst=100000`. Lines 3–16 have the baseline, prog id, InvocationID, PASS-RATIO, VERIFY-DROPS, and WINDOW. They do not contain `1000000`. That cfg is `:19-22`.
- `architecture-pass.md:362` cites `docs/os-handoff.md:4` for the 200 GiB cap. Line 4 is the rev 115 status banner. The cap is on `:17`.
- `architecture-pass.md:357` cites `docs/os-handoff.md:362` for Suricata 8.0.3 disabled. Line 362 is `ethtool | 1:6.19-1`. The package is `:370` (`suricata | 1:8.0.3-1`). Disabled/inactive is `:375`.
- `architecture-pass.md:62` cites `docs/agent-team.md:263` for Tier 1. Line 263 is the new "Architecture pass started…" note. Tier 1 is `:264`, endpoint `:265`, CoW `:266`, quarantine `:267`, verdict `:268`. The italic sentences are the right sentences, one line high. `:203` has the same off-by-one (`:267` cited, verdict text is `:268`).
- `architecture-pass.md:11` cites `module1_xdp_records.c:133-165` for the 4 MiB ring. Those lines are `struct m2_rec` and the size asserts. The ring size is `:80` and the map is `:218-221`.
- `architecture-pass.md:15` cites `docs/tool-install/module1-slice2b-boot-unit.md:583-596` for "Paste W due only after 2026-11-21 15:33 CT". That range is the Paste W heading ("run >= 7 days after Paste B") and the start of the fence. The clock is the status line this commit added (`module1-slice2b-boot-unit.md:3`) and `docs/os-handoff.md:10`.
- `architecture-pass.md:361` cites `docs/BEGIN_Network_Security_Software_Enterprise.md:13-17` for "millions of file/IP reputations in real-time (<100 ms)". Lines 13–17 are the BrightCloud box: 200+ TB, real-time hash classification, global URL/IP/domain/file directories. They do not say millions of reputations or <100 ms. `<100 ms` is `docs/Security Software Architecture Overview.md:70` ("typically < 100 ms on broadband links"). "millions of endpoints" is BEGIN `:42`, which is a different claim.

Fix: retarget every cite above to the line that contains the sentence, and re-read the quote against that line. Keep a fact only when the new line says it. Stop calling the kernel version an Assumption.

## B3. K3 is remapped and the draft contradicts itself
`docs/architecture/architecture-pass.md:206`, `:209-214`, `:217-226`, `:228-236`

The repo's K3 is a per-process Kleene state (summary `:87-94`). The pass's facts section says states "must" apply to network entities (MAC/IP/domain/cert/tuple) "rather than in-memory OS processes", and then lists transition authorities (who may set Known-Bad, who may promote Unknown to Known-Good, aging) as if they were repo constraints. They are not in the summary, agent-team, or BEGIN. They are a proposal.

The LTL paraphrase at `:206` drops the whitelist. The summary does not say `S=0 ∧ NetConnect ⇒ DropPacket`. It says that connect is allowed when `dst ∈ WhiteList`, and otherwise the next state drops. The pre-write line also drops the "until verdict" (`CoWCloned(f) U Verdict(p) ∈ {+1,-1}` at summary `:72-73`).

The draft the recommendation asks AJ to adopt is internally inconsistent:
- Mermaid `:223`: Known-Bad goes to Unknown, "Admin Reclassification Only".
- Table `:236`: Known-Bad on false-positive resolution goes to Known-Good, "AJ Only".
- Prose `:213` agrees with the table (Known-Bad back to Known-Good), not the mermaid.
- Table `:232` keeps the SLM in Unknown and only tightens thresholds. That is Item A Option 1, written into the verdict model before Item A is decided. agent-team `:85` and `:260` still say full function, tighter or looser, until this pass.

Fix: in "what the repo says", keep the per-process definition and quote the whitelist disjunct. Move the network-entity mapping, the actor table, and the mermaid into Option 1 and label them as a proposed change from the summary, not as facts. Make one exit from Known-Bad, and do not encode Item A's tighten-only rule inside Item F unless that row is explicitly "only if AJ picks Item A Option 1". The gap formula cite at `:358` (`summary:26` is `S_0 = S_t + Σ Δ_k^{-1}`; `:75` is `State_host = S_0 + Σ_{k=t}^{1} Δ_k^{-1}`) should not be presented as one formula at both lines.

## B4. Code shape is recommended, and one recommendation describes a header that already exists
`docs/architecture/architecture-pass.md:313`, `:374`, `:377`, `:462-464`

§3 says the section "does not specify or constrain code structure, languages, or software design." Then `:313` recommends replacing the Python reader with "a high-efficiency compiled ringbuf consumer" and calls that independent of the decisions. That answers §4 question 2 (language) by ruling Python out. Milestone 3 (`:462-464`) repeats it as the build.

§6 design advice answers §4 questions 3 and 4:
- `:374` tells AJ to "define an explicit schema versioning header (or adopt an extensible format)".
- `:377` tells AJ to use `#[repr(C)]` and a shared C ABI header. That is Rust layout and an interface. agent-team `:52` and the summary `:77-98` already float `#[repr(C)]`; reporting that, cited, and marked as AJ's call, would be allowed. This paragraph does neither. It is the pass's advice.

The header advice is also wrong about today's files. `docs/tool-install/johnny-m1s2b-reader.py:58-63` already writes a 96-byte header: magic `JM1S2RB`, `HDR_VERSION = 1`, record size, record version, clock offset, and an `m2_cfg` snapshot. `:373` says the files are raw 80-byte structs and gives "VLAN tags" as an example of a field the struct lacks. `module1_xdp_records.c:128-142` already has `vlan_tci` and `F_VLAN` / `F_QINQ` / `F_VLAN_DEEP`. TCP window and payload entropy are actually absent; VLAN tags are not a clean example.

Fix: delete the design-advice sentences at `:374` and `:377`, and delete the "compiled ringbuf consumer" prescription at `:313` and `:464`. If a milestone stays, say "ring-buffer consumer, language per §4 question 2" and stop. If the summary's Rust/`#[repr(C)]` text is mentioned anywhere, cite it and write that AJ has not adopted it. Describe the on-disk file as a 96-byte versioned header plus 80-byte records.

## B5. Numbers used as facts are not in the repo and are not marked Assumption
`docs/architecture/architecture-pass.md:34`, `:419`; `docs/os-handoff.md:7`

- `:34`: "4-bit 1.5B–4B parameters requires 1.5 GiB to 3.5 GiB resident memory plus dynamic KV cache." Nothing in the repo or in the external source list says 4B or 1.5–3.5 GiB. The summary `:7` says "4-bit quantized". BEGIN `:4720` says "e.g., Qwen-1.5B" and does not give a RAM band. Decision 3 at `:419` then says Option A "fits 32 GB RAM budget" on the back of that band. README `:25` still says the on-box SLM is not budgeted, because Suricata, Zeek, the daemon, and ClickHouse or Timescale are the 32 GB stack. `:33` lists those consumers and never adds them up.
- `docs/os-handoff.md:7`: `rate_limited 18217138 historical`. That integer appears nowhere else in the repo, is not in the apply facts this review was given to match, and is not marked Assumption. Paste A's "cfg 8000/16000 before" is the previous config and can stay.

Fix: delete the parameter count and the GiB band, or mark them Assumption and stop using them as the reason Option A fits. On `:419`, do not claim a RAM fit. Delete `18217138` unless a committed paste contains it; do not invent a substitute.

## B6. The commercial-EDR gap section states false Johnny facts and overstates the vendors
`docs/architecture/architecture-pass.md:356`, `:358`, `:360`, `:362`

The nine rows and the Needs-from-AJ column are the right shape (host telemetry, detection content, response/rollback, fleet, tamper resistance, backend/intel, storage, ops, testing). These cells are not honest:

- `:360`: "userspace reader runs as standard root Python script; BPF maps lack pinned ACLs beyond root." The unit is root, and it is not a stock root script. `etc/systemd/system/johnny-m1s2b-reader.service:11` is `User=root`; `:35-41` set `NoNewPrivileges`, empty `CapabilityBoundingSet` and `AmbientCapabilities`, and `ProtectSystem=strict`; `:32-34` set `PrivateNetwork=yes` and `IPAddressDeny=any`; `:41` allows writes only to `/sys/fs/bpf/johnny_m1s2b/m2_rb` and `/var/lib/johnny/m1s2b`; `:63` is a syscall filter. "BPF maps lack pinned ACLs beyond root" has no source. The Needs cell ("define service hardening… capability dropping, read-only rootfs") asks AJ for controls this unit already has, and it ignores them. CIS "225 PASS" is the automatic-pass count only; the recorded total is 225 PASS, 18 PASS (manual), 31 N/A, 0 FAIL (`docs/os-handoff.md:90`).
- `:356`: "script interpreter ASTs" is not a quoted claim from the cited CrowdStrike PDF, and it is not in the repo. The PDF URL is the only external cite on that sentence.
- `:358`: "CrowdStrike provides instant host network isolation via kernel NDIS/eBPF drivers" has no cite. A 2020 Falcon architecture PDF is not evidence for an eBPF isolation driver. The Needs cell tells AJ the outcome ("Drop file rollback and establish advisory quarantine workflows") instead of asking for the Item D and Item E decision.
- `:362`: "ClickHouse / Snowflake" as the commercial EDR standard is not a Webroot or CrowdStrike fact. ClickHouse or Postgres/Timescale is Johnny's own README `:25` candidate list. The Johnny-side "200 GiB" cite is the wrong line (B2); the cap itself is real.

Webroot's `WRkrn.sys` shadow cache at BEGIN `:67-89` and the overview `:26-38` is a fair repo cite. Keep that. Do not extend it.

Fix: describe the reader by the unit's actual controls, and state the remaining gap as "no kernel anti-tamper of the daemon and no measured pin-mode claim" only if a file is cited. Make every Needs cell a question. Delete AST, NDIS/eBPF, and ClickHouse/Snowflake, or replace them with a sentence that is quoted from the cited PDF. `:359`'s "Formally scope Johnny to single-node appliance" has the same defect as `:358`: ask AJ to decide Item B, do not write the recommendation as the need.

## B7. Item E's "exact" RouterOS command is not the repo's quarantine and is not cited
`docs/architecture/architecture-pass.md:174`, `:175`, `:179`

The repo's rule is MAC ACL or VLAN, never port shutdown (`README.md:28`, `docs/agent-team.md:97`, `:113` now that B2's off-by-one is applied). `:174` instead offers `/interface bridge filter add action=drop mac-protocol=ip src-mac-address=...` and calls it exact and copy-pasteable. It has no `chain=`, so it is not a complete RouterOS 7 command, and no RouterOS document is cited. `:179` builds Option 2 on the same uncited bridge-filter path. `:175` calls ether1 management a "physical air-gap". `docs/network-map.md:22-23` is out-of-band management: SSH/Winbox from 192.168.88.0/24, and the bridge address 192.168.50.221 answers ping. That is not an air gap. The OOB facts in `:167-170` are right; keep those.

Fix: Option 1 hands AJ a MAC ACL or VLAN action in the words the repo already uses, and says the exact RouterOS lines are not in this brief. Delete the bridge-filter example. Replace "air-gap" with the network-map wording (management only on ether1, not manageable from the LAN).

## N1. FICLONE wording overreaches the man page, and `reflink=1` is not shown for this volume
`docs/architecture/architecture-pass.md:134-135`

`ioctl_ficlone(2)` (https://man7.org/linux/man-pages/man2/ioctl_ficlone.2.html) says both files must be on the same filesystem; `EXDEV` is "not on the same mounted filesystem". It does not say every distinct mount point fails. Two bind mounts of one filesystem still share a superblock. "O(1)" is not in that page; the page says the clone is faster than a physical copy. `reflink=1` on Johnny's XFS is not in the repo and is not marked Assumption. The same-filesystem limit at `docs/os-handoff.md:326` is the sourced claim. Keep that. Mark `reflink=1` as Assumption or drop it.

## N2. "MAX/Rock Box" treats two names as one host
`docs/architecture/architecture-pass.md:48`, `:70`, `:418`, `:443`

README `:26` and agent-team `:264` say the upstream is the MAX over the LAN. rock-box is the SFP+4 workstation (`docs/network-map.md:12`). The parked Security Onion note (`docs/os-handoff.md:392-393`) points the manager at ableton_box and the model at strix-halo, not at rock-box. Write "the MAX". If a sentence also names rock-box, mark it Assumption or ask AJ which machine the MAX is.

## N3. Rev 114's heading still says the rate cap is not applied
`docs/os-handoff.md:16`

The status line at `:17` says applied and verified (2026-11-14 21:32Z, see rev 115). The heading still says "DRAFTED, NOT APPLIED". Rev 115 at the top is clear. The heading should say applied, or say that the heading is the original draft title. As written, the section contradicts itself.

`docs/findings/module1-slice2b/README.md:13` still says the rate cap is drafted, not applied, directly under the retention bullet the pass cites (`:12`). `README.md:20` still says the retention raise is drafted, not on Johnny; the pass's ellipsis at `architecture-pass.md:96` skips that clause. Flag both drifts in the brief. Do not leave AJ with two live-state stories.

## N4. "Production" and a couple of option claims are stronger than the sources
`docs/architecture/architecture-pass.md:10`, `:99`, `:175` (air-gap is B7), `:180`

`:10` says Module 1 is in a "verified production state" while the same page says a 7-day validation gate is the thing still running. Say verified at the 21:32Z window, week test in progress.

`:99` says SFP+7 receives mirrored ingress from SFP+3 (bedroom). Mirror config does include SFP+3 (`docs/network-map.md:25`). At the 2026-10-29 audit SFP+3 had no link (`:11`). Say configured mirror source, no link at that audit.

`:180` "sub-second network quarantine" is not sourced. Drop the latency claim.

Item B Option 2 (`:75`) specifies "a simple JSON-over-TLS stub in the daemon". That is an interface inside an unchosen option. Describe the option as "keep the Tier 1 words, implement only a LAN client" and leave the encoding in §4.

## N5. Handoff verify lines compress script tokens; one extra claim has no transcript
`docs/os-handoff.md:9`

`docs/tool-install/module1-slice2b-boot.sh:747` prints `PASS-RATIO tcpdump=<n> xdp=<n> pct=<n>`, not `PASS-RATIO 83%`. The value 83 matches the required fact. The tcpdump and xdp counts are dropped, so the ratio cannot be recomputed from rev 115. `:666` prints `ETHTOOL-DROP-DELTAS none (checked=<n>)`. Rev 115 says `ETHTOOL-DROP-DELTAS none` with no `checked=` count and no committed Paste C transcript. Add the two counts if the paste had them, and either include `checked=` or drop the ethtool clause. Do not invent the counts.

## N6. §8 schedules the recommendations as the path
`docs/architecture/architecture-pass.md:464-476`

The section is labeled proposed, and it correctly forbids Johnny changes before the gate and code construction before §4 is answered. Milestone 4 still "implements the K3 state machine", milestone 6 turns on Suricata/Zeek on Johnny, and milestone 7 says "over mTLS" (WireGuard was the other half of Option 1). Prefix each of those with "only if AJ picks" the matching option, or the brief has decided them.

## N7. Two listed external sources are not used by a claim
`docs/architecture/architecture-pass.md:498-499`, `:506`

NIST SP 800-207 and SP 800-218 are in the source list and not cited in the body. The Webroot URL at `:506` is a white-paper index, not a paper the gap table quotes. Drop them or cite a sentence that uses them. RFC 9420, RFC 8446, the BPF LSM page, `ioctl_ficlone(2)`, and ATLAS AML.T0051 are actually used; AML.T0051 in the summary is filenames and CLI args (`summary:166`), and the pass's extension to DNS and HTTP payloads (`:35`) should stay labeled as the pass's application of that technique, which it roughly is. No change required on AML.T0051 beyond not calling the GiB numbers part of it.
