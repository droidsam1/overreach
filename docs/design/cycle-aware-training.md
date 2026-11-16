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

Pure function `estimatePhase(on:events:)` → `CyclePhaseEstimate { phase, cycleDay, confidence, reasons }`.

- Cycle start = first day of flow after ≥ 10 days without flow (or `isCycleStart` from Health).
- Cycle length = median of the last up to 6 cycles; default 28 until 2 cycles are known.
- Ovulation ≈ next expected start − 14 days (the luteal phase is the more stable half).
- Phases: menstrual = flow days; follicular until ovulation − 2; ovulatory = ovulation ± 2;
  luteal after that; late luteal = last 5 days before the expected start.
- Confidence drops with few cycles, high variability (> 7 days spread) or an overdue period. Irregular cycles
  or `cycleTracking != .naturalCycle` → `.unknown`, phase is not used.

## Where it plugs in

| Phase | Work |
| --- | --- |
| 0 — Foundation | Domain types above and `CycleSource` protocol. ADR-0009. No behaviour. |
| 1 — v0.1 | Progression engine takes an optional context parameter so phase 2 does not change signatures. |
| 2 — v0.2 | `HealthKitSource` implements `CycleSource` (`menstrualFlow` + symptom types). Onboarding asks sex and tracking mode. Check-in: "period started today" + symptoms. `estimatePhase`. **Phase-aware HRV / resting HR baselines** for the readiness light and deload signals. |
| 3 — Intelligence | Report includes phase, cycle day and symptoms (opt-in). Symptom-driven autoregulation. Running: luteal phase raises HR at a given pace and heat strain, so HR-based run load is read with that context. Personal per-phase analysis after ≥ 3 cycles. |
| Later — Nutrition | New `NutritionSource` + `FeatureNutrition` modules. Energy availability first; protein high end of 1.4–2.2 g/kg/day in luteal; carbohydrates matched to training load in every phase. |

## Phase-aware baselines (phase 2)

The deload signals "HRV 7-day average below normal ≥ 5 days" and "resting HR ≥ 5 bpm above baseline" compare
against a baseline. For naturally cycling users with a confident phase estimate, the baseline is computed from
the same phase in previous cycles (fallback: overall baseline with the luteal tolerance widened). Without at
least 2 cycles of HRV data, the signal carries the reason "possible luteal shift" instead of firing at full
weight.

## Autoregulation (phase 3)

When check-in symptoms or energy are poor (in any phase, for any user), today's targets switch to RPE-based:
keep the planned reps at target RPE and let the load fall out of it. A missed target on such a day is not
counted towards stall detection. The reason shown names the symptom, not the phase.

## Personal pattern detection (phase 3)

After ≥ 3 cycles with training in several phases, compare per-phase e1RM at matched loads, RPE at matched
loads and run HR at matched pace. Only a consistent difference (e.g. > 3 % e1RM, same direction in ≥ 3
cycles) produces an insight such as *"Your bench RPE is ~0.5 higher in the late luteal phase; targets on
those days use RPE."* Otherwise nothing is shown.

## Privacy

Reproductive data never leaves the device. It is excluded from the shareable report unless the user turns on
"Include cycle context" in Settings.
