#!/bin/bash
# check_status.sh — Ralph pre-flight status check
# Run this at the start of every loop to get ground truth on open tasks.
# Ralph's PROMPT.md mandates running this as the first action every loop.

echo "=================================================="
echo "RALPH PRE-FLIGHT STATUS CHECK"
echo "=================================================="
echo ""
echo "Open tasks in fix_plan.md:"
grep -n "^\- \[ \]" .ralph/fix_plan.md | head -20

OPEN_COUNT=$(grep -c "^\- \[ \]" .ralph/fix_plan.md 2>/dev/null || echo "0")
DONE_COUNT=$(grep -c "^\- \[x\]" .ralph/fix_plan.md 2>/dev/null || echo "0")

echo ""
echo "Total open tasks:  $OPEN_COUNT"
echo "Total done tasks:  $DONE_COUNT"
echo ""

if [ "$OPEN_COUNT" -gt 0 ]; then
    echo "!!! PROJECT IS NOT COMPLETE: $OPEN_COUNT TASKS STILL OPEN !!!"
    echo "!!! DO NOT SET EXIT_SIGNAL: true                          !!!"
    echo "!!! Pick an open task above and work on it.               !!!"
else
    echo "✅ All tasks done — EXIT_SIGNAL: true is permitted."
    echo "   But first check: are there stretch goals to add?"
fi

echo "=================================================="
