import Analytics
import Domain
import Foundation
import PresentationKit

public enum PerformanceDistance: Int, CaseIterable, Identifiable, Sendable {
    case oneKilometer = 1, fiveKilometers = 5, tenKilometers = 10

    public var id: Int { rawValue }
    public var title: String { L10n.format("{1} km", String(rawValue)) }

    var distance: RunningPerformance.Distance {
        switch self {
        case .oneKilometer: .oneKilometer
        case .fiveKilometers: .fiveKilometers
        case .tenKilometers: .tenKilometers
        }
    }
}

public enum PerformanceSession: Hashable, Sendable {
    case run(RunActivity)
    case strength(sessionID: UUID, setID: UUID)
}

public struct PerformancePoint: Identifiable, Sendable {
    public let id: PerformanceSession
    public let date: Date
    public let value: Double
    public let valueText: String
    public let detail: String
}

public struct PerformanceSeries: Identifiable, Sendable {
    public enum Unit: Equatable, Sendable {
        case elapsedSeconds, weight, reps, heartRate
    }

    public let id: String
    public let title: String
    public let unit: Unit
    public let isEstimated: Bool
    public let points: [PerformancePoint]
    public let best: PerformancePoint?
    public internal(set) var comparison: String
    public var trend: String?
    public var context: String?
}

/// One lift. Records compare one source at a time, so a lift trained in several sources offers them as a filter.
public struct StrengthPerformanceOption: Identifiable, Sendable {
    public let id: String
    public let title: String
    /// Sources with sets in the period, the one with most sessions first.
    public let sources: [DataSourceKind]
    let exercise: Exercise
    let sets: [StrengthPerformance.RecordedSet]
}

private struct RankedLift {
    let option: StrengthPerformanceOption
    let count: Int
    let last: Date
}

struct PerformanceProgress {
    let window: PerformanceComparison
    let format: Format

    func running(_ results: [RunningPerformance.BestTime]) -> [PerformanceSeries] {
        RunActivity.Kind.allCases.flatMap { kind in
            let matching = results.filter { $0.kind == kind }
            let exact = matching.filter { $0.coverage != .nearWholeActivity }.map(runPoint)
            let nearby = matching.filter { $0.coverage == .nearWholeActivity }.map(runPoint)
            let title = runTitle(kind)
            let measured = makeSeries(kind.rawValue, title: title, unit: .elapsedSeconds, points: exact)
            guard !nearby.isEmpty else { return [measured] }
            let bound = makeSeries(
                "\(kind.rawValue)-bound", title: L10n.format("{1} · Time upper bounds", title),
                unit: .elapsedSeconds, points: nearby, comparesMedians: false
            )
            return [measured, bound]
        }
    }

    private func runPoint(_ result: RunningPerformance.BestTime) -> PerformancePoint {
        let isBound = result.coverage == .nearWholeActivity
        let seconds = isBound ? result.elapsedSeconds.rounded(.up) : result.elapsedSeconds
        let clock = text(seconds, unit: .elapsedSeconds)
        let source = result.run.source.displayName
        let observedMeters = format.number(result.observedDistanceMeters, maxFractionDigits: 2)
        return PerformancePoint(
            id: .run(result.run), date: result.run.startedAt, value: result.elapsedSeconds,
            valueText: isBound ? L10n.format("≤ {1}", clock) : clock,
            detail: isBound ? L10n.format("{1} · Observed at {2} m", source, observedMeters)
                : result.coverage == .trackSamples ? L10n.format("{1} · From the recorded track", source) : source
        )
    }

    func heartRate(
        _ segments: [ComparableRunningHeartRate.Segment], now: Date, calendar: Calendar
    ) -> PerformanceSeries? {
        guard let comparison = ComparableRunningHeartRate.compare(segments: segments, window: window) else {
            return nil
        }
        let pace = comparison.paceSecondsPerKilometer
        let band = L10n.format(
            "{1}–{2} /km", text(pace.lowerBound, unit: .elapsedSeconds), text(pace.upperBound, unit: .elapsedSeconds)
        )
        let points = comparison.segments.map { segment in
            PerformancePoint(
                id: .run(segment.run), date: segment.run.startedAt, value: segment.heartRateBPM,
                valueText: text(segment.heartRateBPM, unit: .heartRate), detail: segment.run.source.displayName
            )
        }
        let observations = comparison.segments.map { segment in
            PerformanceTrend.Observation(
                sessionID: "\(segment.run.source.rawValue):\(segment.run.id)", date: segment.run.startedAt,
                value: segment.heartRateBPM, comparisonKey: band
            )
        }
        let label = PerformanceTrend.runningHeartRate(
            observations, through: now, windowDays: window.days, calendar: calendar
        )
        var series = makeSeries("heart-rate", title: band, unit: .heartRate, points: points)
        series.trend = trendText(label)
        if let cadence = comparison.cadenceStepsPerMinute {
            series.context = L10n.format("Median cadence {1} steps/min", format.number(cadence))
        }
        return series
    }

    private func runTitle(_ kind: RunActivity.Kind) -> String {
        switch kind {
        case .race: L10n.text("Recorded race")
        case .training: L10n.text("Outdoor training")
        case .treadmill: L10n.text("Treadmill")
        case .unknown: L10n.text("Run type unknown")
        }
    }

    /// One option per exercise, the most trained in the period first.
    func strengthOptions(
        _ sets: [StrengthPerformance.RecordedSet], exercises: [Exercise]
    ) -> [StrengthPerformanceOption] {
        let names = Exercise.displayNames(exercises)
        let byExercise = Dictionary(grouping: sets, by: \.exerciseID)
        let options = exercises.compactMap { exercise -> RankedLift? in
            guard let exerciseSets = byExercise[exercise.id] else { return nil }
            let visible = exerciseSets.filter { window.includes($0.date) }
            guard !visible.isEmpty else { return nil }
            let sessions = { (sets: [StrengthPerformance.RecordedSet]) in Set(sets.map(\.sessionID)).count }
            let sources = DataSourceKind.allCases
                .map { source in (source, visible.filter { $0.source == source }) }
                .filter { !$0.1.isEmpty }
                .sorted { sessions($0.1) > sessions($1.1) }
                .map(\.0)
            let option = StrengthPerformanceOption(
                id: exercise.id.uuidString, title: names[exercise.id] ?? exercise.name, sources: sources,
                exercise: exercise, sets: exerciseSets
            )
            return RankedLift(option: option, count: sessions(visible), last: visible.map(\.date).max() ?? .distantPast)
        }
        return options.sorted {
            ($0.count, $0.last) != ($1.count, $1.last)
                ? ($0.count, $0.last) > ($1.count, $1.last)
                : $0.option.title.localizedStandardCompare($1.option.title) == .orderedAscending
        }.map(\.option)
    }

    func strengthSeries(
        _ option: StrengthPerformanceOption, source: DataSourceKind? = nil, profile: AthleteProfile?, now: Date,
        calendar: Calendar
    ) -> [PerformanceSeries] {
        let exercise = option.exercise
        let chosen = source ?? option.sources.first
        let sets = option.sets.filter { $0.source == chosen }
        let visible = sets.filter { window.includes($0.date) }
        var series = [
            record(.heaviestLoad, id: "heaviest", title: L10n.text("Heaviest set"), in: sets),
            record(.measuredOneRepMax, id: "max", title: L10n.text("Recorded max single"), in: sets)
        ]
        let estimates = StrengthPerformance.estimatedOneRepMax(in: sets, exercise: exercise)
        var estimated = makeSeries(
            "estimated", title: L10n.text("Estimated 1RM"), unit: .weight,
            points: estimates.map { strengthPoint($0.set, value: $0.weightKg, unit: .weight) },
            estimated: true
        )
        let observations = estimates.map {
            PerformanceTrend.Observation(
                sessionID: $0.set.sessionID.uuidString, date: $0.set.date, value: $0.weightKg,
                comparisonKey: "\($0.set.exerciseID):\($0.set.source.rawValue):\($0.equationVersion)"
            )
        }
        let trend = PerformanceTrend.strength(
            observations, context: .init(through: now, profile: profile, calendar: calendar)
        )
        estimated.trend = trendText(trend)
        if sets.first?.source == .app, StrengthPerformance.equationVersion(for: exercise) != nil {
            series.append(estimated)
        }
        for reps in Set(visible.map(\.reps)).sorted() {
            series.append(record(
                .loadAtReps(reps), id: "reps-\(reps)", title: L10n.format("Heaviest at {1} reps", String(reps)),
                in: sets
            ))
        }
        var shownLoads: Set<String> = []
        for load in Set(visible.map(\.weightKg)).sorted() where shownLoads.insert(format.weight(load)).inserted {
            series.append(record(
                .repsAtLoad(load), id: "weight-\(load)",
                title: L10n.format("Most reps at {1}", format.weight(load)), in: sets, unit: .reps
            ))
        }
        return series.filter { !$0.points.isEmpty || $0.isEstimated }
    }

    private func record(
        _ metric: StrengthPerformance.Record, id: String, title: String,
        in sets: [StrengthPerformance.RecordedSet], unit: PerformanceSeries.Unit = .weight
    ) -> PerformanceSeries {
        let results = StrengthPerformance.records(in: sets, matching: metric)
        return makeSeries(id, title: title, unit: unit, points: results.map {
            strengthPoint($0, value: unit == .reps ? Double($0.reps) : $0.weightKg, unit: unit)
        })
    }

    private func strengthPoint(
        _ set: StrengthPerformance.RecordedSet, value: Double, unit: PerformanceSeries.Unit
    ) -> PerformancePoint {
        var detail = L10n.format("{1} reps at {2}", String(set.reps), format.weight(set.weightKg))
        if let rpe = set.rpe {
            detail = L10n.format("{1} · RPE {2}", detail, format.number(rpe))
        }
        return PerformancePoint(
            id: .strength(sessionID: set.sessionID, setID: set.setID), date: set.date, value: value,
            valueText: text(value, unit: unit), detail: detail
        )
    }

    func makeSeries(
        _ id: String, title: String, unit: PerformanceSeries.Unit, points: [PerformancePoint],
        estimated: Bool = false, comparesMedians: Bool = true, includesPrevious: Bool = false
    ) -> PerformanceSeries {
        let visible = points.filter { includesPrevious ? window.contains($0.date) : window.includes($0.date) }
            .sorted { $0.date < $1.date }
        let best = unit == .heartRate ? nil : visible.min { left, right in
            unit == .elapsedSeconds ? left.value < right.value : left.value > right.value
        }
        let summary = window.summarize(points, date: \.date, value: \.value)
        let counts = L10n.format(
            "Sessions this period {1} · Previous period {2}",
            String(summary.currentCount), String(summary.previousCount)
        )
        let comparison: String
        if comparesMedians, let delta = summary.delta {
            let direction = delta < 0 ? "−" : delta > 0 ? "+" : ""
            comparison = L10n.format("Median change {1} · {2}", direction + text(abs(delta), unit: unit), counts)
        } else {
            comparison = counts
        }
        return PerformanceSeries(
            id: id, title: title, unit: unit, isEstimated: estimated, points: visible, best: best,
            comparison: comparison
        )
    }

    private func text(_ value: Double, unit: PerformanceSeries.Unit) -> String {
        switch unit {
        case .elapsedSeconds: format.minutesAndSeconds(Int(value.rounded()))
        case .weight: format.weight(value)
        case .reps: L10n.format("{1} reps", format.number(value))
        case .heartRate: format.number(value) + " bpm"
        }
    }

    func trendText(_ label: PerformanceTrend.Label) -> String {
        switch label {
        case .insufficientEvidence: L10n.text("Insufficient evidence for a trend")
        case .improving: L10n.text("Improving")
        case .withinVariability: L10n.text("Within normal variability")
        case .declining: L10n.text("Declining")
        case .possiblePlateau: L10n.text("Possible plateau")
        }
    }
}
