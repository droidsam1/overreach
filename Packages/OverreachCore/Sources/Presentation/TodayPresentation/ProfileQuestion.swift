import Domain
import Foundation
import Observation
import PresentationKit

/// A profile question Today asks in context instead of in onboarding (ADR-0041, rule 5): it appears as the pending
/// prompt only when the answer would change a recommendation and the field is still empty.
public enum ProfileQuestion: String, Codable, CaseIterable, Sendable {
    /// Whether recovery should account for a menstrual cycle (phase-aware HRV and resting heart rate baselines).
    case cycleTracking
    /// Whether the walks Health shows are dog walks, which unlocks "With your dog?" on each walk.
    case walkingRoutine

    /// Walks in the last two weeks needed before the walking question is worth asking.
    static let walksNeeded = 3
    static let walkWindowDays = 14

    /// What Today knows when it decides which question is due.
    struct Facts {
        var profile: AthleteProfile
        /// HRV or resting heart rate is part of the readiness reading, so a cycle would change how it is compared.
        var hasRecoveryReadings: Bool
        /// Walks found in the last `walkWindowDays` days.
        var recentWalks: Int
    }

    /// The first question that is relevant, still unanswered and not postponed today.
    @MainActor
    static func next(_ facts: Facts, today: CalendarDay, log: ProfileQuestionLog) -> ProfileQuestion? {
        allCases.first { question in
            question.isRelevant(facts) && !log.isAnswered(question) && !log.isPostponed(question, on: today)
        }
    }

    func isRelevant(_ facts: Facts) -> Bool {
        switch self {
        case .cycleTracking:
            // Only people who never said anything about their sex: "female" was asked about the cycle in the
            // setup, "male" and "prefer not to say" have nothing to answer.
            facts.profile.sex == nil && facts.profile.cycleTracking == .off && facts.hasRecoveryReadings
        case .walkingRoutine:
            facts.profile.walkingRoutine == WalkingRoutine() && facts.recentWalks >= Self.walksNeeded
        }
    }

    /// The card Today shows for this question.
    public var card: ProfileQuestionCard {
        switch self {
        case .cycleTracking:
            ProfileQuestionCard(
                question: self,
                title: L10n.text("Should recovery account for a menstrual cycle?"),
                detail: L10n.text(
                    "Context for reading HRV and resting heart rate, never a fixed rule. It stays on your device."
                ),
                answers: [CycleTrackingMode.naturalCycle, .hormonalContraception, .menopause].map {
                    ProfileQuestionCard.Answer(id: $0.rawValue, title: $0.displayName)
                } + [ProfileQuestionCard.Answer(id: ProfileQuestionCard.noAnswer, title: L10n.text("Not for me"))]
            )
        case .walkingRoutine:
            ProfileQuestionCard(
                question: self,
                title: L10n.text("Do you walk a dog?"),
                detail: L10n.text("Your recent walks are in Health. The advice can ask which ones were with your dog."),
                answers: [
                    ProfileQuestionCard.Answer(id: ProfileQuestionCard.yesAnswer, title: L10n.text("Yes")),
                    ProfileQuestionCard.Answer(id: ProfileQuestionCard.noAnswer, title: L10n.text("No"))
                ]
            )
        }
    }

    /// The profile after this answer; `nil` when the answer changes nothing.
    func apply(answer: String, to profile: AthleteProfile) -> AthleteProfile? {
        var updated = profile
        switch self {
        case .cycleTracking:
            guard let mode = CycleTrackingMode(rawValue: answer), mode != .off else { return nil }
            updated.cycleTracking = mode
        case .walkingRoutine:
            guard answer == ProfileQuestionCard.yesAnswer else { return nil }
            updated.walkingRoutine.hasDog = true
        }
        return updated
    }
}

/// The question on screen with the answers it offers.
public struct ProfileQuestionCard: Equatable, Sendable {
    public struct Answer: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
    }

    static let noAnswer = "no"
    static let yesAnswer = "yes"

    public let question: ProfileQuestion
    public let title: String
    public let detail: String
    public let answers: [Answer]
}

/// Which profile questions were answered or put off, kept on the device (not in backups, reports or the profile).
/// An answered question is never asked again; "Later" hides it for the rest of the day.
@MainActor
public final class ProfileQuestionLog {
    public struct State: Codable, Equatable, Sendable {
        var answered: Set<ProfileQuestion> = []
        /// The day each question was postponed, by raw value.
        var postponed: [String: CalendarDay] = [:]

        public init() {}
    }

    public private(set) var state: State
    private let save: @MainActor (State) -> Void

    public init(_ state: State = State(), save: @escaping @MainActor (State) -> Void = { _ in }) {
        self.state = state
        self.save = save
    }

    func isAnswered(_ question: ProfileQuestion) -> Bool { state.answered.contains(question) }

    func isPostponed(_ question: ProfileQuestion, on day: CalendarDay) -> Bool {
        state.postponed[question.rawValue] == day
    }

    func answer(_ question: ProfileQuestion) {
        state.answered.insert(question)
        state.postponed[question.rawValue] = nil
        save(state)
    }

    func postpone(_ question: ProfileQuestion, on day: CalendarDay) {
        state.postponed[question.rawValue] = day
        save(state)
    }
}
