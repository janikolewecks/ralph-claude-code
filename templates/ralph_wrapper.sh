#!/bin/bash
# ralph_wrapper.sh — Auto-restart wrapper for Ralph Loop
#
# Usage: bash ralph_wrapper.sh
#   (instead of: ralph --monitor)
#
# This wrapper adds the recovery features missing from default Ralph:
#   - Auto-restart after token/usage limit (waits WAIT_MINUTES, then retries)
#   - Auto-reset + restart after circuit breaker opens
#   - Blocks premature EXIT_SIGNAL: true (verifies 0 open tasks in fix_plan.md)
#   - Auto-restart on unexpected exits
#
# Stop with Ctrl+C

WAIT_MINUTES=30
LOG_FILE=".ralph/logs/ralph.log"
STATUS_FILE=".ralph/status.json"

echo "[WRAPPER] Ralph auto-restart wrapper started at $(date)"
echo "[WRAPPER] Will wait ${WAIT_MINUTES} minutes and retry on token limit."
echo "[WRAPPER] Stop with Ctrl+C"

while true; do
    echo "[WRAPPER] ========================================="
    echo "[WRAPPER] Starting ralph --monitor at $(date)"

    # Proactive circuit breaker reset — clears stale state carried over
    # from a prior crash or unclean exit, so every start begins CLOSED.
    python3 -c "
import json, os
cb_file = '.ralph/.circuit_breaker_state'
if os.path.exists(cb_file):
    try:
        with open(cb_file, 'r+') as f:
            d = json.load(f)
            d['state'] = 'CLOSED'
            d['consecutive_no_progress'] = 0
            d['consecutive_same_error'] = 0
            d['consecutive_permission_denials'] = 0
            d['reason'] = ''
            f.seek(0); json.dump(d, f, indent=4); f.truncate()
    except Exception as e:
        print(f'[WRAPPER] CB pre-reset skipped: {e}')
" 2>/dev/null

    ralph --monitor
    sleep 2

    # Find the tmux session name from the log
    SESSION=$(grep "Setting up tmux session:" "$LOG_FILE" 2>/dev/null | tail -1 | awk '{print $NF}')
    if [ -z "$SESSION" ]; then
        echo "[WRAPPER] Could not find tmux session name. Waiting 60s and retrying..."
        sleep 60
        continue
    fi

    echo "[WRAPPER] Waiting for tmux session '$SESSION' to finish..."

    # Record log size before session, so we only check NEW log entries later
    LOG_LINES_BEFORE=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)

    while tmux has-session -t "$SESSION" 2>/dev/null; do
        sleep 15
    done

    echo "[WRAPPER] Session ended at $(date). Checking exit reason..."
    sleep 2

    # Only look at log lines added during this session
    LAST_LOG=$(tail -n +$LOG_LINES_BEFORE "$LOG_FILE" 2>/dev/null | tail -20)

    # -----------------------------------------------------------------------
    # Check 1: EXIT_SIGNAL: true — only accept if 0 open tasks remain
    # -----------------------------------------------------------------------
    if echo "$LAST_LOG" | grep -qi "EXIT_SIGNAL.*true\|exit_signal.*true"; then
        OPEN_TASKS=$(grep -c "^\- \[ \]" .ralph/fix_plan.md 2>/dev/null || echo "99")
        if [ "$OPEN_TASKS" -gt 0 ]; then
            echo "[WRAPPER] ⚠️  Ralph set EXIT_SIGNAL: true but $OPEN_TASKS tasks still open!"
            echo "[WRAPPER] Resetting session and restarting..."
            python3 -c "
import json, datetime
# Reset session so Ralph starts fresh without 'I was done' memory
s = {'session_id': '', 'created_at': '', 'last_used': '', 'reset_at': datetime.datetime.utcnow().isoformat()+'+00:00', 'reset_reason': 'premature_exit_blocked'}
open('.ralph/.ralph_session', 'w').write(json.dumps(s, indent=2))
# Reset status
st = {'timestamp': datetime.datetime.utcnow().isoformat()+'+00:00', 'loop_count': 0, 'calls_made_this_hour': 0, 'max_calls_per_hour': 100, 'last_action': 'reset_premature_exit', 'status': 'in_progress', 'exit_reason': '', 'next_reset': ''}
open('.ralph/status.json', 'w').write(json.dumps(st, indent=2))
# Reset exit signals
open('.ralph/.exit_signals', 'w').write(json.dumps({'test_only_loops': [], 'done_signals': [], 'completion_indicators': []}))
print('[WRAPPER] Session reset complete.')
" 2>/dev/null
            sleep 10
            continue
        fi
        echo "[WRAPPER] ✅ Ralph finished with EXIT_SIGNAL: true AND 0 open tasks. All done!"
        exit 0
    fi

    # -----------------------------------------------------------------------
    # Check 2: Permission denied / halting loop
    # -----------------------------------------------------------------------
    if echo "$LAST_LOG" | grep -qi "permission denied.*halting\|halting loop"; then
        echo "[WRAPPER] Permission denied caused halt. Waiting 10 minutes and restarting..."
        echo "[WRAPPER] Tip: set ALLOWED_TOOLS=\"Write,Read,Edit,Bash(*)\" in .ralphrc to prevent this."
        sleep 600
        continue
    fi

    # -----------------------------------------------------------------------
    # Check 3: Token / API usage limit
    # -----------------------------------------------------------------------
    if echo "$LAST_LOG" | grep -qi "usage limit\|hit your limit\|5-hour\|rate.limit\|overloaded"; then
        echo "[WRAPPER] Token/usage limit hit. Waiting ${WAIT_MINUTES} minutes..."
        for i in $(seq $WAIT_MINUTES -1 1); do
            echo -ne "[WRAPPER] Resuming in ${i} minutes...\r"
            sleep 60
        done
        echo ""
        echo "[WRAPPER] Restarting ralph now."
        continue
    fi

    # -----------------------------------------------------------------------
    # Check 4: Circuit breaker opened
    # -----------------------------------------------------------------------
    if echo "$LAST_LOG" | grep -qi "circuit breaker\|execution halted"; then
        echo "[WRAPPER] Circuit breaker opened. Waiting 10 minutes, then resetting..."
        sleep 600
        python3 -c "
import json
try:
    with open('.ralph/.circuit_breaker_state', 'r+') as f:
        d = json.load(f)
        d['state'] = 'CLOSED'
        d['consecutive_permission_denials'] = 0
        d['consecutive_no_progress'] = 0
        d['consecutive_same_error'] = 0
        d['reason'] = ''
        f.seek(0); json.dump(d, f, indent=4); f.truncate()
    print('[WRAPPER] Circuit breaker reset to CLOSED.')
except Exception as e:
    print(f'[WRAPPER] Could not reset circuit breaker: {e}')
" 2>/dev/null
        echo "[WRAPPER] Restarting ralph."
        continue
    fi

    # -----------------------------------------------------------------------
    # Check 5: Unexpected / unknown exit — wait and retry
    # -----------------------------------------------------------------------
    echo "[WRAPPER] Unexpected exit. Last log lines:"
    echo "$LAST_LOG"
    echo "[WRAPPER] Waiting 10 minutes before restart..."
    sleep 600
    echo "[WRAPPER] Restarting ralph."
done
