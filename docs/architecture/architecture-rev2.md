# Johnny Architecture Rev 2: AJ Decisions and Stages

Rev 2, 2026-11-17 America/Chicago. Status: AJ DECISIONS RECORDED + STAGE 1 APPLIED AND VERIFIED ON JOHNNY 2026-11-17 + ROCK BOX §3 CHECK RECORDED 2026-11-17 + STAGE 2 DECISIONS O17/O21/O27/O28 AJ-DECIDED 2026-11-17 (O27 window + O17 minisign: `docs/os-handoff.md` rev 122, `docs/sessions/2026-11-17-stage2-decisions-2.md`; `docs/os-handoff.md` rev 121, `docs/sessions/2026-11-17-stage2-decisions.md`; `docs/findings/stage2/2026-11-17-rockbox-fs-check.md`, `docs/os-handoff.md` rev 120, `docs/sessions/2026-11-17-stage2-rockbox-fs-check.md`; Stage 1: `docs/os-handoff.md` rev 119, `docs/sessions/2026-11-17-stage1-cutover-applied.md`)

This file supersedes the decision brief `docs/architecture/architecture-pass.md` (rev 3) for every item it decides. Items it does not decide stay open, and each one says **AJ decides.**

- **Source of the decisions:** AJ answered the brief through his architect on 2026-11-14 at about 10:04 PM and 10:08 PM CT, approved rev 1 of this plan at 10:11 PM CT, and approved the four Stage 1 code-shape picks (O5, O6, O8, O9) at 10:56 PM CT (`§1.2`, `§2.3`, `§4 Stage 1`, `§7`). The chat is not saved in the repo. This file is the record.
- **Wording:** each decision below is AJ's words paraphrased. Lines under "Notes" are not AJ's words. They carry a repo cite, a URL, or a label.
- **Hold (superseded 2026-11-17 by AJ's choice):** Johnny's one-week capture test (`2026-11-14 15:33 CT` to `2026-11-21 15:33 CT` / `21:33Z`, `docs/tool-install/stage1-rust-daemon-cutover.md:10-11`, `docs/os-handoff.md:30`) was ended early by AJ's choice on 2026-11-17 (~3 days, not 7; 0 new `rate_limited`, `rb_full`, or `discarded` drops from baseline `2026-11-14T21:32:11Z` to cutover) when AJ ran Pastes S1-1..S1-5 to apply Stage 1 (`docs/os-handoff.md` rev 119). Paste W is superseded and is no longer the gate.

Labels used here:

| Label | Meaning |
|---|---|
| **AJ decision (AJ, 2026-11-14)** | AJ decided it. Recorded as given. |
| **Target** | A goal. Not measured. Not a fact. |
| **UNVERIFIED** | Nobody has checked it yet. |
| Assumption: | The writer's reading. AJ can overrule it. |
| **AJ decides.** | Still open. Numbered in §7 (O1 to O34). |

---

## 1. AJ Decisions

### 1.1 Target: hybrid

**AJ decision (AJ, 2026-11-14):** The target is a hybrid.
- A CrowdStrike-style backend on the MAX.
- Webroot-style lightweight endpoint agents.
- Johnny stays the network sensor.

Notes:
- This resolves brief Decision 1 toward the scope of Option C (network sensor plus endpoint agents on other LAN hosts, `docs/architecture/architecture-pass.md:404`; Item C Option 3, `:116-120`). It is staged (§4). The brief recommended Option A (`:405`). AJ did not take that recommendation.
- The brief's own note says a network-only sensor cannot reach Webroot or CrowdStrike class, and that Decision 1 Option C is the path to that level (`docs/architecture/architecture-pass.md:122`, `:406`).
- Johnny's role does not change. It watches mirrored traffic on `eno1np0` (`docs/architecture/architecture-pass.md:11`).
- The MAX is named in `README.md:26` and `docs/agent-team.md:75`. It has no host record under `docs/hosts/` (only `docs/hosts/ableton_box.md` is there). Its hardware, OS, and address are **UNVERIFIED** in this repo. **AJ decides.** (O4)
- Whether Johnny itself also gets host LSM self-protection (brief Decision 1 Option B, `docs/architecture/architecture-pass.md:403`) was not decided. **AJ decides.** (O1)

### 1.2 Code shape

**AJ decision (AJ, 2026-11-14):** AJ dictates the code shape. Recorded as given:

1. One lightweight deterministic sensor daemon.
2. Control-plane / data-plane separation inside that daemon. Control plane = PDP / PE / PA. Data plane = PEP.
3. C stays in-kernel for BPF.
4. Rust for userspace.
5. AI inference runs as a separate process, or on the MAX over gRPC.
6. The AI is wrapped in a Run-Time Assurance (RTA) monitor.
7. A version field in every record. Readers must ignore unknown fields.
8. An LPM-trie block map.
9. Hot-reloadable rules with candidate / validate / commit, and rollback.
10. Signed builds plus SBOM.
11. Logs streamed to the MAX over TLS 1.3.

Notes:
- The plane terms are from NIST SP 800-207 (https://csrc.nist.gov/pubs/sp/800/207/final). PDP is the Policy Decision Point. It is made of the Policy Engine (PE), which decides, and the Policy Administrator (PA), which tells the enforcement point what to do. PEP is the Policy Enforcement Point, which enforces. The repo already names this split (`docs/JOHNNY_ Executive Architectural Summary.md:44`, `docs/agent-team.md:53`).
- TLS 1.3 is RFC 8446 (https://www.rfc-editor.org/rfc/rfc8446.html).
- C in-kernel and Rust in userspace match the reference design (`docs/JOHNNY_ Executive Architectural Summary.md:7`, `:174-176`; `docs/BEGIN_Network_Security_Software_Enterprise.md:4755`).
- LPM trie is a kernel BPF map type for longest-prefix match (https://docs.kernel.org/bpf/map_lpm_trie.html). The reference design uses one for CIDR drops (`docs/JOHNNY_ Executive Architectural Summary.md:35`, `:175`).
- AJ did not say which program holds the block map or what it blocks. On Johnny's passive SPAN port a drop cannot block traffic between other hosts (`docs/architecture/architecture-pass.md:222`, `:315`). **AJ decides.** (O12)
- SBOM is already in the reference design and the roster (`docs/JOHNNY_ Executive Architectural Summary.md:46`, `docs/agent-team.md:134`).
- No repo source defines the RTA monitor. Assumption: it is a small deterministic check between the AI and the daemon. It passes only outputs that are inside fixed bounds. It drops anything else and a safe default applies. Its checks and its fallback: **AJ decides.** (O14)
- How the two planes are kept apart inside one daemon (threads, processes, the interface between them) was not stated. **AJ decides.** (O13)
- "Rust for userspace" does not name the language of the AI inference process or of the Windows kernel driver. **AJ decides.** (O11)
- Which brief §4 questions this answers is in §2.3.

### 1.3 Why the AI exists

**AJ decision (AJ, 2026-11-14):** The AI has two reasons to exist:
- (a) neuro-symbolic logic / heuristics;
- (b) telemetry triage / efficiency.

Both run asynchronously, off the hot path.

Notes:
- Repo background for (a): semantic judgment of command lines and scripts that byte math cannot make (`docs/BEGIN_Network_Security_Software_Enterprise.md:4732`, `docs/agent-team.md:84`).
- Repo background for (b): telemetry compression before it goes upstream (`docs/JOHNNY_ Executive Architectural Summary.md:7`, `docs/BEGIN_Network_Security_Software_Enterprise.md:4741`). The size of that saving is a **Target** (§1.6).
- The reference design already runs the model asynchronously (`docs/JOHNNY_ Executive Architectural Summary.md:165`).

### 1.4 Endpoint scope

**AJ decision (AJ, 2026-11-14):** Linux first. Windows (ABLETON_BOX) in Stage 4.

Notes:
- The first Linux endpoint is Rock Box (Stage 2, §4). Rock Box is the Ubuntu workstation on SFP+4 (`README.md:24`, `docs/network-map.md:12`).
- Which other Linux hosts get an agent, and in what order, was not stated. **AJ decides.** (O2)
- `docs/hosts/ableton_box.md:3` records AJ (2026-10-31): the box gets a new OS, and its role is not decided. `docs/os-handoff.md:403-405` parks three decisions about it, one of them an Ubuntu Server install. Stage 4 needs Windows on that box. These two records and this decision are not yet reconciled. **AJ decides.** (O3)

### 1.5 Four fixes (AJ-approved corrections)

#### Fix 1: The AI can only tighten or suggest

**AJ decision (AJ, 2026-11-14):** The AI can only tighten or suggest. Loosening comes only from rules signed by AJ.

This explicitly supersedes:
- The per-PID / per-directory relax example: "it instructs the eBPF map to relax χ² and entropy tripwires for that directory" (`docs/BEGIN_Network_Security_Software_Enterprise.md:4734-4737`; same text at `docs/Security Software Architecture Overview.md:1229`).
- "Full function for now" in `docs/agent-team.md:260` (§7.2).

It also resolves brief Decision 3 / Item A (`docs/architecture/architecture-pass.md:419-426`, `:21-54`).

Notes:
- The reference design's own risk table already says tighten, never loosen (`docs/JOHNNY_ Executive Architectural Summary.md:166`). The reason is prompt injection: a string in a filename or command line could talk a model into an ALLOW (same row; MITRE ATLAS AML.T0051, https://atlas.mitre.org/techniques/AML.T0051).
- The brief's Option 1 had one cost: false positives need an administrator (`docs/architecture/architecture-pass.md:40`). AJ-signed rules are that administrator path.
- The signature scheme: **AJ-DECIDED 2026-11-17** (AJ, 7:59 PM CT: "follow claude recs"): Ed25519 via minisign (**AJ-DECIDED 2026-11-17 9:01 PM CT**), see O17. (O17)
- What counts as "tighter" must be written down for each threshold and each verdict transition before the AI may change one. The per-PID thresholds in the reference design are `chi_sq_scaled_max` and `entropy_q16_min` (`docs/JOHNNY_ Executive Architectural Summary.md:96-108`). **AJ decides.** (O18)
- Where a "suggest" goes and how AJ sees it was not stated. **AJ decides.** (O19)
- Repo lines that still carry the old rule are listed in §6.

#### Fix 2: Rollback on Rock Box depends on Rock Box's filesystem — **VERIFIED 2026-11-17: ext4, no reflink → full-copy shadow**

**AJ decision (AJ, 2026-11-14):** Rollback on Rock Box depends on Rock Box's filesystem, which was not yet verified at the time of the decision (verified 2026-11-17, see Status below).
- Reflink / FICLONE where the filesystem supports it (btrfs; XFS with reflink).
- Otherwise a full-copy shadow (e.g. ext4).
- Disk use scales with the write volume of the monitored process.

Status: **VERIFIED 2026-11-17 (§3 check, run by AJ ~5:04 PM CT, raw output in `docs/findings/stage2/2026-11-17-rockbox-fs-check.md`).** `/` and `/home` are one ext4 partition (`/dev/nvme0n1p2`), with no reflink. Rollback on Rock Box therefore needs a full-copy shadow (the ext4 case above). A full-copy store on `/` shares space with the OS, so its disk cap must protect free space on `/`. A full-copy store may sit on another disk: the `EXDEV` same-filesystem limit applies only to clones. Store location and cap: **AJ decides.** (O22)

Notes:
- `ioctl_ficlone(2)` (https://man7.org/linux/man-pages/man2/ioctl_ficlone.2.html): the clone shares blocks until one side is written. Source and destination must be on the same filesystem (`EXDEV` if not). A filesystem that cannot reflink returns `EOPNOTSUPP`.
- XFS reflink is a format-time feature and shows as `reflink=1` in `xfs_info` (mkfs.xfs(8), https://man7.org/linux/man-pages/man8/mkfs.xfs.8.html).
- AJ's stage scope (§4, Stage 2) does not list rollback. Which stage builds it: **AJ decides.** (O22)
- File rollback on Johnny itself (brief Decision 5, `docs/architecture/architecture-pass.md:437-444`) was not decided. **AJ decides.** (O22)

#### Fix 3: In-kernel entropy sees about 4 KB per write and can be bypassed

**AJ decision (AJ, 2026-11-14):** In-kernel entropy samples only about 4 KB per write. It can be bypassed by intermittent (partial) encryption or by encoding (e.g. Base64). So it is paired with lineage / behavior context.

Notes:
- The repo's reference design shows the 4096-byte sample: "over a N=4096 byte sector buffer" (`docs/JOHNNY_ Executive Architectural Summary.md:55`), and the sketch `char sample[4096]` with the comment "Sample a 4KB chunk of the write buffer" (`docs/Security Software Architecture Overview.md:1028-1034`; `docs/BEGIN_Network_Security_Software_Enterprise.md:4386-4392`).
- The same sketch samples only when `count >= 4096` (`docs/Security Software Architecture Overview.md:1029`). A shorter write is not sampled at all. How short writes are handled: **AJ decides.** (O28)
- The reference design names the same bypass and the same answer: every k-th block or Base64 defeats block math, so the trigger is process state and behavior, not entropy alone (`docs/JOHNNY_ Executive Architectural Summary.md:167`).

#### Fix 4: The Windows kernel minifilter is a HARD GATE for Stage 4

**AJ decision (AJ, 2026-11-14):** The Windows kernel minifilter needs Microsoft signing (EV certificate, cost and paperwork) and its own altitude. So it is a HARD GATE for Stage 4.

Notes:
- No price is stated here.
- Microsoft pages that hold the current rules. These URLs are written from memory of well-known pages. They were not fetched in this session (no outbound contact was allowed). **Source to confirm** before Stage 4 entry:
  - Driver code signing requirements: https://learn.microsoft.com/en-us/windows-hardware/drivers/dashboard/code-signing-reqs
  - Driver signing policy: https://learn.microsoft.com/en-us/windows-hardware/drivers/install/kernel-mode-code-signing-policy--windows-vista-and-later-
  - Minifilter altitude request: https://learn.microsoft.com/en-us/windows-hardware/drivers/ifs/minifilter-altitude-request
  - Allocated filter altitudes: https://learn.microsoft.com/en-us/windows-hardware/drivers/ifs/allocated-altitudes
- Which Microsoft signing path is used, and who holds the EV certificate: **AJ decides.** (O30)

### 1.6 Adjustments

**AJ decision (AJ, 2026-11-14):**
- The "90%+ bandwidth reduction" is a TARGET, not a fact.
- Vendor driver altitudes (e.g. WRkrn.sys, Falcon) are references only.

Notes:
- Where the repo states the 90% figure: "compresses telemetry by >90%" (`docs/JOHNNY_ Executive Architectural Summary.md:7`); "by over 90%" (`docs/BEGIN_Network_Security_Software_Enterprise.md:4741`, `docs/Security Software Architecture Overview.md:1230`). Read each as a **Target**. Nothing in the repo measures it.
- Assumption: "Filters 99% of noise" (`docs/BEGIN_Network_Security_Software_Enterprise.md:4723`) is the same kind of unmeasured figure and gets the same treatment.
- Where the repo states vendor altitudes: 388360 for CrowdStrike and 320111 / 321611 for Webroot (`docs/Security Software Architecture Overview.md:637`, `:643`; `docs/BEGIN_Network_Security_Software_Enterprise.md:3816`, `:3823`). These numbers were not checked against Microsoft's list. Johnny's Windows driver gets its own altitude from Microsoft (fix 4).

### 1.7 Deferred (not rejected)

**AJ decision (AJ, 2026-11-14):** The items below are cut as overhead for a one-person build. They are DEFERRED, NOT REJECTED.

| # | Deferred item | Where the repo has it | What would bring it back |
|---|---|---|---|
| 1 | Formal verification tooling (e.g. TLA+ / LTL model checking, EverParse proofs) | `docs/JOHNNY_ Executive Architectural Summary.md:45`, `:68-75`; `docs/agent-team.md:55`, `:67`, `:125` | **AJ decides.** (O31) |
| 2 | YANG / NETCONF / OpenC2 schemas | OpenC2: `docs/JOHNNY_ Executive Architectural Summary.md:47`, `:126-158`; `docs/agent-team.md:73`. YANG / NETCONF: no repo source found (grep) | **AJ decides.** (O31) |
| 3 | ISO 27034 governance | `docs/JOHNNY_ Executive Architectural Summary.md:46` | **AJ decides.** (O31) |
| 4 | Wasm enclaves | no repo source found (grep) | **AJ decides.** (O31) |
| 5 | Merkle / TPM log chaining | no repo source found (grep) | **AJ decides.** (O31) |
| 6 | Multi-year tiered retention | no repo source found (grep). Today's retention is the reader's 200 GiB cap on Johnny (`docs/os-handoff.md:28`) | **AJ decides.** (O31) |

Notes:
- The three LTL safety properties stay as plain design statements (`docs/JOHNNY_ Executive Architectural Summary.md:70-75`). Only the tooling that would machine-check them is deferred.
- With OpenC2 schemas deferred, the message format for a response action is open. The brief's Item E and the Daemon's `openc2-actuator` skill both assume OpenC2 (`docs/architecture/architecture-pass.md:164`, `docs/agent-team.md:73`). **AJ decides.** (O32)

---

## 2. Map to the Brief

Brief = `docs/architecture/architecture-pass.md`. For open rows the brief's options still stand as written. They are not re-argued here.

### 2.1 Decisions 1–6

| Brief decision | Brief lines | Status | What rev 2 records | Still open |
|---|---|---|---|---|
| Decision 1: scope (Item C) | `:399-407` | **Decided** | §1.1, §1.4: hybrid. Option C-like scope, staged. Johnny stays the network sensor. Linux agents first, Windows in Stage 4. | Option B (host LSM on Johnny itself, `:403`). **AJ decides.** (O1) |
| Decision 2: containment path (Item E) | `:409-417` | **Still open** | Nothing. Stage 2's "network gating for Unknown processes" is on the endpoint, inside the agent. It does not touch the switch. | Options A–D at `:412-415`. **AJ decides.** (O20) |
| Decision 3: SLM role (Item A) | `:419-426` | **Decided** for authority. **Partly decided** for placement. | §1.5 fix 1: tighten or suggest only; loosening only by AJ-signed rules. §1.2 item 5: inference is a separate process, or on the MAX over gRPC. §1.3: async, off the hot path. | Whether any model runs on Johnny itself, its RAM budget (`README.md:25`), model choice. **AJ decides.** (O16) Signature scheme (**AJ-DECIDED 2026-11-17 9:01 PM CT**): minisign (Ed25519), verified in userspace before any map write. The private key is kept on a USB stick and on Rock Box, for now. AJ accepts that root on Rock Box can sign rules (kernel lockdown `none`, `docs/findings/stage2/2026-11-17-rockbox-lockdown.md`; Secure Boot on Rock Box assumed off, **UNVERIFIED**; AJ: "this isnt fort knox"); see the O25 note. AJ creates the key pair himself (agents create no keys, `docs/tool-install/stage1-rust-daemon-cutover.md:65-72`), with minisign's default password prompt (not `-W`). The public key may be committed; the private key never is. Key rotation is open. (O17) |
| Decision 4: verdict model (Item F) | `:428-435` | **Partly decided** | The AI cannot loosen (fix 1). **AJ-DECIDED 2026-11-17** (AJ, 7:59 PM CT: "follow claude recs"): K3 three-state for Stage 2 processes; Unknown = executable SHA-256 on neither the signed allow list nor the deny list; no promotion via the parent process; interpreters are a known gap (see O21). | Other transitions and who may make each transition; network entities. (The brief's Options A–C at `:431-433` are settled for Stage 2 processes by the K3 three-state decision.) **AJ decides.** (O21) |
| Decision 5: file rollback (Item D) | `:437-444` | **Partly decided** | §1.5 fix 2: rollback on Rock Box follows Rock Box's filesystem: **verified 2026-11-17** as one ext4 partition, no reflink, so full-copy shadow (`docs/findings/stage2/2026-11-17-rockbox-fs-check.md`). | Rollback on Johnny itself (Options A–C at `:440-442`); which stage builds rollback; shadow store location and disk cap. **AJ decides.** (O22) |
| Decision 6: upstream (Item B) | `:446-453` | **Partly decided** | §1.1: the backend is on the MAX. §1.2 item 11: logs go to the MAX over TLS 1.3. §1.2 item 5: AI calls use gRPC. | Client authentication (mTLS), WireGuard, certificate issuance, MLS / fleet keying, any cloud scope. Options A–C at `:449-451`. **AJ decides.** (O23) |

### 2.2 Items A–F

| Brief item | Brief lines | Status | See |
|---|---|---|---|
| Item A: SLM limits and autonomy | `:21-54` | **Decided** (authority); **partly decided** (placement) | Decision 3 row |
| Item B: Tier 1 / fleet / cloud | `:58-86` | **Partly decided** | Decision 6 row |
| Item C: endpoint vs network | `:90-123` | **Decided** | Decision 1 row |
| Item D: CoW filesystem | `:127-158` | **Partly decided** | Decision 5 row |
| Item E: quarantine path | `:162-198` | **Still open** | Decision 2 row |
| Item F: K3 verdict model | `:202-262` | **Still open** | Decision 4 row |

### 2.3 Code-shape questions (brief §4, `:334-353`)

| # | Question | Status | Answer recorded | Still open |
|---|---|---|---|---|
| 1 | Module boundaries (`:338-339`) | **Answered** | One lightweight deterministic sensor daemon. Control plane and data plane are separated inside it. AI inference is outside it. | How the split is kept inside one daemon. **AJ decides.** (O13) |
| 2 | Languages (`:340-341`) | **Answered** | C in-kernel for BPF. Rust for userspace. | AI inference process; Windows kernel driver. **AJ decides.** (O11) |
| 3 | Kernel-to-userspace BPF library (`:342-343`) | **Answered** (Stage 1) | **AJ decision (AJ, 2026-11-14 10:56 PM CT):** Use `aya` (`=0.16.0`, `default-features = false`) in userspace only (`crates/johnny-daemon/Cargo.toml:9`, `crates/johnny-daemon/src/bpf.rs:1-322`, with `attach` at `:235-277` and `probe` at `:283-322`). Attach to existing pinned maps (`m2_rb`, `m2_cfg`, `m2_ctl`) under `/sys/fs/bpf/johnny_m1s2b` (or load the existing compiled C object `docs/tool-install/module1-xdp-records.o` in userspace) without modifying the C BPF source, object, or pins. | Stage 2 BPF-LSM attachment mechanics on Rock Box. **AJ decides.** (O5) |
| 4 | Record schema evolution (`:344-345`) | **Answered** (Stage 1 v1) | **AJ decision (AJ, 2026-11-14 10:56 PM CT):** Freeze today's 80-byte `struct m2_rec` (`docs/tool-install/module1_xdp_records.c:133-165`) as implicit v1 across the kernel-to-userspace boundary, stamp `"version": 1` in userspace outputs (`crates/johnny-record-v1/src/lib.rs:25`, `crates/johnny-record-v1/src/record.rs:140-145`, `crates/johnny-daemon/src/control/status.rs:118`, `crates/johnny-daemon/src/bpf.rs:311`), and have readers ignore unknown versions or headers safely (`crates/johnny-record-v1/src/record.rs:83-86`, `crates/johnny-daemon/src/data/ring.rs:133-140`, `crates/johnny-record-v1/src/runfile.rs:130-145`). New fields and in-kernel binary header changes are deferred to v2. | v2 binary wire encoding when v2 opens. **AJ decides.** (O6) |
| 5 | Storage backend (`:346-347`) | **Open** | — | **AJ decides.** (O7) |
| 6 | Repo layout (`:348-349`) | **Answered** (Stage 1) | **AJ decision (AJ, 2026-11-14 10:56 PM CT):** `crates/` is a Cargo workspace next to `docs/` (`crates/Cargo.toml:1-15`) with a shared `johnny-record-v1` parser library crate (`crates/johnny-record-v1/`, reusable by the Stage 2 Rock Box agent) and a `johnny-daemon` binary crate (`crates/johnny-daemon/`). `docs/tool-install/johnny-m1s2b-reader.py` stays in place for fallback. | Where Stage 2–4 crates sit inside `crates/`. **AJ decides.** (O8) |
| 7 | Build, test, packaging (`:350-351`) | **Answered** (Stage 1) | **AJ decision (AJ, 2026-11-14 10:56 PM CT):** Plain Cargo builds (`crates/release.sh:1-146`). Release target emits a SHA-256 of the compiled Rust binary (`crates/dist/johnny-daemon.sha256`) and a CycloneDX SBOM (`crates/johnny-daemon.cdx.json`; `cargo-cyclonedx` is missing on Rock Box, documented at `crates/release.sh:3-5`, `:29-32` and `docs/tool-install/stage1-rust-daemon-cutover.md:28`, so `crates/release.sh:34-141` emits deterministic CycloneDX 1.5 JSON from `cargo metadata --locked --offline` + `crates/Cargo.lock` with tool name `cargo-metadata-lockfile`). Signing uses signed git tags (`git tag -s`), and AJ signs; no keys created by agents (`docs/tool-install/stage1-rust-daemon-cutover.md:65-72`). | Package format for Stage 2–4 fleet rollout. **AJ decides.** (O9) |
| 8 | Rule versioning and hot reload (`:352-353`) | **Answered** for the mechanism | Hot-reloadable rules: candidate / validate / commit, and rollback. | Rule format, what "validate" checks, what triggers rollback. **AJ decides.** (O10) |

### 2.4 Other parts of the brief

- **Brief §8 build order (`:457-482`)** is replaced by the stages in §4. Milestone 1 (Paste W) was originally Stage 1's first entry step and was ended early by AJ's choice on 2026-11-17 (~3 days from `2026-11-14 15:33 CT` to cutover, not 7; Paste W superseded, not passed; see `:307`). Milestone 3 (ring buffer consumer) is Stage 1 (applied 2026-11-17). Milestones 4–6 (K3 engine, ingress filtering, Suricata / Zeek) are not placed in a stage by AJ's decisions. **AJ decides.** (O24)
- **Brief §5 gaps (`:357-371`)**: the "Needs from AJ" cells in rows 2, 5, 6, 8, and 9 (detection engines, tamper resistance, threat-intel feeds, operator interface, test method) are not decided by rev 2. **AJ decides.** (O25)
- **Single Packet Authorization** (`:314-315`) is not decided. **AJ decides.** (O26)
- **Brief §6 lock-in risks 3–5** (switch write access, filesystem choice on Johnny, MLS) still stand as written (`:383-391`). Rev 2's own lock-in watch is §5.

---

## 3. Rock Box Read-Only Check (fix 2 and Stage 2 entry)

What it is: nine read-only lines for AJ to run on Rock Box, in a normal terminal. No sudo. No writes. No ssh. It does not touch Johnny, so the week-test hold does not apply to it.

Review state: **ran unreviewed.** AJ ran this exact block on Rock Box at ~5:04 PM CT 2026-11-17 before any adversarial review of it (`AGENTS.md:13`); no review record exists. The block is read-only, so there was no harm. Raw output: `docs/findings/stage2/2026-11-17-rockbox-fs-check.md`. Result: ext4 on one partition for `/` and `/home`, no reflink (full-copy shadow); `CONFIG_BPF_LSM=y` and `bpf` active.

***<u>Run on Rock Box</u>***

```bash
echo "== kernel"; uname -r
echo "== mount holding /"; findmnt -no SOURCE,FSTYPE,OPTIONS --target /
echo "== mount holding /home"; findmnt -no SOURCE,FSTYPE,OPTIONS --target /home
echo "== filesystem type of / and /home"; stat -f -c '%n %T' / /home
echo "== xfs reflink on /"; xfs_info / 2>/dev/null | grep -o 'reflink=[01]' || echo not-xfs-or-no-access
echo "== xfs reflink on /home"; xfs_info /home 2>/dev/null | grep -o 'reflink=[01]' || echo not-xfs-or-no-access
echo "== active LSM list"; cat /sys/kernel/security/lsm; echo
echo "== kernel config"; grep -E '^CONFIG_BPF_LSM=|^CONFIG_LSM=' "/boot/config-$(uname -r)" || echo CONFIG_BPF_LSM-not-found
echo ROCKBOX-FS-CHECK-DONE
```

What each line does, in plain words:

| Line | Plain meaning |
|---|---|
| `uname -r` | Prints the running kernel version. |
| `findmnt ... --target /` | Prints the device, filesystem type, and mount options of the filesystem that holds `/`. |
| `findmnt ... --target /home` | The same for the filesystem that holds `/home`. If the device is the same as for `/`, then `/home` is not a separate filesystem. |
| `stat -f -c '%n %T'` | Asks the kernel for the filesystem type of each path. A second opinion on the two lines above. |
| `xfs_info ... reflink` | On XFS, prints `reflink=1` or `reflink=0`. On anything else, prints `not-xfs-or-no-access`. |
| `cat /sys/kernel/security/lsm` | Prints the security modules that are active right now, as one comma-separated line. |
| `grep ... /boot/config-...` | Prints whether this kernel was built with BPF LSM, and the kernel's built-in default LSM order. |
| `echo ROCKBOX-FS-CHECK-DONE` | Means the block ran to the end. It is a "done" token, not a "pass" token. |

What each result would mean:

| Result | Meaning for rollback (fix 2) |
|---|---|
| Filesystem type is `btrfs` | The reflink / FICLONE path is available on that filesystem. |
| Type is `xfs` and `reflink=1` | The reflink / FICLONE path is available on that filesystem. |
| Type is `xfs` and `reflink=0` | No reflink. Full-copy shadow. |
| Type is `ext4` in `findmnt` (`stat` prints `ext2/ext3` for it) | No reflink. Full-copy shadow, per AJ's fix 2. |
| `/` and `/home` are on different filesystems | A clone cannot cross filesystems (`EXDEV`, https://man7.org/linux/man-pages/man2/ioctl_ficlone.2.html). The shadow store must sit on the same filesystem as the files it protects, or be a full copy. |
| `findmnt` says `xfs` but the reflink line says `not-xfs-or-no-access` | The check could not read the answer without sudo, or `/home` is not its own mount point (then use the `/` line). Assumption: `xfs_info` works without sudo on a mounted XFS. If it does not, a sudo line is drafted and reviewed as its own paste. |
| Any other type (for example zfs) | Not covered by AJ's fix 2. **AJ decides.** (O22) |

| Result | Meaning for BPF LSM (Stage 2 entry) |
|---|---|
| `CONFIG_BPF_LSM=y` and `bpf` is in the active LSM list | BPF LSM programs can attach on Rock Box (https://docs.kernel.org/bpf/bpf_lsm.html). The entry criterion is met. |
| `CONFIG_BPF_LSM=y` but `bpf` is not in the active list | The kernel can do it but it is not switched on. Turning it on needs a kernel command-line change and a reboot of Rock Box. That is its own reviewed paste. **AJ decides.** (O28) |
| No `CONFIG_BPF_LSM=y` line in the output (or `CONFIG_BPF_LSM-not-found`) | This kernel build has no BPF LSM, or its config file could not be read. Stage 2's exec-lineage hook needs another plan. **AJ decides.** (O28) |

The active list is the file `/sys/kernel/security/lsm` (https://docs.kernel.org/admin-guide/LSM/index.html).

What to send back: the whole output, ending in `ROCKBOX-FS-CHECK-DONE`.

Rollback: none needed. The block changes nothing.

---

## 4. Stages

The stages replace the brief's build order (`docs/architecture/architecture-pass.md:457-482`). Every threshold below is a **Target** until AJ sets it; only the Stage 1 cutover counters (`:307`, `:313`), the S1-4 retention properties (`:314`; its unit-sandbox check is a Rock Box test), and the Johnny `--summary` matches in S1-3 and S1-5 (`:312`) are measured on Johnny (run-file byte parity at `:312` is a Rock Box fixture result), while Stages 2–4 figures remain unmeasured.

### Stage 1: Rust userspace daemon on Johnny (APPLIED 2026-11-17)

**Goal.** A Rust daemon on Johnny replaces the Python reader as the consumer of the existing ring buffer. The kernel side does not change. **Status: APPLIED AND VERIFIED ON JOHNNY 2026-11-17** (PR #42 build, merge `c23ea4f`; `S1-1..S1-5` passed; `johnny-daemon.service` `enabled`/`active`, `johnny-m1s2b-reader.service` `disabled`/`inactive` with files kept on disk for rollback; `docs/os-handoff.md` rev 119, `docs/sessions/2026-11-17-stage1-cutover-applied.md`).

**AJ Stage 1 Decisions (AJ, 2026-11-14 10:56 PM CT):**
1. **Userspace BPF attachment (`aya`, O5):** Use `aya` (`=0.16.0`, `default-features = false`) in userspace only (`crates/johnny-daemon/Cargo.toml:9`, `crates/johnny-daemon/src/bpf.rs:1-322`, with `attach` at `:235-277` and `probe` at `:283-322`). Attach to the existing pinned maps and ring `m2_rb` under `/sys/fs/bpf/johnny_m1s2b` (or load the existing compiled C object `docs/tool-install/module1-xdp-records.o` in userspace without modifying kernel probes). Never modify the C BPF source (`docs/tool-install/module1_xdp_records.c`), compiled C object (`docs/tool-install/module1-xdp-records.o`), or any live pins or hashes.
2. **Implicit v1 wire contract (`struct m2_rec`, O6):** Freeze today's 80-byte `struct m2_rec` (`docs/tool-install/module1_xdp_records.c:133-165`) as implicit v1 across the kernel-to-userspace boundary, and stamp `"version": 1` in userspace outputs (`crates/johnny-record-v1/src/lib.rs:25`, `crates/johnny-record-v1/src/record.rs:140-145`, `crates/johnny-daemon/src/control/status.rs:118`, `crates/johnny-daemon/src/bpf.rs:311`). New fields and in-kernel binary header changes come only in v2 (deferred). Readers ignore unknown versions or headers safely (`crates/johnny-record-v1/src/record.rs:83-86`, `crates/johnny-daemon/src/data/ring.rs:133-140`, `crates/johnny-record-v1/src/runfile.rs:130-145`).
3. **Cargo workspace (`crates/`, O8):** `crates/` is a Cargo workspace next to `docs/` (`crates/Cargo.toml:1-15`) containing the shared `johnny-record-v1` parser library crate (`crates/johnny-record-v1/`, `#![forbid(unsafe_code)]`, reusable by the Stage 2 Rock Box agent) and the `johnny-daemon` binary crate (`crates/johnny-daemon/`). `docs/tool-install/johnny-m1s2b-reader.py` stays in place untouched for fallback/rollback.
4. **Plain Cargo builds, SHA-256, CycloneDX SBOM, and AJ-signed tags (O9):** Build with plain Cargo (`crates/release.sh:1-146`), emitting a SHA-256 hash of the compiled Rust release binary (`crates/dist/johnny-daemon.sha256`) and a CycloneDX 1.5 SBOM (`crates/johnny-daemon.cdx.json`; `cargo-cyclonedx` is not installed on Rock Box, documented at `crates/release.sh:3-5`, `:29-32` and `docs/tool-install/stage1-rust-daemon-cutover.md:28`). Release signing uses AJ-signed git tags (`git tag -s`); agents never create signing keys (`docs/tool-install/stage1-rust-daemon-cutover.md:65-72`).

**Scope & Deliverables (APPLIED on Johnny 2026-11-17, PR #42 build, merge `c23ea4f`):**
- Consumes ring `m2_rb` (`docs/tool-install/module1_xdp_records.c:218-221`), which the existing C program `j_xdp_records` fills (`docs/architecture/architecture-pass.md:11`). The pinned BPF object is not rebuilt.
- Reads the documented record: 80 bytes, `struct m2_rec`, version byte first (`docs/tool-install/module1_xdp_records.c:133-165`, `:78`; `crates/johnny-record-v1/src/record.rs:31-108`).
- Writes the documented run file: a 96-byte header, then 80-byte records (`docs/tool-install/johnny-m1s2b-reader.py:58-63`, `:42-43`; `crates/johnny-record-v1/src/runfile.rs:69-166`), with live rotation (`1 GiB` / `3600 s`) and retention (`keep=200`, `dir-cap=200 GiB`, `reserve=100 GiB`) limits configured in `etc/systemd/system/johnny-daemon.service:16` (binary CLI defaults match the Python reader's defaults at `crates/johnny-daemon/src/control/config.rs:15-24`, `:72-88`; bounds validated at `crates/johnny-daemon/src/control/config.rs:100-124` and enforced by `crates/johnny-daemon/src/control/policy.rs:28-79` and `crates/johnny-daemon/src/data/writer.rs:78-265`).
- Follows §1.2: one daemon with control plane (`crates/johnny-daemon/src/control/` — `config.rs:1-246` Policy Administrator bounds validation, `policy.rs:1-92` pure Policy Engine for rotate/keep/dir-cap/low-disk decisions, `status.rs:1-244` `"version": 1` event logger; there is no rule candidate/validate/commit/rollback store in this commit) and data plane (`crates/johnny-daemon/src/data/` — `mod.rs:15-23` `KernelMaps` trait, `ring.rs:1-152` `Ring` consumer, `synth.rs:1-127` test-only `SynthRing`, `writer.rs:1-265` `RotatingWriter`) separated inside it (`crates/johnny-daemon/src/daemon.rs:1-128`).
- Systemd unit `etc/systemd/system/johnny-daemon.service` (SHA-256 `e3c8df9c8c2fd225bffaf83701f4d39d1a4d74918fe4e236d540058de35dbffa`, installed, `enabled`, and `active` on Johnny since 2026-11-17 ~3:30 PM CT with binary `/usr/local/libexec/johnny/johnny-daemon` SHA-256 `08e96c19b83edc6662684d0c4a7902675def5837a769d1592f06dc082c1681ac`) matches every sandbox directive of `etc/systemd/system/johnny-m1s2b-reader.service` (`crates/johnny-daemon/tests/parity.rs:664-713`).
- Cutover/rollback runbook `docs/tool-install/stage1-rust-daemon-cutover.md` (APPLIED 2026-11-17 via Pastes S1-1..S1-5; historical `DO NOT RUN BEFORE PASTE W (after 2026-11-21 15:33 CT / 21:33Z)` banner retained for test audit, superseded by AJ's choice), keeping the Python reader (`johnny-m1s2b-reader.service` `disabled`/`inactive`, files kept on disk) as rollback.
- Not in Stage 1: any BPF change, any LSM hook, any AI, any stream to the MAX, any database.

**Entry criteria.**
1. Paste W hold (originally after 2026-11-21 15:33 CT / 21:33Z, `docs/tool-install/module1-slice2b-boot-unit.md:583-601`) was ended early and superseded by AJ's choice on 2026-11-17 (~3 days from `2026-11-14 15:33 CT` to cutover, not 7; Paste C at `20:27Z` printed `M1S2B-NORC-VERIFY-DONE` with `window-60 seen-delta=26416` and zero drops, and `BASELINE CTL rate_limited 18217138` had `0` new `rate_limited` from baseline `2026-11-14T21:32:11Z` to cutover). No longer the gate.
2. **Answered (AJ, 2026-11-14 10:56 PM CT):** AJ answered the four Stage 1 code-shape items: `aya` in userspace only (O5), implicit v1 80-byte `struct m2_rec` with `"version": 1` stamped in userspace outputs and unknown versions/headers safely handled (O6), `crates/` Cargo workspace with `johnny-record-v1` + `johnny-daemon` (O8), and plain Cargo builds + SHA-256 + CycloneDX SBOM + AJ-signed git tags (O9).
3. The draft and every paste in `docs/tool-install/stage1-rust-daemon-cutover.md` are reviewed by the adversarial-reviewer before AJ runs anything (`AGENTS.md:13`).

**Exit criteria.** Targets. Thresholds: **AJ decides.** (O27)
1. **Target (byte-for-byte run-file parity proven on Rock Box fixtures; `--summary` parity proven on Johnny 2026-11-17 in S1-3 and S1-5):** byte-for-byte run-file parity and `--summary` parity with `docs/tool-install/johnny-m1s2b-reader.py` on synthetic ring + recorded fixtures (`crates/johnny-daemon/tests/parity.rs:243-460`), and `--summary` parity on Johnny live snapshots in S1-3 and S1-5 (`docs/tool-install/stage1-rust-daemon-cutover.md:145`, `:228`; `STAGE1-PROBE-INSTALL-DONE`, `STAGE1-VERIFY-DONE`).
2. **Target (proven on Johnny 2026-11-17 in S1-5):** on Johnny, zero drops over an AJ-chosen window (`WINDOW secs=60 seen-delta=17087 rate_limited-delta=0 rb_full-delta=0 discarded-delta=0 emitted-delta=17087 pkts-delta=17088`, `OK-no-drops-window`, `STAGE1-VERIFY-DONE`; `docs/tool-install/stage1-rust-daemon-cutover.md:216`). "Drops" are the counters the existing checks stop on: `rate_limited`, `rb_full`, `discarded` (`docs/os-handoff.md:11, 64, 82`, `docs/tool-install/module1-slice2b-boot-unit.md:679-680`). The window length is AJ's call.
3. **Target (proven on Johnny 2026-11-17 in S1-4):** the same retention limits as today (`etc/systemd/system/johnny-daemon.service:16`, `docs/os-handoff.md:10, 72`), and a unit sandbox no weaker than the current reader unit's (`etc/systemd/system/johnny-daemon.service`, verified by `crates/johnny-daemon/tests/parity.rs:664-713`).
4. **Target:** switching back to the Python reader (`docs/tool-install/stage1-rust-daemon-cutover.md:349-377`) remains available with the Python reader files kept on disk (`476cf867...`, unit `e5c16249...`).
5. The Python reader is kept as rollback until AJ retires it.

**What stays easy to change.**
- The daemon is userspace only. The BPF object, the maps, and the pins are untouched, so going back is a unit switch (`docs/tool-install/stage1-rust-daemon-cutover.md:349-377`).
- The file format does not change in Stage 1, so every older run file stays readable by both readers (`crates/johnny-daemon/tests/parity.rs:243-460`).
- Assumption: only one process drains a BPF ring at a time (one consumer position; https://docs.kernel.org/bpf/ringbuf.html, to confirm). So the two readers are swapped, not run side by side. The earlier cutover had a few-second capture gap (`docs/tool-install/module1-slice2b-boot-unit.md:25`).
- The `aya` crate is isolated in `crates/johnny-daemon/src/bpf.rs:1-322` (imported only at `:28`; `attach` at `:235-277`, `probe` at `:283-322`), and the data plane talks to map pins through the `KernelMaps` trait (`crates/johnny-daemon/src/data/mod.rs:15-23`; `Ring` consumer at `crates/johnny-daemon/src/data/ring.rs:24-152`), so the BPF attachment layer can be swapped later without touching `johnny-record-v1` or `RotatingWriter` (`crates/johnny-daemon/src/data/writer.rs:78-265`).

**Open items.** O13 (beyond Stage 1's single-process `src/control/` and `src/data/` module boundary wired in `src/daemon.rs:70-128`), O27 remainder (what "parity" means, Python reader retirement date; the window is decided, see Stage 2 entry 1 and §7 O27). **AJ decides.**

### Stage 2: Rock Box Linux agent

**Goal.** The first endpoint agent, on Rock Box. Linux first (§1.4).

**Scope.** As AJ gave it:
- BPF-LSM exec lineage. Reference design: `docs/JOHNNY_ Executive Architectural Summary.md:33-36`.
- `vfs_write` sampling, about 4 KB per write, paired with lineage / behavior context (fix 3).
- Network gating for Unknown processes. Reference design: `docs/JOHNNY_ Executive Architectural Summary.md:70-71`, `:164`.
- Signed-rule exceptions (fix 1): a loosening exists only as a rule signed by AJ.

Rollback is not in AJ's Stage 2 scope list. Its mechanism follows fix 2. Which stage builds it: **AJ decides.** (O22)

**Entry criteria.**
1. Stage 1 exit. **AJ-DECIDED 2026-11-17** (AJ, 7:59 PM CT: "follow claude recs") (O27 = B): Stages 1 and 2 overlap. Stage 2 may start now; Stage 1 exits after a longer zero-drop window set by AJ. Window: **AJ-DECIDED 2026-11-17 9:01 PM CT** (option A; B and C declined): Stage 1 exits when Paste S1-6 (`docs/tool-install/stage1-rust-daemon-cutover.md`, read-only, run after **2026-11-21 15:33 CT**, about 4 days on the Rust daemon, no reboot) passes: `rate_limited`, `rb_full`, and `discarded` unchanged from the cutover baseline (`docs/sessions/2026-11-17-stage1-cutover-applied.md:36`). The date alone does not exit Stage 1. Open gap AJ accepted with window A: no cold boot has been tested under the Rust daemon.
2. The Rock Box filesystem check (§3) has been run and its output is recorded in the repo (fix 2). **Met 2026-11-17** (`docs/findings/stage2/2026-11-17-rockbox-fs-check.md`): one ext4 partition for `/` and `/home`, no reflink, so full-copy shadow.
3. BPF LSM availability on Rock Box has been checked read-only: `CONFIG_BPF_LSM` in the kernel config, and `bpf` in the active LSM list (https://docs.kernel.org/bpf/bpf_lsm.html). The same §3 block covers it. **Met 2026-11-17** (`docs/findings/stage2/2026-11-17-rockbox-fs-check.md`): `CONFIG_BPF_LSM=y` and `bpf` is in the active list `lockdown,capability,landlock,yama,apparmor,bpf,ima,evm`. No kernel command-line change or reboot is needed for BPF LSM.
4. The signature scheme for AJ-signed rules (O17) and enough of the verdict model to define "Unknown" (O21) are answered before agent code is written. **AJ-DECIDED 2026-11-17** (AJ, 7:59 PM CT: "follow claude recs"): O17 (**AJ-DECIDED 2026-11-17 9:01 PM CT**) = minisign (Ed25519), verified in userspace before any map write. The private key is kept on a USB stick and on Rock Box, for now. AJ accepts that root on Rock Box can sign rules (kernel lockdown `none`, `docs/findings/stage2/2026-11-17-rockbox-lockdown.md`; Secure Boot on Rock Box assumed off, **UNVERIFIED**; AJ: "this isnt fort knox"); see the O25 note. AJ creates the key pair himself (agents create no keys, `docs/tool-install/stage1-rust-daemon-cutover.md:65-72`), with minisign's default password prompt (not `-W`). The public key may be committed; the private key never is. Key rotation is open.; O21 = K3 three-state; Unknown = the executable's SHA-256 is on neither the signed allow list nor the deny list (see §7).

Fast Path read-only item (not an entry gate): kernel lockdown on Rock Box is `none` (`cat /sys/kernel/security/lockdown` → `[none] integrity confidentiality`, AJ ~7:58 PM CT 2026-11-17, `docs/findings/stage2/2026-11-17-rockbox-lockdown.md`), so lockdown does not limit BPF kernel reads.

**Exit criteria.** Targets. Thresholds: **AJ decides.** (O28)
1. **Target:** exec lineage is recorded for processes started during an AJ-chosen test.
2. **Target:** write sampling runs with an overhead AJ accepts. The overhead is measured, not assumed.
3. **Target:** a test process in the Unknown state is gated from the network, and an AJ-signed rule lifts the gate. An unsigned or wrongly signed rule does not.
4. **Target:** a rule change goes candidate / validate / commit, and a rollback of that change is proven.
5. **Target:** no AI is needed for any of the above.

**What stays easy to change.**
- Thresholds live in maps and rules, not in compiled code, so they change by rule reload.
- **Target:** each hook (exec, write, network) is its own BPF program, so one can be removed without the others.
- **Target:** the rollback store sits behind one interface, so reflink and full-copy are interchangeable. The §3 result (2026-11-17) is one ext4 partition with no reflink, so full-copy is the backend Rock Box can use today.
- Rock Box is AJ's workstation. It also hosts the relay bot and the DMT Console (`AGENTS.md:11`, `docs/os-handoff.md:320`), and every Johnny paste is typed there. Observe-only vs enforcing: **AJ-DECIDED 2026-11-17** (AJ, 7:59 PM CT: "follow claude recs") (O28 = C): observe-only (log, do not deny), which cannot cut those off, except one enforcing test cgroup. Whether BPF LSM can scope a check to a cgroup is **UNVERIFIED**; a Fast Path test must confirm it before any enforcement. (O28)

**Open items.** O2, O10, O12, O18, O22, plus the remainders of O17 (key rotation), O21 (other transitions and authority, network entities), and O28 (exit thresholds, writes shorter than 4096 bytes). Ed25519 with minisign, K3, and observe-only-plus-one-test-cgroup are decided (2026-11-17). **AJ decides.**

### Stage 3: MAX backend + AI service

**Goal.** The CrowdStrike-style backend on the MAX (§1.1), and the AI service.

**Scope.** As AJ gave it:
- gRPC between the sensors and the AI service.
- An RTA monitor around the AI.
- Async triage, off the hot path (§1.3).
- The AI tightens or suggests only (fix 1).
- Logs stream to the MAX over TLS 1.3.

**Entry criteria.**
1. Stage 2 exit, or AJ decides to overlap Stage 3 with Stage 2. **AJ decides.** (O29)
2. Assumption: three open items must be answered before backend code is written: the MAX's host record (O4), the storage backend (O7), and the rest of the upstream transport decision (O23). **AJ decides.**

**Exit criteria.** Targets. Thresholds: **AJ decides.** (O29)
1. **Target:** logs from Johnny and from the Rock Box agent arrive on the MAX over TLS 1.3 and are stored.
2. **Target:** the AI service answers over gRPC, and every answer passes through the RTA monitor.
3. **Target:** an AI output that would loosen anything is refused, and the refusal is logged.
4. **Target:** with the MAX or the AI switched off, Johnny and the agent keep working. They buffer or drop logs by a stated rule.
5. **Target:** the bandwidth saving from triage is measured against raw streaming. The "90%+" figure stays a Target until then (§1.6).

**What stays easy to change.**
- The AI is a separate process behind gRPC. The model or its runtime can be swapped without touching a sensor.
- The sensors do not wait on the AI (async, off the hot path), so the AI service can be down, moved, or replaced.
- The RTA monitor bounds what any model may output, so trust does not depend on which model is loaded.

**Open items.** O4, O7, O11, O14, O15, O16, O19, O23, O29. **AJ decides.**

### Stage 4: Windows agent on ABLETON_BOX

**Goal.** A Windows endpoint agent on ABLETON_BOX (§1.4), behind the signing gate (fix 4).

**Scope.**
- A Windows kernel minifilter with Microsoft signing and its own altitude (fix 4).
- A userspace agent in Rust (§1.2 item 4). Assumption: it speaks the same record and gRPC contracts as the Linux agent.
- Vendor altitudes in the repo are references only (§1.6).

**Entry criteria.**
1. **HARD GATE:** the EV certificate, the Microsoft signing path, and the altitude are in hand (fix 4). No Stage 4 work starts before this.
2. Stage 3 exit. Assumption: Stage 4 follows Stage 3, because the agent reports to the backend. **AJ decides.** (O30)
3. ABLETON_BOX's records are reconciled with a Windows role (O3). **AJ decides.**

**Exit criteria.** Targets. Thresholds: **AJ decides.** (O30)
1. **Target:** the signed driver loads on ABLETON_BOX at its own altitude with Windows driver-signature enforcement on.
2. **Target:** the Windows agent's records arrive on the MAX in the same contract as the Linux agent's.
3. **Target:** fix 1 holds on Windows as on Linux: a loosening needs an AJ-signed rule.

**What stays easy to change.**
- Until the gate passes, nothing Windows-specific is built, so nothing is sunk.
- The record contract and the gRPC contract are OS-neutral (§5), so the backend does not change for Windows.

**Open items.** O3, O11, O30. **AJ decides.**

---

## 5. Lock-In Watch (rev 2)

Four choices that get expensive to undo, and how each stays easy to change. Brief §6 risks 3–5 still stand (`docs/architecture/architecture-pass.md:383-391`).

| # | Choice | What is fixed today | How it stays easy to change |
|---|---|---|---|
| 1 | Record format and version field | Record v1 is 80 bytes with the version in byte 0 (`docs/tool-install/module1_xdp_records.c:133-134`, `:78`). The run-file header carries its own version, the record size, and the record version (`docs/tool-install/johnny-m1s2b-reader.py:58-63`). Today's Python reader stops on any other version or size (`docs/tool-install/johnny-m1s2b-reader.py:128-129`, `:602-603`). That is stricter than AJ's rule. | AJ's rule: a version in every record; readers ignore unknown fields. **Target:** v1 stays readable forever; a new field means a new version, never a silent change to v1. **Target:** only one module converts raw records, so storage and the backend never depend on the struct layout. The encoding is open (O6). **AJ decides.** |
| 2 | Kernel-to-userspace map layout | `m2_cfg` has a version field and falls back to compiled defaults when it does not match (`docs/tool-install/module1_xdp_records.c:82`, `:167-174`). Sizes and offsets are pinned by compile-time asserts on the C side (`:156-165`). | **Target:** shared layouts are defined in one place with size checks on both sides (`docs/agent-team.md:52`). **Target:** a layout change is a new map under a new pin name, with the old one kept until the reader moves. The crate choice is open (O5). **AJ decides.** |
| 3 | gRPC / proto contract | Nothing exists yet. | **Target:** the contract carries a version; changes are additive; receivers ignore unknown fields (AJ's rule, §1.2 item 7). Sensors never block on the AI service, so the contract can be replaced without stopping capture. The contract itself is open (O15). **AJ decides.** |
| 4 | Signing keys | Nothing exists yet. Three separate jobs need a key: AJ's rule signing (fix 1), build signing (§1.2 item 10), and the Microsoft driver identity (fix 4). | **Target:** every signature names its key and its algorithm, and verifiers accept a set of keys, so a key can be rotated or the scheme replaced. **Target:** one key per job, never shared. Rule-signing scheme (**AJ-DECIDED 2026-11-17 9:01 PM CT**, O17): minisign (Ed25519), verified in userspace before any map write. The private key is kept on a USB stick and on Rock Box, for now. AJ accepts that root on Rock Box can sign rules (kernel lockdown `none`, `docs/findings/stage2/2026-11-17-rockbox-lockdown.md`; Secure Boot on Rock Box assumed off, **UNVERIFIED**; AJ: "this isnt fort knox"); see the O25 note. AJ creates the key pair himself (agents create no keys, `docs/tool-install/stage1-rust-daemon-cutover.md:65-72`), with minisign's default password prompt (not `-W`). The public key may be committed; the private key never is. Key rotation is open. **AJ decides** (rotation). |

---

## 6. Repo Lines That Fix 1 Supersedes

Edited in this commit:

| File | Change |
|---|---|
| `README.md:26` | "full function for now" replaced by AJ's 2026-11-14 decision. |
| `AGENTS.md:20` | Same. |
| `docs/agent-team.md:260-261` | Status line added under §7.2. Lines added under §7.3–§7.7 as well. |

Not edited in this commit (outside the task's edit list). Each is superseded by fix 1. Whether and when to edit them: **AJ decides.** (O33)

| File | Line says |
|---|---|
| `docs/agent-team.md:85` | `runtime-control`: thresholds "tighter or looser (full function for now)". |
| `docs/os-handoff.md:334` | "On-box SLM: yes, full function for now". |
| `.claude/agents/slm.md:30`, `:41` | Same `runtime-control` text; "has full function for now". |
| `.claude/agents/daemon.md:41` | "Apply its changes; don't filter them." |
| `.claude/agents/architect.md:42` | "Don't design limits into it." |

The older session notes under `docs/sessions/` that say the same are historical and stay as written.

---

## 7. Every Open Item

Each line below is **AJ decides.**

Scope and hosts:
- **O1.** Host LSM self-protection on Johnny itself (brief Decision 1 Option B, `docs/architecture/architecture-pass.md:403`). **AJ decides.**
- **O2.** Which Linux hosts get an agent after Rock Box, and in what order. **AJ decides.**
- **O3.** ABLETON_BOX: reconcile "gets a new OS, role not decided" (`docs/hosts/ableton_box.md:3`) and the parked Ubuntu option (`docs/os-handoff.md:403-405`) with a Windows agent in Stage 4. **AJ decides.**
- **O4.** The MAX: host record (hardware, OS, address), and how the parked Security Onion pattern (`docs/os-handoff.md:404`) relates to "backend on the MAX". **AJ decides.**

Code shape:
- **O5.** **Decided for Stage 1 (AJ, 2026-11-14 10:56 PM CT):** `aya` (`=0.16.0`, `default-features = false`) in userspace only (`crates/johnny-daemon/Cargo.toml:9`), attaching to existing pinned maps (`m2_rb`, `m2_cfg`, `m2_ctl`) in `crates/johnny-daemon/src/bpf.rs:1-322` (`attach` at `:235-277`, `probe` at `:283-322`) or loading the existing compiled C object in userspace. Still open for Stage 2: whether Stage 2's Rock Box BPF-LSM loader also uses `aya` or pre-compiled C objects. **AJ decides.**
- **O6.** **Decided for Stage 1 v1 (AJ, 2026-11-14 10:56 PM CT):** freeze today's 80-byte `struct m2_rec` as implicit v1, stamp `"version": 1` in userspace outputs (`crates/johnny-record-v1/src/lib.rs:25`, `crates/johnny-daemon/src/control/status.rs:118`), safely skip unknown versions and reject unknown headers in readers (`crates/johnny-record-v1/src/record.rs:83-86`, `crates/johnny-daemon/src/data/ring.rs:133-140`, `crates/johnny-record-v1/src/runfile.rs:130-145`), and defer new fields / in-kernel binary header changes to v2. Still open for v2: the v2 wire encoding. **AJ decides.**
- **O7.** Storage backend and how retention is enforced (brief §4 question 5). **AJ decides.**
- **O8.** **Decided for Stage 1 (AJ, 2026-11-14 10:56 PM CT):** `crates/` Cargo workspace next to `docs/` with `johnny-record-v1` (shared parser library crate) and `johnny-daemon` (binary crate), leaving `docs/tool-install/johnny-m1s2b-reader.py` in place (`crates/Cargo.toml:1-15`). Still open: Stage 2–4 crate names inside `crates/`. **AJ decides.**
- **O9.** **Decided for Stage 1 (AJ, 2026-11-14 10:56 PM CT):** plain Cargo builds (`crates/release.sh:1-146`), emitting SHA-256 of the compiled Rust binary (`crates/dist/johnny-daemon.sha256`) and a CycloneDX SBOM (`crates/johnny-daemon.cdx.json`), with release signing via AJ-signed git tags (`git tag -s`, `docs/tool-install/stage1-rust-daemon-cutover.md:65-72`). Still open for Stage 2–4: fleet package format. **AJ decides.**
- **O10.** Rule format, what "validate" checks, and what triggers a rollback (rest of brief §4 question 8). **AJ decides.**
- **O11.** Language of the AI inference process and of the Windows kernel driver. **AJ decides.**
- **O12.** The LPM-trie block map: which program holds it, what it blocks, who may write it. **AJ decides.**
- **O13.** How the control plane and data plane are kept apart inside one daemon once multi-threaded/async gRPC arrives in Stage 2–3 (in Stage 1 they are separated as `crates/johnny-daemon/src/control/` and `crates/johnny-daemon/src/data/` inside the single-threaded deterministic loop at `crates/johnny-daemon/src/daemon.rs:25-128`). **AJ decides.**
- **O14.** The RTA monitor: what it checks and what the fallback is. **AJ decides.**
- **O15.** The gRPC contract, and for each host whether the AI is a local process or on the MAX. **AJ decides.**

AI:
- **O16.** Whether any model runs on Johnny itself, its RAM budget (`README.md:25`), and the model. **AJ decides.**
- **O17.** Signature scheme for AJ-signed rules; where the private key lives; which component verifies; key rotation. **AJ-DECIDED 2026-11-17 9:01 PM CT**: minisign (Ed25519), verified in userspace before any map write. The private key is kept on a USB stick and on Rock Box, for now. AJ accepts that root on Rock Box can sign rules (kernel lockdown `none`, `docs/findings/stage2/2026-11-17-rockbox-lockdown.md`; Secure Boot on Rock Box assumed off, **UNVERIFIED**; AJ: "this isnt fort knox"); see the O25 note. AJ creates the key pair himself (agents create no keys, `docs/tool-install/stage1-rust-daemon-cutover.md:65-72`), with minisign's default password prompt (not `-W`). The public key may be committed; the private key never is. Key rotation is open. **AJ decides** (rotation).
- **O18.** The written definition of "tighten" and "loosen" for each threshold and each verdict transition. **AJ decides.**
- **O19.** Where an AI "suggest" goes and how AJ sees it. **AJ decides.**

Brief decisions still open:
- **O20.** Decision 2 / Item E: the quarantine path (`docs/architecture/architecture-pass.md:409-417`). **AJ decides.**
- **O21.** Decision 4 / Item F: verdict model states, transitions, and authority (`docs/architecture/architecture-pass.md:428-435`). **AJ-DECIDED 2026-11-17** (AJ, 7:59 PM CT: "follow claude recs"): K3 three-state. Unknown = the executable's SHA-256 is on neither the signed allow list nor the deny list. No promotion via the parent process. Interpreters (`python3`, `bash`, etc.) are a known gap: acceptable while observe-only; a plan is required before enforcing. Still open: other transitions and who may make them; network entities. **AJ decides.**
- **O22.** Decision 5 / Item D: file rollback on Johnny itself (`docs/architecture/architecture-pass.md:437-444`); which stage builds rollback on Rock Box; shadow store location and disk cap (Rock Box is one ext4 partition with no reflink, so full copies: a store on `/` shares space with the OS and its cap must protect free space on `/`; a store may sit on another disk, since `EXDEV` limits only clones; `docs/findings/stage2/2026-11-17-rockbox-fs-check.md`); what to do on a filesystem fix 2 does not name. **AJ decides.**
- **O23.** Decision 6 / Item B beyond TLS 1.3 logs: client authentication, WireGuard, certificate issuance, MLS / fleet keying, any cloud scope (`docs/architecture/architecture-pass.md:446-453`). **AJ decides.**
- **O24.** Where the brief's milestones 4–6 go (K3 engine, ingress filtering, Suricata / Zeek; `docs/architecture/architecture-pass.md:471-479`). **AJ decides.**
- **O25.** Brief §5 "Needs from AJ" rows 2, 5, 6, 8, 9: detection engines, tamper resistance, threat-intel feeds, operator interface, test method (`docs/architecture/architecture-pass.md:364`, `:367`, `:368`, `:370`, `:371`). Note (tamper resistance, 2026-11-17): kernel lockdown on Rock Box is `none` (`docs/findings/stage2/2026-11-17-rockbox-lockdown.md`), so root can change the kernel and the agent. **AJ decides.**
- **O26.** Single Packet Authorization (`docs/architecture/architecture-pass.md:314-315`). **AJ decides.**

Stage thresholds:
- **O27.** Stage 1: what "parity" means, the zero-drop window length, and when the Python reader is retired. **AJ-DECIDED 2026-11-17** (AJ, 7:59 PM CT: "follow claude recs") (= B): Stages 1 and 2 overlap; Stage 2 may start now; Stage 1 exits after a longer zero-drop window set by AJ. Window: **AJ-DECIDED 2026-11-17 9:01 PM CT** (= A; B and C declined): Stage 1 exits when Paste S1-6 passes after 2026-11-21 15:33 CT (about 4 days on the Rust daemon, no reboot): `rate_limited`, `rb_full`, `discarded` unchanged from the cutover baseline. Open gap AJ accepted with window A: no cold boot tested under the Rust daemon. Still open: what "parity" means, Python reader retirement. **AJ decides.**
- **O28.** Stage 2: exit thresholds; observe-only or enforcing from the start; how writes shorter than 4096 bytes are handled. **AJ-DECIDED 2026-11-17** (AJ, 7:59 PM CT: "follow claude recs") (= C): observe-only, except one enforcing test cgroup; whether BPF LSM can scope a check to a cgroup is **UNVERIFIED** and a Fast Path test must confirm it before any enforcement. Still open: exit thresholds, writes shorter than 4096 bytes. (BPF LSM is active on Rock Box as of 2026-11-17, `docs/findings/stage2/2026-11-17-rockbox-fs-check.md`, so the not-active fallback is moot unless that changes.) **AJ decides.**
- **O29.** Stage 3: exit thresholds; whether it overlaps Stage 2; how the "90%+" Target is measured. **AJ decides.**
- **O30.** Stage 4: exit thresholds; the Microsoft signing path; who holds the EV certificate; whether Stage 4 waits for Stage 3. **AJ decides.**

Deferred and housekeeping:
- **O31.** What would bring back each of the six deferred items (§1.7). **AJ decides.**
- **O32.** The response-action message format, now that OpenC2 schemas are deferred. **AJ decides.**
- **O33.** Editing the remaining "full function" lines (§6). **AJ decides.**
- **O34.** The four Microsoft URLs in fix 4 are **source to confirm**; who confirms them and when. **AJ decides.**

---

## 8. Sources

### Repository

Line numbers are as of this commit. `docs/os-handoff.md` gained an 11-line rev 116 section at the top, so handoff line numbers quoted inside the brief are 11 lower than today's. The brief's own line numbers did not move.

- `docs/architecture/architecture-pass.md`: the decision brief (rev 3) that this file supersedes for decided items.
- `docs/JOHNNY_ Executive Architectural Summary.md`: reference design (tiers, K3, 4096-byte sample, risk table).
- `docs/BEGIN_Network_Security_Software_Enterprise.md`: Webroot / CrowdStrike analysis; the relax example; the 90% figure.
- `docs/Security Software Architecture Overview.md`: the `vfs_write` sample sketch; vendor altitudes.
- `docs/agent-team.md`: roster, skills, §7 source conflicts.
- `README.md`, `AGENTS.md`: project rules and design decisions.
- `docs/os-handoff.md`: current state on Johnny; parked items.
- `docs/network-map.md`: cabling and hosts.
- `docs/hosts/ableton_box.md`: ABLETON_BOX hardware record.
- `docs/tool-install/module1-slice2b-boot-unit.md`: runbook; Paste W.
- `docs/tool-install/johnny-m1s2b-reader.py`: the Python reader; run-file header.
- `docs/tool-install/module1_xdp_records.c`: the C BPF source; `struct m2_rec`; maps.
- `docs/tool-install/module1-slice2b-self-test.sh`: Rock Box self-test with the synthetic ring.

### External

- NIST SP 800-207, *Zero Trust Architecture*: https://csrc.nist.gov/pubs/sp/800/207/final
- IETF RFC 8446, *TLS 1.3*: https://www.rfc-editor.org/rfc/rfc8446.html
- Linux man-pages, *ioctl_ficlone(2)*: https://man7.org/linux/man-pages/man2/ioctl_ficlone.2.html
- Linux man-pages, *mkfs.xfs(8)*: https://man7.org/linux/man-pages/man8/mkfs.xfs.8.html
- Linux kernel docs, *BPF LSM*: https://docs.kernel.org/bpf/bpf_lsm.html
- Linux kernel docs, *LSM usage* (the active list file): https://docs.kernel.org/admin-guide/LSM/index.html
- Linux kernel docs, *BPF LPM trie map*: https://docs.kernel.org/bpf/map_lpm_trie.html
- Linux kernel docs, *BPF ring buffer*: https://docs.kernel.org/bpf/ringbuf.html
- MITRE ATLAS, *AML.T0051*: https://atlas.mitre.org/techniques/AML.T0051
- Microsoft Learn (four pages, **source to confirm**, listed in §1.5 fix 4).

External pages were not fetched in this session. The NIST, RFC, man7, BPF LSM, and ATLAS URLs are the ones the task or the brief already cites. The rest are well-known pages written from memory and should be opened once by the reviewer.
