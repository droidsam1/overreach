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

/// Optional first-run setup (issue #18): a short visual tour of what the app does, then the two questions the first
/// recommendation needs: the goal and the devices (ADR-0041, rule 5). The devices step ends with how to start (train,
/// import history, restore a backup). Every page and step can be skipped. Other profile questions are asked later
/// on Today, when their answer would change a recommendation, and can be edited in Settings. Setup is only
/// offered on a device with no training data, so it never interrupts an existing user or a restore.
/// Connecting Apple Health or Garmin from the devices step is wired by the App.
@MainActor
@Observable
public final class OnboardingModel {
    public enum Step: Int, CaseIterable, Hashable, Sendable {
        case goal, devices
    }

    /// The tour shown before the data steps on a first launch.
    public enum TourPage: Int, CaseIterable, Hashable, Sendable {
        case welcome, logging, coaching, assistant, recovery, safety
    }

    public var isPresented = false
    public private(set) var step: Step = .goal
    /// The tour page on screen; `nil` once the tour is over or skipped (the data steps show).
    public private(set) var tourPage: TourPage?
    public private(set) var errorMessage: String?

    public var goalKind: TrainingGoal.Kind?
    /// Devices picked on the devices step. Empty: only the iPhone.
    public private(set) var wearables: Set<Wearable> = []

    public let goalOptions: [Option<TrainingGoal.Kind>] = TrainingGoal.Kind.allCases.map {
        Option(value: $0, name: $0.displayName)
    }
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

    /// "Step 1 of 2"
    public var progressText: String {
        L10n.format("Step {1} of {2}", step.rawValue + 1, Step.allCases.count)
    }

    public var canGoBack: Bool { step == .devices }

    /// Position of the tour page, for the page dots.
    public var tourIndex: Int { tourPage?.rawValue ?? TourPage.allCases.count }
    public var tourCount: Int { TourPage.allCases.count }
    public var isLastTourPage: Bool { tourPage == TourPage.allCases.last }
    public var canGoBackInTour: Bool { (tourPage?.rawValue ?? 0) > 0 }
    /// The last step ends with the ways to start instead of "Continue".
    public var isLastStep: Bool { step == .devices }
    public var canSkipStep: Bool { !isLastStep }
    /// The devices step: Apple Watch, Garmin, another watch. "Only my iPhone" is the empty choice.
    public let wearableOptions: [Wearable] = Wearable.allCases
    public var usesOnlyPhone: Bool { wearables.isEmpty }
    public func isSelected(_ wearable: Wearable) -> Bool { wearables.contains(wearable) }
    /// Garmin was picked: the step offers to connect it now (or later from Today or Settings).
    public var offersGarminSetup: Bool { wearables.contains(.garmin) }
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
            profile = stored
            goalKind = stored.goal?.kind
            wearables = stored.wearables
            step = .goal
            tourPage = .welcome
            isPresented = true
        } catch {
            // The app works without the setup: it is offered again next time.
        }
    }

    /// Next tour page, or the first data step after the last one.
    public func nextTourPage() {
        guard let tourPage else { return }
        self.tourPage = TourPage(rawValue: tourPage.rawValue + 1)
    }

    public func previousTourPage() {
        guard let tourPage, tourPage.rawValue > 0 else { return }
        self.tourPage = TourPage(rawValue: tourPage.rawValue - 1)
    }

    /// Goes straight to the data steps.
    public func skipTour() {
        tourPage = nil
    }

    /// Picks or unpicks a device on the devices step.
    public func toggle(_ wearable: Wearable) {
        if wearables.contains(wearable) {
            wearables.remove(wearable)
        } else {
            wearables.insert(wearable)
        }
    }

    /// "Only my iPhone": no watch.
    public func chooseOnlyPhone() {
        wearables = []
    }

    public func next() {
        step = .devices
    }

    public func back() {
        step = .goal
    }

    /// Leaves this step's stored answers as they were and moves on.
    public func skipStep() {
        guard canSkipStep else { return }
        goalKind = profile.goal?.kind
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
        updated.wearables = wearables
        return updated
    }
}
