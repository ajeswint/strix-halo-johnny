# relay — Grok drafts, Claude reviews, one commit per batch

```
tools/relay/relay.sh batch-6 [--dry-run] [--rounds 3]     # draft/review loop -> commit+push -> prints AJ's Johnny steps
tools/relay/fetch-and-score.sh batch-6                    # scp Johnny out.txt + score CSV/doc (preferred)
tools/relay/relay.sh batch-6 --results /tmp/batch-6-out.txt [--dry-run]   # score only, if you already have the file
```

Env: `GROK_MODEL` (relay default `grok-4.7-high`; fetch-and-score defaults to `grok-4.7-low-fast`), `CLAUDE_MODEL`, `CLAUDE_BUDGET` (USD per claude call, default 3), `AGENT_TIMEOUT` (seconds per agent call, default 600), `RELAY_REPO`, `JOHNNY`, `RELAY_EXTRA`.

Working tree: if the only uncommitted paths are under `tools/relay/logs/` or `tools/relay/state/`, relay auto-commits them as `relay: logs` and continues. Anything else still aborts — commit or stash first. Agents may only touch `docs/cis-fix/batch-N.{md,sh}`, the results CSV, `docs/compliance/`, and `tools/relay/`.

Logs: `tools/relay/logs/<batch>-<ts>.{log,patch,json}`. Batch start commit: `tools/relay/state/<batch>.base`.
Never runs sudo or writes on Johnny; AJ runs the printed sudo step himself. `fetch-and-score.sh` only downloads the out.txt.
