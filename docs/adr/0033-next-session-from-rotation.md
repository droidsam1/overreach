# 0033 — Today infers the next session from the athlete's rotation

- **Status:** Accepted
- **Date:** 2026-11-21

## Context

Many people train without a plan in the app. They repeat the same workouts in a fixed order (A, B, C, D, then A
again), often imported from Strong with only the session name to tell them apart. Today based its easy strength
option on the most recent session, so after D it suggested a lighter D instead of A. A deload proposal said how much
to cut but not which session to cut. Two more problems showed up on the same screen:

- A break the detection could not confirm on its own (ADR-0029: a hybrid athlete without run data, or no regular
  training before it) did not count, so Today proposed a deload right after one. The lighter sessions after the break
  also counted as a performance drop.
- The seven-day list of workouts and recovery values repeated History without saying what it meant for today.

## Decision

1. **`SessionRotation` (Analytics) reads the order the athlete follows.** A workout is its routine when the session
   was started from one, otherwise its name, ignoring case and accents. The same workout twice within 12 hours counts
   once. The shortest cycle of up to six distinct workouts that repeats twice at the end of the last 120 days is the
   rotation; one repeated workout needs three sessions. No evidence claim: it only follows the athlete's own order.
2. **Order of precedence:** today's dated routine, then a declared plan (`PlanSchedule`), then the athlete's choice
   for today, then the detected rotation. Without any of them the easy option keeps using the most recent session.
3. **The athlete can say which session comes next.** Without a plan, Today lists the recent workouts (in rotation
   order when there is one) and the choice lasts for the day. It is not stored.
4. **Deloads apply to a concrete session.** With a known next session, the deload card shows each exercise as it
   was last done and with `DeloadPlan.standard` applied. Without one it explains the plan with a generic example.
5. **Ask before proposing a deload after a possible break.** When a deload would be proposed and an unconfirmed
   break after the last recovery would have prevented it, Today asks whether that break was a rest. The answer is
   the same `DeloadDecision` Plan stores. Performance drops and RPE creep only compare sessions since the last
   deload or confirmed break.
6. **Today drops the seven-day timeline.** The readiness explanation keeps the workouts that matter for today's light,
   and History shows the full record. A failed workout read still shows a note.

## Consequences

- An A-B-C-D rotation needs eight sessions before Today guesses; until then the athlete can choose.
- The choice is not saved, so it does not change the rotation or progression.
- Renaming a workout without a routine starts a new rotation.
