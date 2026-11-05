#!/usr/bin/env bash
# relay.sh <batch-N> [--results FILE] [--dry-run] [--rounds N]
# Automates the Grok (cursor-agent) <-> Claude (claude -p) relay for CIS batches.
# Never runs sudo. Never writes to Johnny. Read-only ssh audits only (skipped in --dry-run).
set -euo pipefail
usage(){ echo "usage: relay.sh batch-N [--results FILE] [--dry-run] [--rounds N]"; exit 2; }
[ $# -ge 1 ] || usage
BATCH=$1; shift; [[ $BATCH =~ ^batch-[0-9]+$ ]] || usage
RESULTS=""; DRY=0; ROUNDS=3
while [ $# -gt 0 ]; do case $1 in
  --results) RESULTS=$2; shift 2;; --dry-run) DRY=1; shift;; --rounds) ROUNDS=$2; shift 2;; *) usage;; esac; done

REPO=${RELAY_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}
GROK_MODEL=${GROK_MODEL:-grok-4.7-high}
AGENT_TIMEOUT=${AGENT_TIMEOUT:-600}   # seconds per agent call; kills hung CLIs
CLAUDE_MODEL=${CLAUDE_MODEL:-}          # empty = claude default
CURSOR_BIN=${RELAY_CURSOR_BIN:-$HOME/.local/bin/cursor-agent}  # CURSOR_AGENT is set to 1 by Cursor itself
JOHNNY=${JOHNNY:-aj@192.168.50.152}
DOC=docs/cis-fix/$BATCH.md; SH=docs/cis-fix/$BATCH.sh; CSV=docs/cis-26.04-l1-results.csv
LOGDIR=$REPO/tools/relay/logs; STATE=$REPO/tools/relay/state
mkdir -p "$LOGDIR" "$STATE"
TS=$(date +%Y%m%d-%H%M%S); LOG=$LOGDIR/$BATCH-$TS.log
log(){ echo "[$(date '+%H:%M:%S CT')] $*" | tee -a "$LOG" >&2; }
cd "$REPO"

# Paths the agents may change; anything else aborts the run.
ALLOWED_RE="^(docs/cis-fix/$BATCH\.(md|sh)|docs/cis-26\.04-l1-results\.csv|docs/compliance/.*|etc/.*|tools/relay/(relay\.sh|fetch-and-score\.sh|README\.md|logs/.*|state/.*))$"
check_paths(){
  local bad; bad=$(git status --porcelain --untracked-files=all | awk '{print $NF}' | grep -Ev "$ALLOWED_RE" || true)
  if [ -n "$bad" ]; then log "ABORT: unexpected files changed:"; echo "$bad" | tee -a "$LOG"; exit 3; fi
}
# Auto-commit relay debris so a leftover log never blocks scoring.
auto_commit_relay_debris(){
  local paths dirt
  # All dirty paths (tracked + untracked). Abort if anything outside logs/state.
  paths=$(git status --porcelain --untracked-files=all | awk '{print $NF}')
  [ -z "$paths" ] && return 0
  dirt=$(echo "$paths" | grep -Ev '^tools/relay/(logs|state)/' || true)
  if [ -n "$dirt" ]; then
    log "ABORT: working tree has uncommitted changes; commit/stash first"
    echo "$paths" | tee -a "$LOG" >&2
    exit 3
  fi
  if [ $DRY = 1 ]; then
    log "DRY RUN: would auto-commit relay logs/state debris"
    git status --short | tee -a "$LOG" >&2
    return 0
  fi
  git add tools/relay/logs tools/relay/state
  if git diff --cached --quiet; then return 0; fi
  git commit -q -m "relay: logs"
  git push -q origin HEAD
  log "Auto-committed relay logs/state as $(git rev-parse --short HEAD)"
}
auto_commit_relay_debris

CONV="DELIVERY CONVENTION (overrides AGENTS.md paste rules): AJ copies $SH to Johnny with scp and runs it whole as 'sudo bash ~/cis-audit/$BATCH.sh' from an SSH session; KVM-only steps (reboot checks, console) are separate numbered pastes marked '# RUNS IN: KVM' that AJ types at the console. The .sh file IS the deliverable; $DOC links to it rather than duplicating it. Rollback goes in $DOC under '## Rollback'. APT/DPKG RULE (every batch): any apt-get, apt, or dpkg in $SH MUST export DEBIAN_FRONTEND=noninteractive (and prefer DEBCONF_NONINTERACTIVE_SEEN=true), use -y and -o Dpkg::Options::=--force-confold (and --force-confdef), never rely on interactive debconf or pam-auth-update prompts (they hang under '| tee'); prefer timeout(1) around apt/dpkg; pam-auth-update must be noninteractive with explicit --enable/--disable profiles and --force when re-running over package leftovers. "
EXTRA=${RELAY_EXTRA:-}   # optional one-off instructions for this run (Grok and Claude)
SAFETY="HARD RULES: never run sudo; never write to Johnny ($JOHNNY); never run git commit/push/reset/checkout; edit only $DOC, $SH (and $CSV only if told). "
if [ $DRY = 1 ]; then SAFETY+="DRY RUN: do NOT ssh or contact Johnny at all."
else SAFETY+="You MAY run read-only, non-sudo audit commands on Johnny via: ssh -o BatchMode=yes $JOHNNY '<cmd>' (no redirects to files, no rm/mv/tee/cp/install/systemctl changes)."; fi

grok(){ # $1 prompt
  local out=$LOGDIR/$BATCH-$TS-grok-$2.json
  log "Grok ($GROK_MODEL) round $2 ..."
  timeout -k 10 "$AGENT_TIMEOUT" "$CURSOR_BIN" -p --model "$GROK_MODEL" --output-format json --force --trust --workspace "$REPO" "$SAFETY
$CONV
${EXTRA:+ONE-OFF REQUIREMENTS FOR THIS RUN: $EXTRA}
$1" > "$out" 2>>"$LOG" || { log "Grok CLI failed or timed out after ${AGENT_TIMEOUT}s (see $out / $LOG)"; exit 4; }
  python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print((d.get("result") or "")[:1500])' "$out" | tee -a "$LOG" >&2
  check_paths
}

SCHEMA='{"type":"object","properties":{"verdict":{"type":"string","enum":["approve","changes"]},"issues":{"type":"array","items":{"type":"string"}}},"required":["verdict","issues"]}'
claude_review(){ # $1 round -> prints verdict JSON
  local out=$LOGDIR/$BATCH-$TS-claude-$1.json base; base=$(cat "$STATE/$BATCH.base")
  log "Claude review round $1 (diff vs $base) ..."
  { git diff "$base" -- docs; git ls-files -o --exclude-standard docs | while read -r f; do echo "=== NEW FILE $f"; cat "$f"; done; } > "$LOGDIR/$BATCH-$TS-diff-$1.patch"
  timeout -k 10 "$AGENT_TIMEOUT" claude -p ${CLAUDE_MODEL:+--model "$CLAUDE_MODEL"} --output-format json --json-schema "$SCHEMA" \
    --allowedTools "Read" "Grep" "Glob" --permission-mode dontAsk --no-session-persistence --max-budget-usd "${CLAUDE_BUDGET:-3}" \
    "You are the reviewer for CIS Ubuntu 26.04 L1 fix $BATCH on host Johnny. Review the diff on stdin (and read repo files if needed) for: correctness vs CIS, safety (rollback, backups, set -euo pipefail, STOP guards), each paste's first line saying SSH or KVM, one numbered script $SH only. If $SH runs apt-get/apt/dpkg, reject with BLOCKER unless DEBIAN_FRONTEND=noninteractive and noninteractive dpkg options are present (see APT/DPKG RULE). $CONV ${EXTRA:+ONE-OFF REQUIREMENTS (reject with BLOCKER if any is missing): $EXTRA} Return verdict approve if AJ can safely run it as is; cosmetic or style nits go in issues but do NOT block approval. Return changes only for correctness, safety, or rollback problems, each issue prefixed BLOCKER:." \
    < "$LOGDIR/$BATCH-$TS-diff-$1.patch" > "$out" 2>>"$LOG" || { log "Claude CLI failed or timed out after ${AGENT_TIMEOUT}s (see $out)"; exit 4; }
  python3 - "$out" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
v=d.get("structured_output")
if v is None:
    r=d.get("result","");import re;m=re.search(r"\{.*\}",r,re.S);v=json.loads(m.group(0)) if m else {"verdict":"changes","issues":["unparseable reviewer output"]}
print(json.dumps(v))
PY
}

commit_push(){ # $1 message
  check_paths
  if [ $DRY = 1 ]; then log "DRY RUN: would commit+push: $1"; git status --short | tee -a "$LOG"; return; fi
  git add -A docs/cis-fix docs/compliance etc "$CSV" tools/relay/logs tools/relay/state 2>/dev/null || true
  git commit -q -m "$1" && git push -q origin HEAD && log "Committed+pushed $(git rev-parse --short HEAD)"
}

fix_csv(){ # normalise quoting; merge stray commas into title (6 columns: id,title,level,result,evidence,date)
python3 - "$CSV" <<'PY'
import csv,sys
p=sys.argv[1]; rows=list(csv.reader(open(p,newline='')))
h=rows[0]; n=len(h); out=[h]; fixed=0
for r in rows[1:]:
    if len(r)>n:
        k=len(r)-n; r=[r[0], ",".join(r[1:2+k])]+r[2+k:]; fixed+=1
    out.append(r)
if fixed: csv.writer(open(p,'w',newline=''),quoting=csv.QUOTE_MINIMAL,lineterminator='\n').writerows(out)  # rewrite only if a row was malformed
bad=[i for i,r in enumerate(out) if len(r)!=n]
print(f"csv: {len(out)-1} rows, merged {fixed}, bad {len(bad)}"); sys.exit(1 if bad else 0)
PY
}

if [ -z "$RESULTS" ]; then
  # ---------- DRAFT / REVIEW LOOP ----------
  [ -f "$STATE/$BATCH.base" ] || git rev-parse HEAD > "$STATE/$BATCH.base"
  log "Batch $BATCH base $(cat "$STATE/$BATCH.base") dry=$DRY"
  ISSUES="(none yet; this is the first draft or revision)"
  for r in $(seq 1 "$ROUNDS"); do
    grok "Task: draft or revise CIS fix $BATCH for Johnny. Write $DOC with a '## Plan' section written ONCE (do not keep rewriting other sections; no handoff/rev churn; do not touch docs/os-handoff.md). Write exactly ONE script $SH: numbered pastes (# PASTE 1, # PASTE 2...), each paste's first line a comment saying where it runs: '# RUNS IN: SSH' or '# RUNS IN: KVM'. Each paste uses set -euo pipefail, takes backups before changes, has STOP guards (echo STOP-... ; exit 1) on unexpected state, and a rollback comment. Read docs/cis-26.04-l1-results.csv and the batch notes to choose rules if $DOC has no scope yet. Reviewer issues to fix: $ISSUES" "$r"
    V=$(claude_review "$r"); log "Claude verdict: $V"
    if [ "$(jq -r .verdict <<<"$V")" = approve ]; then
      commit_push "CIS $BATCH: plan and script, Claude-approved (relay round $r)"
      log "=== AJ: run on Johnny ==="
      echo "scp $REPO/$SH $JOHNNY:~/cis-audit/$BATCH.sh   # from aj-rock-box"
      grep -nE '^# (PASTE|RUNS IN)' "$SH" || true
      echo "Then on Johnny (SSH or KVM per paste): sudo -v && sudo bash ~/cis-audit/$BATCH.sh 2>&1 | tee ~/cis-audit/$BATCH-out.txt"
      echo "Score (one command): tools/relay/fetch-and-score.sh $BATCH"
      echo "Or manual: scp $JOHNNY:~/cis-audit/$BATCH-out.txt /tmp/ && $0 $BATCH --results /tmp/$BATCH-out.txt"
      exit 0
    fi
    ISSUES=$(jq -r '.issues|join("\n- ")' <<<"$V")
  done
  log "NOT APPROVED after $ROUNDS rounds. Last issues:"; echo "- $ISSUES" | tee -a "$LOG"; exit 1
else
  # ---------- RESULTS ----------
  [ -f "$RESULTS" ] || { log "no results file $RESULTS"; exit 2; }
  cp "$RESULTS" "$LOGDIR/$BATCH-$TS-results.txt"
  fix_csv | tee -a "$LOG"
  # Build scoring input: batch out.txt + optional read-only SSH snapshot (no sudo).
  SCORE_IN=$LOGDIR/$BATCH-$TS-score-input.txt
  {
    echo "=== BATCH OUTPUT ($RESULTS) ==="
    cat "$RESULTS"
    echo
    echo "=== READ-ONLY SSH SNAPSHOT (no sudo; may be incomplete after harden) ==="
    if [ $DRY = 1 ]; then
      echo "(dry-run: skipped ssh)"
    else
      ssh -o BatchMode=yes -o ConnectTimeout=10 "$JOHNNY" 'bash -s' <<'EOS' 2>/dev/null || echo "(ssh snapshot failed)"
set +e
echo "-- listen 22 --"; ss -H -lnt sport = :22
echo "-- sshd modes --"; stat -c "%a %U %G %n" /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>&1
echo "-- sshd -T (unprivileged; fails if config 0600) --"; sshd -T 2>&1 | egrep -i "^(allowusers|banner|clientaliveinterval|clientalivecountmax|disableforwarding|logingracetime|macs|maxauthtries|maxstartups|permitrootlogin) " | head -40
echo "-- issue.net --"; cat /etc/issue.net 2>&1; echo
echo "-- environment PATH --"; grep -E "^PATH=" /etc/environment 2>&1
echo "-- pam wheel --"; grep -nE "pam_wheel|sugroup" /etc/pam.d/su 2>&1
echo "-- sugroup --"; getent group sugroup 2>&1
echo "-- sudoers.d --"; ls -la /etc/sudoers.d/ 2>&1
echo "-- sysctl ipv6/martians --"; sysctl net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.default.disable_ipv6 net.ipv4.conf.all.log_martians net.ipv4.conf.default.log_martians 2>&1
echo "-- ufw --"; ufw status 2>&1 | head -20
EOS
    fi
  } > "$SCORE_IN"

  log "Claude scoring results into $CSV ..."
  timeout -k 10 "$AGENT_TIMEOUT" claude -p ${CLAUDE_MODEL:+--model "$CLAUDE_MODEL"} --output-format json --allowedTools "Read" "Grep" "Edit($CSV)" \
    --permission-mode acceptEdits --no-session-persistence --max-budget-usd "${CLAUDE_BUDGET:-3}" \
    "You are scoring CIS $BATCH for host Johnny. Input on stdin has (1) the batch apply/verify out.txt and (2) a read-only SSH snapshot (no sudo).

HARD RULE for scoring: if the batch output contains OK-$BATCH or OK-batch-N / OK-paste success lines and no unresolved STOP-* that aborted the run, you MUST update every in-scope CSV row for this batch from FAIL/FAIL (manual) to the correct PASS/PASS (manual)/N/A based on the evidence. Do NOT leave rows unchanged waiting for a later Governance re-audit — this --results step IS the re-audit.

Evidence you may use (any is enough): VERIFY/OK/SKIP/WROTE/STATE lines in the out.txt; values the script itself checked (e.g. sshd_ok, sysctl -n, ufw status); the read-only SSH snapshot; and for root-only files after a harden (sshd_config 0600, sudoers 0440) mark PASS with evidence noting verified from batch log when the script printed OK after its own root checks. Prefer live snapshot values when present.

Update ONLY rows of $CSV for rules this batch covered: result, evidence (short), date $(date +%F). Keep 6 columns; quote fields with commas. Edit no other file. Reply with a one-paragraph summary of every changed row. If you would change zero rows despite OK-*, that is a scoring bug — change them." \
    < "$SCORE_IN" > "$LOGDIR/$BATCH-$TS-claude-score.json" 2>>"$LOG"
  fix_csv | tee -a "$LOG"
  grok "Append a '## Results' section ONCE to $DOC summarising tools/relay/logs/$BATCH-$TS-results.txt and the CSV changes (git diff $CSV). Do not edit other sections or files." results
  commit_push "CIS $BATCH: results scored and recorded"
  awk -F, 'NR>1' "$CSV" >/dev/null; python3 -c "
import csv,collections;r=list(csv.DictReader(open('$CSV')));print(collections.Counter(x['result'] for x in r))" | tee -a "$LOG"
fi
