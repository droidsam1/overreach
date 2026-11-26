import Analytics
import Domain
import Foundation
import Observation
import PresentationKit

/// What the rest timer shows at one moment.
public struct RestTimerState: Hashable, Sendable {
    public let exerciseName: String
    /// "1:30"
    public let remaining: String
    /// Share of the rest already elapsed, from 0 to 1.
    public let progress: Double
    public let isFinished: Bool
    /// "Rest" while counting down, "Rest over" at the end.
    public let title: String
    /// "Skip" while counting down, "Dismiss" at the end.
    public let dismissTitle: String
    /// "Suggested 3:00–5:00 · moderate evidence (rest-strength)"
    public let suggestion: String
}

/// The rest between sets (issue #16). It stores when the rest ends, so it stays right while the app is suspended.
@MainActor
@Observable
public final class RestTimerModel {
    private struct Running {
        var draft: RestTimerDraft
        let exerciseName: String
        let suggestion: String
    }

    private static let stepSeconds = 15

    private var running: Running? {
        didSet { onChange?() }
    }
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var alertTask: Task<Void, Never>?

    private let alerts: (any RestAlertScheduler)?
    private let clock: @Sendable () -> Date
    private let format = Format()

    init(alerts: (any RestAlertScheduler)?, clock: @escaping @Sendable () -> Date) {
        self.alerts = alerts
        self.clock = clock
    }

    // MARK: Screen state

    public var isActive: Bool { running != nil }

    var draft: RestTimerDraft? { running?.draft }

    public func state(at date: Date) -> RestTimerState? {
        guard let running else { return nil }
        let seconds = max(0, Int(running.draft.endsAt.timeIntervalSince(date).rounded(.up)))
        let isFinished = seconds == 0
        return RestTimerState(
            exerciseName: running.exerciseName,
            remaining: format.minutesAndSeconds(seconds),
            progress: 1 - min(1, Double(seconds) / Double(max(1, running.draft.durationSeconds))),
            isFinished: isFinished,
            title: isFinished ? L10n.text("Rest over") : L10n.text("Rest"),
            dismissTitle: isFinished ? L10n.text("Dismiss") : L10n.text("Skip"),
            suggestion: running.suggestion
        )
    }

    // MARK: Intents

    public func addTime() { adjust(by: Self.stepSeconds) }

    public func removeTime() { adjust(by: -Self.stepSeconds) }

    public func skip() { stop() }

    /// Waits until the system alert matches the timer.
    public func alertsSettled() async { await alertTask?.value }

    // MARK: Driven by the session

    /// Starts the suggested rest for the exercise's focus, replacing any rest in progress.
    func start(after setID: DraftSet.ID, of exercise: DraftExercise) {
        let duration = exercise.prescribedRestSeconds
            ?? FocusPrescription.for(exercise.focus ?? .hypertrophy).defaultRestSeconds
        let draft = RestTimerDraft(
            setID: setID, exerciseID: exercise.id, endsAt: clock().addingTimeInterval(TimeInterval(duration)),
            durationSeconds: duration
        )
        restore(draft, for: exercise)
    }

    func restore(_ draft: RestTimerDraft, for exercise: DraftExercise) {
        let prescription = FocusPrescription.for(exercise.focus ?? .hypertrophy)
        let range = prescription.restSeconds
        let evidence = prescription.restEvidence
        let suggestion = if let seconds = exercise.prescribedRestSeconds {
            L10n.format("Routine rest {1}", format.minutesAndSeconds(seconds))
        } else {
            L10n.format(
                "Suggested {1}–{2} · {3} ({4})", format.minutesAndSeconds(range.lowerBound),
                format.minutesAndSeconds(range.upperBound), evidence.level.displayName, evidence.key
            )
        }
        running = Running(draft: draft, exerciseName: exercise.name, suggestion: suggestion)
        if draft.endsAt > clock() {
            scheduleAlert()
        }
    }

    func stop(cancelPendingAlert: Bool = false) {
        guard running != nil || cancelPendingAlert else { return }
        running = nil
        enqueueAlert { await $0.cancelRestEnd() }
    }

    /// Stops the rest started by this set, if any.
    func stop(setID: DraftSet.ID) {
        if running?.draft.setID == setID { stop() }
    }

    func stop(exerciseID: DraftExercise.ID) {
        if running?.draft.exerciseID == exerciseID { stop() }
    }

    // MARK: Helpers

    private func adjust(by seconds: Int) {
        guard var current = running else { return }
        let now = clock()
        let remaining = max(0, current.draft.endsAt.timeIntervalSince(now)) + TimeInterval(seconds)
        guard remaining > 0 else {
            stop()
            return
        }
        current.draft.endsAt = now.addingTimeInterval(remaining)
        current.draft.durationSeconds = max(current.draft.durationSeconds, Int(remaining.rounded(.up)))
        running = current
        scheduleAlert()
    }

    private func scheduleAlert() {
        guard let running else { return }
        let date = running.draft.endsAt
        let title = L10n.text("Rest over")
        let body = L10n.format("Next set: {1}", running.exerciseName)
        enqueueAlert { await $0.scheduleRestEnd(at: date, title: title, body: body) }
    }

    /// Runs alert changes one at a time, so the system always ends up with the latest one.
    private func enqueueAlert(_ change: @escaping @Sendable (any RestAlertScheduler) async -> Void) {
        guard let alerts else { return }
        let previous = alertTask
        alertTask = Task {
            await previous?.value
            await change(alerts)
        }
    }
}
