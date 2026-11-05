#!/usr/bin/env bash
# fetch-and-score.sh <batch-N>
# scp Johnny's ~/cis-audit/<batch>-out.txt to /tmp, then run relay --results.
# Never sudo. Never writes on Johnny (scp download only).
set -euo pipefail
usage(){ echo "usage: fetch-and-score.sh batch-N"; exit 2; }
[ $# -eq 1 ] || usage
BATCH=$1
[[ $BATCH =~ ^batch-[0-9]+$ ]] || usage

REPO=${RELAY_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}
JOHNNY=${JOHNNY:-aj@192.168.50.152}
# This project's scoring default: low-fast (high hung mid-batch once).
export GROK_MODEL=${GROK_MODEL:-grok-4.7-low-fast}
OUT=/tmp/${BATCH}-out.txt
REMOTE=~/cis-audit/${BATCH}-out.txt

echo "[$(date '+%H:%M:%S CT')] scp $JOHNNY:$REMOTE -> $OUT"
scp -o BatchMode=yes "$JOHNNY:$REMOTE" "$OUT"
echo "[$(date '+%H:%M:%S CT')] scoring with GROK_MODEL=$GROK_MODEL"
exec "$REPO/tools/relay/relay.sh" "$BATCH" --results "$OUT"
