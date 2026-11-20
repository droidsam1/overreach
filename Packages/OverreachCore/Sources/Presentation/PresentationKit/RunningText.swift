import Domain
import Foundation

extension PlannedRun.Purpose {
    public var displayName: String {
        switch self {
        case .easy: L10n.text("Easy run")
        case .intervals: L10n.text("Intervals")
        case .tempo: L10n.text("Tempo run")
        case .long: L10n.text("Long run")
        case .race: L10n.text("Race")
        case .rest: L10n.text("Rest day")
        }
    }
}

extension RunningGoal {
    public func displayName(format: Format = Format()) -> String {
        let distance = format.number(Double(distanceMeters) / 1_000, maxFractionDigits: 3)
        return switch (targetSeconds, aimsForPainFree) {
        case (let seconds?, true):
            L10n.format("Run {1} km in {2} without pain", distance, format.minutesAndSeconds(seconds))
        case (let seconds?, false):
            L10n.format("Run {1} km in {2}", distance, format.minutesAndSeconds(seconds))
        case (nil, true): L10n.format("Run {1} km without pain", distance)
        case (nil, false): L10n.format("Finish {1} km", distance)
        }
    }
}
