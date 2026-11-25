# Run-to-strength recommendation replay

[ADR-0044](../adr/0044-rotation-after-a-recorded-run.md) describes the rotation and carry-over rules. The
first private replay used six running recordings and an accompanying strength history. The table records the
decision paths using relative order and broad timing buckets. The automated cases use synthetic dates,
exercises and run measurements.

| Case | Routine expected from the stated order | Strength observed after the run | Current rotation advice | Deciding condition |
| --- | --- | --- | --- | --- |
| 1 | C, lower body | C, under 24 h | No offer | Variable gaps in the preceding rotation |
| 2 | D, torso | D, under 24 h | No offer | Variable gaps in the preceding rotation |
| 3 | A, lower body | A, under 24 h | No offer | Variable gaps in the preceding rotation |
| 4 | C, lower body | C, under 24 h | No offer | Variable gaps in the preceding rotation |
| 5 | D, torso | D, 24–48 h | No offer | Repeated C in the recent sequence |
| 6 | C, lower body | None recorded within 48 h | No offer | The repeated C is still in the recent sequence |

The expected routine is inferred from the athlete's stated A → B → C → D order and the last completed slot
before the decision. Exact intent, readiness and the reason for the repeated C were unavailable. The run
export covers only selected outings, so a gap between recordings does not establish a gap in running.

At each observed start, or at the end of the 48-hour window if no lift was logged, consider only strength
sessions completed before the decision. The dated projection requires two cycles with equal local calendar
day gaps. Today only assesses the run when that projection has a heavy slot due on the decision date. A
missing offer leaves the observed workout's suitability unassessed.

A separate synthetic control puts the same run 20 hours before C and D with a stable projection, no previous
heavy leg bout input and unknown readiness. Before [#316](https://github.com/droidsam1/overreach/pull/316),
the rule reported close timing in both and offered a swap for C. The current rule treats close timing as
context, recommends keeping C in its planned slot and makes no offer for D.

The athlete separately described two short running blocks followed by heavy, sore legs and a completed
strength session. Keep this as a reported case with unknown timing and no linked recording. Validate that a
future check-in can distinguish heavy but functional legs from movement limitation before proposing an
adjustment. This replay checks decision paths. Session outcomes and the value of the advice need prospective
review.
