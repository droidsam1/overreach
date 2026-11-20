# 0028 — Running calendar entries have a local date and stable identity

- Status: accepted
- Date: 2026-11-20

## Context

The first running-goal release saved one dated commitment in `TrainingGoal.nextRun`. Today needs to see upcoming quality sessions and races even when an easier session comes first. The strength plan still uses the undated routine rotation in [ADR-0019](0019-training-plans.md).

## Decision

- A hybrid goal can store an optional list of running entries with a stable UUID and a `CalendarDay`. Moving or editing an entry keeps its UUID. Decode the original single entry as a one-item calendar with a deterministic ID. The first calendar edit writes the list and clears the legacy field. Backup and context formats keep their existing versions under [ADR-0018](0018-data-compatibility.md) and [ADR-0017](0017-ai-exchange-channel.md).
- Multiple workouts may share a day. An explicit running rest day is exclusive of other running entries on that date. Race protection consults every pending entry through tomorrow. Today asks the user to review the schedule when several workouts are due and leaves them intact. Strength and running can share a day through their existing paths.
- Completion requires an explicit link to a recorded run on that local date. Use the same cross-source matching as History and prevent linking a recording to multiple entries. A moved entry keeps its identity, and an entry with a confirmed result must be unlinked before moving it. A past entry with no confirmed link stays unlinked. Recording, adjusting and deleting a calendar entry operate independently of workout history.
- The context export carries the calendar and retains `nextRun` as a summary for older readers. The Plan screen owns calendar edits. AI plan import continues to handle strength blocks and routines.
