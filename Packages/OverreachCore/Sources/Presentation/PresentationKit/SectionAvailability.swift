import Foundation

/// Which sections of Today and "Recovery & Progress" have data worth showing (ADR-0041, rule 6). One pure rule per
/// section: an empty section never renders, and a single line names what unlocks it.
public enum SectionAvailability {
    /// The Recovery row: at least one reading (HRV, resting heart rate or sleep) exists.
    public static func recovery(readings: Int) -> Bool { readings >= 1 }

    /// Recent load: at least one row of load (logged sessions, runs or everyday movement) to compare.
    public static func recentLoad(rows: Int) -> Bool { rows >= 1 }

    /// Progress: a goal, or a lift trained in at least two sessions.
    public static func progress(hasGoal: Bool, sessionsOfMostTrainedLift: Int) -> Bool {
        hasGoal || sessionsOfMostTrainedLift >= 2
    }

    /// The history link on Today: there is something recorded to look back at.
    public static func history(sessions: Int, runs: Int) -> Bool { sessions + runs >= 1 }

    /// Charts: a chart renders only when it has points.
    public static func charts(withData count: Int) -> Bool { count >= 1 }

    /// "What appears here": one line for a screen where no section is available, naming the action that unlocks it.
    public static func unlockHint(recovery: Bool, recentLoad: Bool, progress: Bool) -> String? {
        guard !(recovery || recentLoad || progress) else { return nil }
        return L10n.text("Connect a source or log a workout to see recovery and load here.")
    }
}
