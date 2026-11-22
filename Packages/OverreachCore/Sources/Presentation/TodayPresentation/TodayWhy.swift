import Domain
import Foundation
import PresentationKit

/// The details a Why row opens.
public enum WhyRowKind: String, Hashable, Sendable {
    case trainingThatCounts, sourcesAndCoverage, furtherReading
}

/// The level-2 "Why" screen of Today: what weighs on the verdict, a card per reason with a signal, the signals in
/// range and the rows to the details that already exist. It only arranges what the readiness rules and
/// `TodaySignal` already computed: there is no composite score and no new threshold (ADR-0041, ADR-0042).
public struct TodayWhy: Hashable, Sendable {
    /// One segment of the "What weighs" bar.
    public struct Weight: Hashable, Sendable, Identifiable {
        public let id: Int
        public let title: String
        /// Relative size of the segment. It follows the order the rules list the reasons in, first the heaviest.
        public let weight: Int
        public let tone: ReadinessLevel
    }

    /// One reason that has a signal: its value, 14-night series and band, a sentence and the evidence.
    public struct Card: Hashable, Sendable, Identifiable {
        public let signal: TodaySignal
        public let sentence: String
        public let evidence: String
        public let source: URL?
        /// The usual zone of the load ratio, to draw it as a gauge instead of a night chart.
        public var isGauge: Bool { signal.kind == .load }
        /// The load ratio to place on the gauge; `nil` for the signals drawn as a night chart.
        public let gaugeValue: Double?

        public var id: TodaySignal.Kind { signal.kind }
    }

    /// A signal that is in range, as a compact value with its baseline line.
    public struct Normal: Hashable, Sendable, Identifiable {
        public let kind: TodaySignal.Kind
        public let title: String
        public let value: String
        public let unit: String
        /// "In your range", "+0.4 h vs week".
        public let baseline: String

        public var id: TodaySignal.Kind { kind }
    }

    /// A row to a level-2 detail that already exists.
    public struct Row: Hashable, Sendable, Identifiable {
        public let kind: WhyRowKind
        public let title: String
        /// A one-line preview of what the detail holds.
        public let detail: String

        public var id: WhyRowKind { kind }
    }

    public let level: ReadinessLevel
    /// Shown before anything else when the reasons advise skipping training; such a verdict has no signal cards.
    public let safetyText: String?
    /// Segments of the bar, heaviest first. Signals in range are one more, neutral segment (`normalWeight`).
    public let weights: [Weight]
    /// Size of the neutral segment for `normal`; zero when there are no signals in range.
    public let normalWeight: Int
    public let cards: [Card]
    public let normal: [Normal]
    public let rows: [Row]

    /// The loaded values the screen reads.
    struct Inputs {
        var signals: TodaySignal.Inputs
        /// `readinessLines`, aligned with `signals.readiness.reasons`.
        var lines: [ReadinessLine]
        var trainingContext: ReadinessTrainingContext?
        var sources: [ReadinessSourceDetail]
        var coverageNote: String?
    }

    static func make(_ inputs: Inputs) -> TodayWhy {
        let readiness = inputs.signals.readiness
        let reasons = Array(zip(readiness.reasons, inputs.lines))
        let skipsTraining = readiness.reasons.contains(where: \.advisesSkippingTraining)
        let safety = reasons.first { $0.0.advisesSkippingTraining }?.1.text

        // Context and "missing data" explain a comparison; they never weigh on the verdict.
        let weighing = reasons.filter { reason, _ in !reason.isContext && reason != .missingData }
        let weights = weighing.enumerated().map { index, entry in
            Weight(
                id: index, title: entry.1.text, weight: weighing.count - index,
                tone: entry.0.advisesSkippingTraining ? .red : readiness.level
            )
        }

        var cards: [Card] = []
        var reasonKinds: Set<TodaySignal.Kind> = []
        if !skipsTraining {
            for (reason, line) in weighing {
                guard let kind = signalKind(of: reason), !reasonKinds.contains(kind),
                      let signal = TodaySignal.signal(kind, inputs.signals) else { continue }
                reasonKinds.insert(kind)
                cards.append(Card(
                    signal: signal, sentence: line.text, evidence: line.evidence, source: line.source, gaugeValue: nil
                ))
            }
            if inputs.signals.load?.isReason == true, let load = TodaySignal.signal(.load, inputs.signals) {
                cards.append(Card(
                    signal: load, sentence: load.status, evidence: "", source: nil,
                    gaugeValue: inputs.signals.load?.value
                ))
                reasonKinds.insert(.load)
            }
        }

        let normalKinds: [TodaySignal.Kind] = [.hrv, .sleep, .restingHeartRate]
        let normal: [Normal] = skipsTraining ? [] : normalKinds.compactMap { kind in
            guard !reasonKinds.contains(kind), let signal = TodaySignal.signal(kind, inputs.signals),
                  signal.tone != .amber, signal.tone != .red else { return nil }
            return Normal(
                kind: kind, title: signal.title, value: signal.value, unit: signal.unit, baseline: signal.status
            )
        }

        return TodayWhy(
            level: readiness.level, safetyText: safety, weights: weights, normalWeight: normal.isEmpty ? 0 : 1,
            cards: cards, normal: normal, rows: rows(inputs, lines: inputs.lines)
        )
    }

    private static func signalKind(of reason: ReadinessReason) -> TodaySignal.Kind? {
        switch reason {
        case .hrvBelowBaseline: .hrv
        case .shortSleep: .sleep
        case .restingHeartRateElevated: .restingHeartRate
        default: nil
        }
    }

    private static func rows(_ inputs: Inputs, lines: [ReadinessLine]) -> [Row] {
        var rows: [Row] = []
        if let context = inputs.trainingContext {
            rows.append(Row(
                kind: .trainingThatCounts, title: L10n.text("Training that counts"), detail: context.heading
            ))
        }
        if !inputs.sources.isEmpty || inputs.coverageNote != nil {
            rows.append(Row(
                kind: .sourcesAndCoverage, title: L10n.text("Sources and coverage"),
                detail: inputs.coverageNote ?? inputs.sources.map(\.title).joined(separator: " · ")
            ))
        }
        let readings = Set(lines.flatMap(\.readings)).count
        if readings > 0 {
            rows.append(Row(
                kind: .furtherReading, title: L10n.text("Further reading"),
                detail: L10n.format("{1} readings", String(readings))
            ))
        }
        return rows
    }
}
