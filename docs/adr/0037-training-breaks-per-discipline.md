# 0037 — Count breaks per discipline, automatically by default

- **Status:** Accepted
- **Date:** 2026-11-21

## Context

ADR-0029 detects recovery periods from all training together and asks the athlete about every ambiguous one. A
hybrid athlete who stops lifting for a week but keeps running had no strength recovery, and Plan asked about periods
from months ago that nobody remembers. The athlete asked for a week without training to count as rest without a
question, for strength and running separately, with a setting to turn it off.

## Decision

1. `DetectedDeload` gains a `discipline` (strength, running, or `nil` for both).
2. With `AthleteProfile.countsBreaksAutomatically` on (the default, also for profiles saved before it existed), at
   least 7 complete days without strength work is a strength break, and at least 7 without runs is a running break
   for someone who runs (a running goal, or runs in 2 of the 4 weeks before). Both count without asking, over all
   imported and logged history. A week without any training counts for both unless run data could not be read. A
   period the athlete already said was not rest stays out.
3. The deload advice and Plan's "last deload" read strength recovery (`RecoveryHistory.lastRecovery(for:)`).
4. A break of 14 days or more is a return: no deload proposal in the 28 days after it.
5. With the setting off, ADR-0029's behaviour stays: ambiguous periods wait for an answer.

Evidence: `training-breaks` in [the evidence register](../evidence.md).

## Consequences

- Fewer questions, and a week off lifting resets the strength deload interval even while running continues.
- An unlogged week of training counts as rest until the athlete turns the setting off; the setting says so.
- Older `DeloadDecision`s have no discipline and keep applying to both.
- A running return making the next runs easy is not implemented yet ([deloads and breaks task 3](../design/deloads-and-breaks.md#3-breaks-per-discipline-counted-automatically)).
