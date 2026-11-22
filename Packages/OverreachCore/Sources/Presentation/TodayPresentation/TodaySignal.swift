import Domain
import Foundation
import PresentationKit

/// One of the (at most three) signal tiles of the Today hero: a value, how it compares and a short trend.
/// Display values only; the numbers come from what Today already computes, no rule is added here
/// (`docs/design/today-visual.md`, ADR-0042).
public struct TodaySignal: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable {
        case hrv, sleep, restingHeartRate, load, bodyBattery
    }

    public let kind: Kind
    public let title: String
    /// The value, formatted for the locale.
    public let value: String
    public let unit: String
    /// Short comparison text, such as "In your range" or "↓ Below your baseline".
    public let status: String
    public let tone: ReadinessLevel
    /// It is the reason the verdict is amber or red.
    public let isLeading: Bool
    /// Last 14 days, oldest first, today last. `nil` for a day without a value.
    public let trend: [Double?]
    /// The personal band, only when a baseline supports one.
    public let band: ClosedRange<Double>?

    public var id: Kind { kind }

    /// A load reading (ACWR) from the training load already computed elsewhere.
    public struct Load: Hashable, Sendable {
        public let value: Double
        public let status: String
        public let tone: ReadinessLevel
        /// Load is one of the reasons behind the verdict.
        public let isReason: Bool
        public let trend: [Double?]

        public init(value: Double, status: String, tone: ReadinessLevel, isReason: Bool, trend: [Double?] = []) {
            self.value = value
            self.status = status
            self.tone = tone
            self.isReason = isReason
            self.trend = trend
        }
    }

    /// The loaded values the choice reads.
    public struct Inputs: Sendable {
        public var today: CalendarDay?
        public var metrics: DailyMetrics?
        /// Recent days, merged across sources, any order. Days without data may be missing.
        public var nights: [DailyMetrics]
        public var readiness: Readiness
        public var load: Load?
        public var calendar: Calendar
        public var format: Format

        public init(
            today: CalendarDay?, metrics: DailyMetrics?, nights: [DailyMetrics], readiness: Readiness,
            load: Load? = nil, calendar: Calendar = .current, format: Format = Format()
        ) {
            self.today = today
            self.metrics = metrics
            self.nights = nights
            self.readiness = readiness
            self.load = load
            self.calendar = calendar
            self.format = format
        }
    }

    /// Days shown in a trend.
    public static let trendDays = 14
    /// Most tiles the hero shows.
    public static let limit = 3

    /// The tiles to show, in order: the leading reason's signal first, then HRV, sleep and resting heart rate.
    /// Load replaces the least informative of them when it is a reason. A signal without data is left out.
    public static func signals(_ inputs: Inputs) -> [TodaySignal] {
        guard inputs.today != nil else { return [] }
        let leadingKind = leadingKind(inputs)
        func make(_ kind: Kind) -> TodaySignal? { signal(kind, inputs) }
        var order: [Kind] = [.hrv, .sleep, .restingHeartRate]
        if let leadingKind { order = [leadingKind] + order.filter { $0 != leadingKind } }
        var chosen = order.compactMap(make)
        if let load = make(.load), inputs.load?.isReason == true, !chosen.contains(where: { $0.kind == .load }) {
            if chosen.count >= limit {
                chosen.removeLast()
            }
            chosen.append(load)
        }
        return Array(chosen.prefix(limit))
    }

    /// One signal on its own, whatever the tile limit: the Why screen builds a card for each reason with a signal.
    static func signal(_ kind: Kind, _ inputs: Inputs) -> TodaySignal? {
        guard let today = inputs.today else { return nil }
        let leading = leadingKind(inputs) == kind
        switch kind {
        case .hrv: return hrv(inputs, today: today, leading: leading)
        case .sleep: return sleep(inputs, today: today, leading: leading)
        case .restingHeartRate: return restingHeartRate(inputs, today: today, leading: leading)
        case .load: return load(inputs, leading: leading)
        case .bodyBattery: return nil
        }
    }

    // MARK: Leading reason

    private static func leadingKind(_ inputs: Inputs) -> Kind? {
        for reason in inputs.readiness.reasons where !reason.isContext {
            switch reason {
            case .hrvBelowBaseline: return .hrv
            case .shortSleep: return .sleep
            case .restingHeartRateElevated: return .restingHeartRate
            default: continue
            }
        }
        return inputs.load?.isReason == true ? .load : nil
    }

    // MARK: Builders

    private static func hrv(_ inputs: Inputs, today: CalendarDay, leading: Bool) -> TodaySignal? {
        guard let metrics = inputs.metrics, let value = metrics.hrvNightlyAverageMs else { return nil }
        let outcome = inputs.readiness.hrvInput?.outcome
        let status: String = switch outcome {
        case .below: L10n.text("↓ Below your baseline")
        case .within: L10n.text("In your range")
        case .above: L10n.text("Above your baseline")
        case nil: L10n.text("Last night")
        }
        let band: ClosedRange<Double>? = {
            guard let low = metrics.hrvBaselineLowMs, let high = metrics.hrvBaselineHighMs, low <= high else {
                return nil
            }
            return low...high
        }()
        return TodaySignal(
            kind: .hrv, title: L10n.text("HRV"), value: inputs.format.number(value, maxFractionDigits: 0),
            unit: L10n.text("ms"), status: status, tone: tone(outcome, leading: leading, level: inputs.readiness.level),
            isLeading: leading, trend: trend(inputs, today: today) { $0.hrvNightlyAverageMs }, band: band
        )
    }

    private static func sleep(_ inputs: Inputs, today: CalendarDay, leading: Bool) -> TodaySignal? {
        guard let hours = inputs.metrics?.sleepSeconds.map({ $0 / 3_600 }) else { return nil }
        let others = inputs.nights.filter { $0.day != today && $0.day < today }
            .suffix(7).compactMap { $0.sleepSeconds.map { $0 / 3_600 } }
        let status: String
        if others.isEmpty {
            status = L10n.text("Last night")
        } else {
            let delta = hours - others.reduce(0, +) / Double(others.count)
            let sign = delta < 0 ? "−" : "+"
            status = L10n.format("{1} h vs week", sign + inputs.format.number(abs(delta), maxFractionDigits: 1))
        }
        return TodaySignal(
            kind: .sleep, title: L10n.text("Sleep"), value: inputs.format.number(hours, maxFractionDigits: 1),
            unit: L10n.text("h"), status: status,
            tone: tone(inputs.readiness.input(.sleep)?.outcome, leading: leading, level: inputs.readiness.level),
            isLeading: leading, trend: trend(inputs, today: today) { $0.sleepSeconds.map { $0 / 3_600 } }, band: nil
        )
    }

    private static func restingHeartRate(_ inputs: Inputs, today: CalendarDay, leading: Bool) -> TodaySignal? {
        guard let value = inputs.metrics?.restingHeartRate else { return nil }
        let outcome = inputs.readiness.input(.restingHeartRate)?.outcome
        let status: String = switch outcome {
        case .above: L10n.text("A bit high")
        case .within: L10n.text("In your range")
        case .below: L10n.text("Lower than usual")
        case nil: L10n.text("Last night")
        }
        return TodaySignal(
            kind: .restingHeartRate, title: L10n.text("Resting HR"),
            value: inputs.format.number(value, maxFractionDigits: 0), unit: L10n.text("bpm"), status: status,
            // For resting heart rate, higher than the baseline is the unfavourable side.
            tone: tone(
                outcome.map { $0 == .above ? .below : .within }, leading: leading, level: inputs.readiness.level
            ),
            isLeading: leading, trend: trend(inputs, today: today) { $0.restingHeartRate }, band: nil
        )
    }

    private static func load(_ inputs: Inputs, leading: Bool) -> TodaySignal? {
        guard let load = inputs.load else { return nil }
        let trend = Array(load.trend.suffix(trendDays))
        return TodaySignal(
            kind: .load, title: L10n.text("Load"), value: inputs.format.fixed(load.value, digits: 2), unit: "",
            status: load.status, tone: load.tone, isLeading: leading, trend: trend, band: nil
        )
    }

    // MARK: Helpers

    /// Amber or red (the verdict's own level) for the leading signal; otherwise green inside the range, amber outside.
    private static func tone(_ outcome: ReadinessComparison?, leading: Bool, level: ReadinessLevel) -> ReadinessLevel {
        if leading, level == .amber || level == .red { return level }
        switch outcome {
        case .below: return .amber
        case .within, .above: return .green
        case nil: return .unknown
        }
    }

    private static func trend(
        _ inputs: Inputs, today: CalendarDay, value: (DailyMetrics) -> Double?
    ) -> [Double?] {
        var byDay: [CalendarDay: Double] = [:]
        for night in inputs.nights {
            if let reading = value(night) { byDay[night.day] = reading }
        }
        if let metrics = inputs.metrics, let reading = value(metrics) { byDay[metrics.day] = reading }
        return (-(trendDays - 1)...0).map { byDay[today.adding(days: $0, calendar: inputs.calendar)] }
    }
}
