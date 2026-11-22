# relay — standing seats (2026-11-21 9:15 PM CT; 2026-11-21 7:24 PM CT, 2026-11-17, and earlier pins historical)

Current standing seats (AJ, 2026-11-21 9:15 PM CT): **Writer** (**code-writer**) is Gemini 4 Neon high via Antigravity `agy` (`agy --model gemini-4-neon-high --effort high --mode auto --dangerously-skip-permissions --new-project --print "<prompt>"`) — drafts, commands, repo edits; **PR reviewer** (**adversarial-reviewer**) is Claude Code Opus medium — reviews only, does not edit the draft; **decision reviewer** is Claude Code Opus medium. Grok 4.7 high (`cursor-agent`) PR reviewer (reason: Grok tokens running thin) and Argon high (`gemini-4-argon-high`; shared quota exhausted until ~2026-11-24 22:03 CST) are historical. ROCK-BOX-BOT relays. See `AGENTS.md` and `docs/agent-team.md` Rev 13.

Historical note (2026-11-21 7:24 PM CT and 2026-11-17, superseded): standing seats on 2026-11-21 7:24 PM CT were Writer Gemini 4 Neon high via Antigravity `agy`, PR reviewer Grok 4.7 high via `cursor-agent` (now historical; reason: Grok tokens running thin), and decision reviewer Claude Code Opus medium. Standing seats on 2026-11-17 10:50 PM CT were Writer Antigravity `agy` with `gemini-4-argon-high` (high effort, auto mode) and Reviewer Grok 4.7 high via `cursor-agent`, replacing the Claude Fable writer as of 2026-11-15. Standing seats on 2026-11-05 were two Claude Code instances (Sonnet, medium effort: `claude --model sonnet --effort medium --agent code-writer|adversarial-reviewer`), later replaced by the Claude Fable writer (until 2026-11-15) and then the 2026-11-17 standing seats. Earlier Grok-writer pins (2026-11-03 and earlier 2026-11-05) and the Grok draft loop / `GROK_MODEL` values below remain for historical CIS batch scoring only; do not treat `GROK_MODEL`, the 2026-11-05 Sonnet pin, the 2026-11-17 Argon writer pin, or the Grok 4.7 high PR-reviewer pin as the current standing seats.

---

# relay — Grok drafts, Claude reviews, one commit per batch

```
tools/relay/relay.sh batch-6 [--dry-run] [--rounds 3]     # draft/review loop -> commit+push -> prints AJ's Johnny steps
tools/relay/fetch-and-score.sh batch-6                    # scp Johnny out.txt + score CSV/doc (preferred)
tools/relay/relay.sh batch-6 --results /tmp/batch-6-out.txt [--dry-run]   # score only, if you already have the file

After OK-*, `--results` re-audits: Claude gets the out.txt plus a read-only SSH snapshot
(no sudo) and MUST flip in-scope CSV rows from FAIL → PASS/N/A using VERIFY/OK/WROTE
lines and/or that snapshot. Root-only files after harden (e.g. sshd_config 0600) are
scored from the batch log (`verified from batch log`). Also commits `etc/` mirrors when
present. Batches 6–7 already scored this way from VERIFY output; batch 8 initially
left rows unchanged until the scorer prompt was hardened.

```

Env: `GROK_MODEL` (relay default `grok-4.7-high`; fetch-and-score defaults to `grok-4.7-low-fast`), `CLAUDE_MODEL`, `CLAUDE_BUDGET` (USD per claude call, default 3), `AGENT_TIMEOUT` (seconds per agent call, default 600), `RELAY_REPO`, `JOHNNY`, `RELAY_EXTRA`.

Working tree: if the only uncommitted paths are under `tools/relay/logs/` or `tools/relay/state/`, relay auto-commits them as `relay: logs` and continues. Anything else still aborts — commit or stash first. Agents may only touch `docs/cis-fix/batch-N.{md,sh}`, the results CSV, `docs/compliance/`, and `tools/relay/`.

Logs: `tools/relay/logs/<batch>-<ts>.{log,patch,json}`. Batch start commit: `tools/relay/state/<batch>.base`.
Never runs sudo or writes on Johnny; AJ runs the printed sudo step himself. APT/DPKG in batch scripts must be noninteractive (`DEBIAN_FRONTEND=noninteractive`, `force-confold`); interactive debconf under `| tee` hangs. `fetch-and-score.sh` only downloads the out.txt.
