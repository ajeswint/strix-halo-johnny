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
