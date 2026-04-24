# Ralph Iteration Log

Every loop, Ralph appends a structured entry below. This is the human-readable record of what Ralph has tried, with rationale and outcomes — so you can monitor progress without attaching to tmux, and Ralph itself can read recent history (`tail -100`) at the start of each loop to avoid repeating past attempts.

## Entry format

- `## Iteration N — YYYY-MM-DD HH:MM`
- `**Attempted:**` what was done this loop
- `**Rationale:**` why — what signal pointed here
- `**Result:**` observed outcome, with numbers if available
- `**Outcome:**` IMPROVED | NO_IMPROVEMENT | NEEDS_HUMAN_DECISION
- `**Next idea:**` what to try next loop

Newest entries go at the bottom. Start counting N from 1.

---

<!-- Loop entries below. -->
