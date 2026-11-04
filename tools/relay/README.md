# relay.sh — Grok drafts, Claude reviews, one commit per batch
    tools/relay/relay.sh batch-6 [--dry-run] [--rounds 3]     # draft/review loop -> commit+push -> prints AJ's Johnny steps
    tools/relay/relay.sh batch-6 --results /tmp/batch-6-out.txt [--dry-run]   # score CSV + doc Results -> commit+push
Env: GROK_MODEL (default grok-4.7-high), CLAUDE_MODEL, CLAUDE_BUDGET (USD per claude call, default 3), RELAY_REPO, JOHNNY.
Needs a clean working tree. Aborts if an agent touches files outside docs/cis-fix/batch-N.{md,sh}, the results CSV, docs/compliance/, tools/relay/.
Logs: tools/relay/logs/<batch>-<ts>.{log,patch,json}. Batch start commit: tools/relay/state/<batch>.base.
Never runs sudo or writes on Johnny; AJ runs the printed sudo step himself.
    RELAY_EXTRA="..." adds one-off requirements to both Grok and Claude prompts for one run.
