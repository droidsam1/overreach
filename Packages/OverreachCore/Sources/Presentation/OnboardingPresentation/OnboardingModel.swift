import Domain
import Foundation
import Observation
import PresentationKit

/// Where the user goes after the setup.
public enum OnboardingDestination: Hashable, Sendable {
    case train, importHistory
    /// Restore a backup: Settings opens the folder picker.
    case restoreBackup
}

/// Optional first-run setup (issue #18). Every step can be skipped, and it can be reopened from Settings.
/// It is only offered on a device with no training data, so it never interrupts an existing user or a restore.
@MainActor
@Observable
public final class OnboardingModel {
    public enum Step: Int, CaseIterable, Hashable, Sendable {
        case goal, about, walking, start
    }

    public var isPresented = false
    public private(set) var step: Step = .goal
    public private(set) var errorMessage: String?

    public var goalKind: TrainingGoal.Kind?
    public var sex: BiologicalSex? {
        didSet {
            if sex == .male || sex == .unspecified { cycleTracking = .off }
        }
    }
    public var cycleTracking: CycleTrackingMode = .off
    public var hasDog = false
    public var usualWalksPerDay: Int?
    public var walksAreFixed = false
    public var canRunDuringWalks = false

    public let goalOptions: [Option<TrainingGoal.Kind>] = TrainingGoal.Kind.allCases.map {
        Option(value: $0, name: $0.displayName)
    }
    public let sexOptions: [Option<BiologicalSex>] = BiologicalSex.allCases.map {
        Option(value: $0, name: $0.displayName)
    }
    public let cycleOptions: [Option<CycleTrackingMode>] = CycleTrackingMode.allCases.map {
        Option(value: $0, name: $0.displayName)
    }
    public let walkOptions: [Option<Int>] = (0...5).map { Option(value: $0, name: String($0)) }

    private var profile = AthleteProfile()
    private let profiles: any ProfileRepository
    private let workouts: any WorkoutRepository
    private let status: any OnboardingStatusStore

    public init(
        profiles: any ProfileRepository,
        workouts: any WorkoutRepository,
        status: any OnboardingStatusStore
    ) {
        self.profiles = profiles
        self.workouts = workouts
        self.status = status
    }

    // MARK: Screen state

    /// "Step 1 of 4"
    public var progressText: String {
        L10n.format("Step {1} of {2}", step.rawValue + 1, Step.allCases.count)
    }

    public var canGoBack: Bool { step != .goal }
    public var canSkipStep: Bool { step != .start }
    public var showsCycleTracking: Bool { sex == .female }
    public var showsWalkDetails: Bool { hasDog || (usualWalksPerDay ?? 0) > 0 }

    // MARK: Intents

    /// At launch: opens the setup on a device with no data. Anyone who already has data is never asked.
    public func presentIfNeeded() async {
        guard !isPresented, await !status.isOnboardingCompleted() else { return }
        do {
            let stored = try await profiles.profile()
            let sessions = try await workouts.sessions(from: .distantPast, to: .distantFuture)
            guard sessions.isEmpty, stored == AthleteProfile() else {
                await status.markOnboardingCompleted()
                return
            }
            open(with: stored)
        } catch {
            // The app works without the setup: it is offered again next time.
        }
    }

    /// Opens the setup from Settings, with the current answers.
    public func reopen() async {
        do {
            open(with: try await profiles.profile())
        } catch {
            errorMessage = L10n.text("Could not load your profile.")
            open(with: AthleteProfile())
        }
    }

    public func next() {
        step = Step(rawValue: step.rawValue + 1) ?? step
    }

    public func back() {
        step = Step(rawValue: step.rawValue - 1) ?? step
    }

    /// Leaves this step's stored answers as they were and moves on.
    public func skipStep() {
        switch step {
        case .goal:
            goalKind = profile.goal?.kind
        case .about:
            sex = profile.sex
            cycleTracking = profile.cycleTracking
        case .walking:
            applyWalking(profile.walkingRoutine)
        case .start:
            return
        }
        next()
    }

    /// Closes the setup without saving any answer.
    public func skipSetup() async {
        await status.markOnboardingCompleted()
        isPresented = false
    }

    /// Saves the answers and closes the setup. Returns false if they could not be saved.
    public func finish() async -> Bool {
        let updated = answeredProfile
        do {
            if updated != profile {
                try await profiles.save(updated)
                profile = updated
            }
        } catch {
            errorMessage = L10n.text("Could not save your answers. Try again or skip the setup.")
            return false
        }
        errorMessage = nil
        await status.markOnboardingCompleted()
        isPresented = false
        return true
    }

    // MARK: Helpers

    private var answeredProfile: AthleteProfile {
        var updated = profile
        if let goalKind {
            var goal = updated.goal ?? TrainingGoal(kind: goalKind)
            goal.kind = goalKind
            updated.goal = goal
        }
        updated.sex = sex
        updated.cycleTracking = cycleTracking
        updated.walkingRoutine.hasDog = hasDog
        updated.walkingRoutine.usualWalksPerDay = usualWalksPerDay
        updated.walkingRoutine.walksAreFixed = showsWalkDetails && walksAreFixed
        updated.walkingRoutine.canRunDuringWalks = showsWalkDetails && canRunDuringWalks
        return updated
    }

    private func open(with stored: AthleteProfile) {
        profile = stored
        goalKind = stored.goal?.kind
        sex = stored.sex
        cycleTracking = stored.cycleTracking  // After `sex`, which can reset it.
        applyWalking(stored.walkingRoutine)
        step = .goal
        isPresented = true
    }

    private func applyWalking(_ routine: WalkingRoutine) {
        hasDog = routine.hasDog
        usualWalksPerDay = routine.usualWalksPerDay
        walksAreFixed = routine.walksAreFixed
        canRunDuringWalks = routine.canRunDuringWalks
    }
}
