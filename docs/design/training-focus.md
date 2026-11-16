# Training focus, balance and blocks

Status: core implemented (`Analytics`: `FocusPrescription`, `FocusClassifier`, `FocusBalance`, `BlockAdvisor`).
UI pending (logger shows focus and rest; Plan screen shows blocks; Today/Trends show findings). ADR-0013.

## Focus resolution

exercise setting → session → active declared block → inferred from the sets.

## Default prescriptions

| Focus | Reps | RPE | %1RM | Rest | Default scheme |
| --- | --- | --- | --- | --- | --- |
| Strength | 1–6 | 8 | 80–95 % | 3–5 min | RPE-based 4×4 @ 8 |
| Hypertrophy | 6–15 | 8.5 | 60–85 % | 1.5–3 min | Double progression 3×8–12 @ 8.5 |
| Mixed | 4–10 | 8 | 70–88 % | 2–4 min | Double progression 3×5–8 @ 8 |
| Endurance | 15–30 | 8 | 40–60 % | 0.5–1.5 min | Double progression 2×15–25 @ 8 |

Hypertrophy is similar across a wide loading range when sets end close to failure, so the hypertrophy row is a
practical default, not a requirement. Heavy loads matter for 1RM strength.

## Classification (heuristic)

Set: ≥ 15 reps → endurance; ≤ 6 reps and ≥ 78 % of the recent e1RM → strength (≤ 5 reps if no e1RM); else
hypertrophy. Group (exposure, session, week): majority ≥ 60 %, otherwise mixed.

## Balance findings

| Finding | When | Evidence |
| --- | --- | --- |
| Session/exercise focus mismatch | Declared focus ≠ observed (mixed is compatible with both) | loading-by-goal |
| Focus streak | ≥ 4 sessions of hypertrophy/endurance with a strength goal; ≥ 6 of one focus for general/hybrid; not when a declared block matches | periodization |
| No heavy work on priority lift | Strength goal, no strength-focus exposure in 21 days | loading-by-goal |
| Muscle single focus | ≥ 95 % of a muscle's sets in one focus (≥ 4 sets/week), goal ≠ hypertrophy, no declared block | loading-by-goal |
| Low volume | < 4 weekly fractional sets, hypertrophy/general goals | volume-dose-response |

## Blocks

- Inferred: weekly dominant focus, consecutive equal weeks merged.
- Next block: strength goal alternates hypertrophy/mixed (≈ 6 weeks) and strength (≈ 3–6 weeks); stalls on ≥ 2
  lifts bring the switch forward; a target date within 5 weeks triggers a peak. Hypertrophy goal stays on
  hypertrophy up to ~10 weeks, then a short mixed phase. General/hybrid alternate 6 and 4 weeks.
- Plan: template per goal with deload weeks between blocks, up to 52 weeks or the target date (ending with a
  strength block and a taper week).
