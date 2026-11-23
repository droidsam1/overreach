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
/// import history, restore a backup). Every page and step can be skipped. Other profile questions are asked later on
/// Today, when their answer would change a recommendation. Settings → Training profile reopens the setup with every
/// step (without the tour). It is only offered on a device with no training data, so it never interrupts an existing
/// user or a restore.
///
/// To extend it, add a `TourPage` to show a feature or a `Step` to ask for data; the order is the order of the cases.
/// The devices step asks which watches the person uses; connecting Apple Health or Garmin from there is wired by the
/// App (the setup flows belong to other features).
@MainActor
@Observable
public final class OnboardingModel {
    public enum Step: Int, CaseIterable, Hashable, Sendable {
        case goal, about, walking, devices
    }

    /// The tour shown before the data steps on a first launch.
    public enum TourPage: Int, CaseIterable, Hashable, Sendable {
        case welcome, logging, coaching, assistant, recovery, safety
    }

    public var isPresented = false
    public private(set) var step: Step = .goal
    /// The first run asks only the goal and the devices; reopened from Settings it asks every step.
    public private(set) var isFirstRun = false
    /// The tour page on screen; `nil` once the tour is over or skipped (the data steps show).
    public private(set) var tourPage: TourPage?
    public private(set) var errorMessage: String?

    public var goalKind: TrainingGoal.Kind?
    public var sex: BiologicalSex? {
        didSet {
            if sex == .male || sex == .unspecified { cycleTracking = .off }
        }
    }
    public var cycleTracking: CycleTrackingMode = .off
    public var hasDog = false
    /// The dog's name, for the "With …?" question. Blank means no name.
    public var dogName = ""
    public var usualWalksPerDay: Int?
    public var walksAreFixed = false
    public var canRunDuringWalks = false
    /// Devices picked on the devices step. Empty: only the iPhone.
    public private(set) var wearables: Set<Wearable> = []

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

    /// The steps of this run, in order: the goal and the devices on the first run, all of them from Settings.
    public var steps: [Step] { isFirstRun ? [.goal, .devices] : Step.allCases }

    /// "Step 1 of 2"
    public var progressText: String {
        L10n.format("Step {1} of {2}", stepIndex + 1, steps.count)
    }

    public var canGoBack: Bool { stepIndex > 0 }

    /// Position of the tour page, for the page dots.
    public var tourIndex: Int { tourPage?.rawValue ?? TourPage.allCases.count }
    public var tourCount: Int { TourPage.allCases.count }
    public var isLastTourPage: Bool { tourPage == TourPage.allCases.last }
    public var canGoBackInTour: Bool { (tourPage?.rawValue ?? 0) > 0 }
    /// The last step ends with the ways to start instead of "Continue".
    public var isLastStep: Bool { step == steps.last }
    public var canSkipStep: Bool { !isLastStep }
    public var showsCycleTracking: Bool { sex == .female }
    public var showsWalkDetails: Bool { hasDog || (usualWalksPerDay ?? 0) > 0 }

    /// The devices step: Apple Watch, Garmin, another watch. "Only my iPhone" is the empty choice.
    public let wearableOptions: [Wearable] = Wearable.allCases
    public var usesOnlyPhone: Bool { wearables.isEmpty }
    public func isSelected(_ wearable: Wearable) -> Bool { wearables.contains(wearable) }
    /// Garmin was picked: the step offers to connect it now (or later from Today or Settings).
    public var offersGarminSetup: Bool { wearables.contains(.garmin) }
    /// Everything except Garmin reaches the app through Apple Health (and the iPhone counts steps itself).
    public var offersHealthAccess: Bool { true }

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
            open(with: stored, isFirstRun: true)
            tourPage = TourPage.allCases.first
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
        guard stepIndex + 1 < steps.count else { return }
        step = steps[stepIndex + 1]
    }

    public func back() {
        guard stepIndex > 0 else { return }
        step = steps[stepIndex - 1]
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
        case .devices:
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

    private var stepIndex: Int { steps.firstIndex(of: step) ?? 0 }

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
        let trimmedDogName = dogName.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.walkingRoutine.dogName = hasDog && !trimmedDogName.isEmpty ? trimmedDogName : nil
        updated.walkingRoutine.usualWalksPerDay = usualWalksPerDay
        updated.walkingRoutine.walksAreFixed = showsWalkDetails && walksAreFixed
        updated.walkingRoutine.canRunDuringWalks = showsWalkDetails && canRunDuringWalks
        updated.wearables = wearables
        return updated
    }

    private func open(with stored: AthleteProfile, isFirstRun: Bool = false) {
        self.isFirstRun = isFirstRun
        profile = stored
        goalKind = stored.goal?.kind
        sex = stored.sex
        cycleTracking = stored.cycleTracking  // After `sex`, which can reset it.
        applyWalking(stored.walkingRoutine)
        wearables = stored.wearables
        step = .goal
        tourPage = nil
        isPresented = true
    }

    private func applyWalking(_ routine: WalkingRoutine) {
        hasDog = routine.hasDog
        dogName = routine.dogName ?? ""
        usualWalksPerDay = routine.usualWalksPerDay
        walksAreFixed = routine.walksAreFixed
        canRunDuringWalks = routine.canRunDuringWalks
    }
}
