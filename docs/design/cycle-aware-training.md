# Cycle-aware training

Status: design, spread over phases 0–3 (nutrition later). Decision and evidence: ADR-0009.

## Principle

The menstrual cycle is one more input to the same explainable engine. It corrects baselines, adds context
and enables personal pattern detection. It never changes loads, volume or rest by calendar alone.

## Domain (phase 0 – planned)

```swift
public enum BiologicalSex: String, Codable, Sendable { case female, male, unspecified }

public enum CycleTrackingMode: String, Codable, Sendable {
    case off, naturalCycle, hormonalContraception, menopause
}

public struct AthleteProfile: Codable, Sendable {      // also holds age, max HR, zones…
    public var sex: BiologicalSex?
    public var cycleTracking: CycleTrackingMode
}

public enum CyclePhase: String, Codable, Sendable {
    case menstrual, follicular, ovulatory, luteal, lateLuteal, unknown
}

public struct MenstrualEvent: Codable, Sendable {      // one day of bleeding
    public var day: CalendarDay
    public var flow: Flow?                             // light, medium, heavy, unspecified
    public var isCycleStart: Bool
}

public struct CycleSymptoms: Codable, Sendable {       // part of the check-in
    public var cramps: Int?, fatigue: Int?, headache: Int?, bloating: Int?   // 0…3
}

public protocol CycleSource: Sendable {
    func events(in range: ClosedRange<CalendarDay>) async throws -> [MenstrualEvent]
}
```

## Phase estimation (phase 2, `Analytics`)

Evidence: `cycle-phase-estimation`. Pure function
`CyclePhaseEstimator.estimate(on:events:mode:calendar:)` → `CyclePhaseEstimate?`:

```swift
public struct CyclePhaseEstimate: Hashable, Sendable {
    public var phase: CyclePhase          // .menstrual, .follicular, .luteal, .lateLuteal (never .ovulatory)
    public var cycleDay: Int              // 1 = first day of the current period
    public var expectedLength: Int        // days
    public var confidence: Confidence     // .high, .low
    public var reasons: [Reason]          // fewCycles, irregularCycles, overdue, …
}
```

- Returns `nil` unless `mode == .naturalCycle`. Hormonal contraception and menopause never get a phase
  (`cycle-hormonal-contraception`).
- Cycle start = first day of flow after ≥ 10 days without flow (or `isCycleStart` from Health). Spotting alone
  never starts a cycle.
- Expected length = median of the last up to 6 complete cycles; 28 until 2 complete cycles are known.
- Windows, counted from the last start (`S`) and the next expected start (`N = S + expectedLength`):
  - **menstrual**: flow days of the current cycle (at most days 1–7);
  - **follicular**: after menstrual, until `N − 15`;
  - **luteal**: `N − 14 … N − 6`;
  - **late luteal**: `N − 5 … N − 1`.
  No ovulatory window: a calendar cannot place ovulation (± several days), and the app never shows ovulation
  or fertility. `CyclePhase.ovulatory` stays in the enum for a future LH-test source and is not produced.
- Confidence is **high** only with ≥ 2 complete cycles, all of the last 6 within 21–35 days, a spread
  (max − min) ≤ 7 days and today ≤ `N + 3`. Otherwise **low**, and a low estimate is shown as context at most;
  no rule uses it.
- Overdue (today > `N + 3`): phase `.lateLuteal` is not assumed; the estimate is low with reason `overdue`.

## Where it plugs in

| Phase | Work |
| --- | --- |
| 0 — Foundation | Domain types above and `CycleSource` protocol. ADR-0009. No behaviour. |
| 1 — v0.1 | Progression engine takes an optional context parameter so phase 2 does not change signatures. |
| 2 — v0.2 | `HealthKitSource` implements `CycleSource` (`menstrualFlow` + symptom types; Garmin's cycle endpoint later). Onboarding asks sex and tracking mode. Check-in: "period started today" + symptoms. `CyclePhaseEstimator`. **Phase-aware HRV / resting HR baselines** for the readiness light and deload signals. |
| 3 — Intelligence | Report includes phase, cycle day and symptoms (opt-in). Symptom-driven autoregulation. Running: luteal phase raises HR at a given pace and heat strain, so HR-based run load is read with that context. Personal per-phase analysis after ≥ 3 cycles. |
| Later — Nutrition | New `NutritionSource` + `FeatureNutrition` modules. Energy availability first; protein high end of 1.4–2.2 g/kg/day in luteal; carbohydrates matched to training load in every phase. |

## Phase-aware baselines (phase 2)

Evidence: `cycle-phase-baselines` (replaces the interim `hrv-cycle-phase` behaviour). Resting HR rises a few bpm
and RMSSD falls in the luteal phase, so a whole-cycle baseline reads a normal luteal week as poor recovery.

Two **baseline windows**, enough for the size of the shift and robust to the ± days of error in estimation:

- **follicular window** = menstrual + follicular days;
- **luteal window** = luteal + late luteal days.

Rule, inside `ReadinessRules` (HRV check and resting-HR check), only when the estimate is high confidence:

1. Build the baseline from previous days whose own estimate (computed with the events known then) falls in the
   same window as today, over the readiness baseline period extended back to cover ≥ 2 previous cycles (up to
   120 days).
2. If that window has ≥ 2 cycles with data and the usual minimum of nights (14 for resting HR, Garmin baseline
   or 14 nights for HRV), use it in place of the overall baseline. Reason: `phaseBaseline(window)`, evidence
   `cycle-phase-baselines`.
3. Otherwise use the overall baseline and:
   - HRV: keep the interim behaviour (`hrvMayReflectCycle`, not counted towards red) in the luteal window only;
     in the follicular window a low HRV counts as usual;
   - resting HR: in the luteal window the "above baseline" threshold widens from 5 to 8 bpm, reason
     `possibleLutealShift`.
4. Low confidence, no estimate or another mode → today's behaviour for that user (`hrvMayReflectCycle` stays for
   natural-cycle trackers without a confident estimate).

Garmin's own HRV baseline is a whole-cycle baseline: with a phase baseline available it is ignored for the
comparison and still shown as the device's context (`composite-scores`).

`RecoveryTrend` runs `readiness()` per day, so the deload signals (`hrvSuppressed`, `restingHeartRateElevated`)
inherit phase baselines without change; the per-day call passes the estimate for that day.

**Implementation (v0.2).** `CyclePhaseEstimator` and `CycleContext` (Analytics), `ReadinessRules.readiness(…, cycle:)`
and `RecoveryTrend.assess(…, cycle:)`; `HealthKitMetricsSource` implements `CycleSource`. Details the spec left open:

- The menstrual window is the logged flow days only; an unlogged day inside a period reads as follicular, which is
  the same baseline window.
- Past days are estimated with the events up to that day, and only confident estimates of previous cycles (not the
  current one) enter a phase baseline. A cycle counts towards the 2-cycle minimum when it has at least one reading
  of that series in the window.
- `phaseBaseline(window, cycles)` is shown whenever HRV or resting HR used a phase baseline, even on a green day;
  `possibleLutealShift` only when the widened threshold kept a 5–8 bpm rise from counting. Both are context and
  never a signal.
- The deload trend does not count a low-HRV day that the light reads as `hrvMayReflectCycle`.
- Garmin's HRV range was already context only: readiness compares personal series, so nothing changes there.
- Health asks for menstrual-flow access the first time Today reads it, and Today reads it only for a natural
  cycle, so other users are never asked. Flow logged as "none" is ignored. A year of events is read (6 cycles plus
  the estimates of past days); metrics history grows to 120 + 7 days for these users.

**Texts.** Reasons name the window, never a diagnosis: *"Compared with your luteal days in the last 2 cycles"*,
*"Resting HR often rises a few beats before a period; the threshold allows for it."* Nothing mentions ovulation.

**Tests (fixtures).** Synthetic 28 ± 2-day cycles over 120 days with a +4 bpm / −10 % RMSSD luteal shift:
- a luteal day at the luteal norm is green with a phase baseline and would have been amber without it;
- a truly suppressed luteal day (below the luteal baseline) still counts;
- one known cycle → fallback; irregular cycles (24, 38, 29) → low confidence → no phase;
- hormonal contraception → overall baseline; missing HRV → nothing breaks.

## Autoregulation (phase 3)

When check-in symptoms or energy are poor (in any phase, for any user), today's targets switch to RPE-based:
keep the planned reps at target RPE and let the load fall out of it. A missed target on such a day is not
counted towards stall detection. The reason shown names the symptom, not the phase (`cycle-symptoms`).

## Personal pattern detection (phase 3)

After ≥ 3 cycles with training in several phases, compare per-phase e1RM at matched loads, RPE at matched
loads and run HR at matched pace. Only a consistent difference (e.g. > 3 % e1RM, same direction in ≥ 3
cycles) produces an insight such as *"Your bench RPE is ~0.5 higher in the late luteal phase; targets on
those days use RPE."* Otherwise nothing is shown.

## Privacy

Reproductive data never leaves the device. It is excluded from the shareable report unless the user turns on
"Include cycle context" in Settings.
