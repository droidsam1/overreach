import Domain
import Foundation
import Observation
import PresentationKit

/// One highlight of a release, for the "What's new" screen.
public struct ReleaseHighlight: Identifiable, Hashable, Sendable {
    public let symbol: String
    public let title: String
    public let detail: String
    public var id: String { symbol + title }
}

/// The highlights of one app version. Each release adds its entry to `ReleaseNotes.all` (newest first).
public struct ReleaseNotes: Hashable, Sendable {
    public let version: String
    public let highlights: [ReleaseHighlight]

    public static var all: [ReleaseNotes] {
        [
            ReleaseNotes(version: "0.1.0", highlights: [
                ReleaseHighlight(
                    symbol: "applewatch.radiowaves.left.and.right", title: L10n.text("Your watch in History"),
                    detail: L10n.text(
                        "Sessions your watch also recorded show its heart rate and load. Workouts recorded but not "
                            + "logged appear in History, ready to log."
                    )
                ),
                ReleaseHighlight(
                    symbol: "applewatch.radiowaves.left.and.right", title: L10n.text("Garmin connection"),
                    detail: L10n.text(
                        "Nightly HRV, sleep score, Body Battery and runs from your Garmin, with your own key. "
                            + "Settings → Garmin: three steps."
                    )
                ),
                ReleaseHighlight(
                    symbol: "face.smiling", title: L10n.text("Daily check-in"),
                    detail: L10n.text("Ten seconds on Today: energy, soreness or sick. The readiness light takes it into account.")
                ),
                ReleaseHighlight(
                    symbol: "circle.hexagongrid.fill", title: L10n.text("Readiness light"),
                    detail: L10n.text(
                        "Today says whether to train hard, easy or rest, from your HRV, resting HR, sleep and check-in, with the reasons."
                    )
                ),
                ReleaseHighlight(
                    symbol: "calendar.badge.clock", title: L10n.text("Train your plan"),
                    detail: L10n.text("Import a multi-week plan from your AI. Train shows the next session.")
                ),
                ReleaseHighlight(
                    symbol: "calendar", title: L10n.text("History calendar"),
                    detail: L10n.text("Strength days, runs and steps month by month, with each day's details.")
                ),
                ReleaseHighlight(
                    symbol: "list.bullet.clipboard.fill", title: L10n.text("Session summary"),
                    detail: L10n.text("After each session: plan adherence, records and next targets. Reopen it from History.")
                ),
                ReleaseHighlight(
                    symbol: "flame.fill", title: L10n.text("Warm-up sets"),
                    detail: L10n.text("Suggested ramps for main lifts and the first exercise for each muscle.")
                ),
                ReleaseHighlight(
                    symbol: "gauge.with.dots.needle.50percent", title: L10n.text("Effort your way"),
                    detail: L10n.text("Log RPE or reps in reserve, with a guide to rate it well.")
                ),
                ReleaseHighlight(
                    symbol: "exclamationmark.bubble.fill", title: L10n.text("Clearer advice"),
                    detail: L10n.text("Targets say what to do today, and stalls explain why and what to try.")
                ),
                ReleaseHighlight(
                    symbol: "bubble.left.and.text.bubble.right.fill", title: L10n.text("Plan with your AI"),
                    detail: L10n.text("Share your data with ChatGPT or Claude and bring routines back.")
                ),
                ReleaseHighlight(
                    symbol: "lock.icloud.fill", title: L10n.text("Safer data"),
                    detail: L10n.text("Backup reminders, restore during setup, and data that stays readable in future versions.")
                ),
                ReleaseHighlight(
                    symbol: "circle.lefthalf.filled", title: L10n.text("Dark mode"),
                    detail: L10n.text("Choose light, dark or the same as the iPhone in Settings.")
                ),
            ]),
        ]
    }
}

/// "What's new" after an update: the highlights of every version since the last one the user saw. New installs
/// are not shown it (the first-run tour covers that); people who used an earlier build are.
@MainActor
@Observable
public final class WhatsNewModel {
    public var isPresented = false
    /// "What's new in 0.2.0".
    public private(set) var title = ""
    public private(set) var highlights: [ReleaseHighlight] = []

    private let status: any OnboardingStatusStore
    private let workouts: any WorkoutRepository
    private let currentVersion: String?
    private let notes: [ReleaseNotes]

    public init(
        status: any OnboardingStatusStore,
        workouts: any WorkoutRepository,
        currentVersion: String?,
        notes: [ReleaseNotes] = ReleaseNotes.all
    ) {
        self.status = status
        self.workouts = workouts
        self.currentVersion = currentVersion
        self.notes = notes
    }

    /// At launch, when the first-run setup is not showing.
    public func checkAtLaunch() async {
        guard let currentVersion, !isPresented else { return }
        let lastSeen = await status.lastSeenReleaseNotesVersion()
        if lastSeen == nil {
            let sessions = (try? await workouts.sessions(from: .distantPast, to: .distantFuture)) ?? []
            guard !sessions.isEmpty else {
                await status.markReleaseNotesSeen(version: currentVersion)  // a new user: the tour covers it
                return
            }
        }
        let current = Self.components(currentVersion)
        let seen = Self.components(lastSeen ?? "0")
        // Versions after the last one seen, up to the running one.
        let pending = notes.filter { note in
            let version = Self.components(note.version)
            return !current.lexicographicallyPrecedes(version) && seen.lexicographicallyPrecedes(version)
        }
        guard !pending.isEmpty else {
            await status.markReleaseNotesSeen(version: currentVersion)
            return
        }
        highlights = pending.flatMap(\.highlights)
        title = L10n.format("What's new in {1}", currentVersion)
        isPresented = true
    }

    /// The first-run setup is showing: this version's news is part of it.
    public func markCurrentAsSeen() async {
        guard let currentVersion else { return }
        await status.markReleaseNotesSeen(version: currentVersion)
    }

    public func dismiss() async {
        isPresented = false
        await markCurrentAsSeen()
    }

    /// "0.10.1" → [0, 10, 1, 0]: numeric parts, padded so versions compare as numbers.
    static func components(_ version: String) -> [Int] {
        let parts = version.split(separator: ".").map { Int($0) ?? 0 }
        return parts + Array(repeating: 0, count: max(0, 4 - parts.count))
    }
}
