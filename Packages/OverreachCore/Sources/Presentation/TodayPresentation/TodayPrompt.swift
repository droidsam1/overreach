/// The one secondary prompt Today shows under the hero (ADR-0041, rule 2).
public enum TodayPrompt: Int, CaseIterable, Comparable, Sendable {
    case sourceFailure, confirmBreak, checkIn, connectHealth, connectGarmin, dogWalk, profileQuestion

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// What is true on Today right now; the priority rule only reads this.
    struct Facts: Equatable {
        var sourceFailure = false
        var confirmBreak = false
        var checkIn = false
        var connectHealth = false
        var connectGarmin = false
        var dogWalk = false
        var profileQuestion = false
        /// The prompt the primary action already shows, which is never repeated.
        var shownByPrimary: TodayPrompt?
    }

    /// The first applicable prompt, in the order of the cases: a failed source that changes today's decision, the
    /// break confirmation, the check-in, connect Apple Health, connect Garmin, then contextual questions (the dog walk,
    /// then a profile question that was moved out of onboarding). Adding a
    /// prompt means placing its case here and reviewing the order (ADR-0041).
    static func next(_ facts: Facts) -> TodayPrompt? {
        let applicable: [TodayPrompt: Bool] = [
            .sourceFailure: facts.sourceFailure, .confirmBreak: facts.confirmBreak, .checkIn: facts.checkIn,
            .connectHealth: facts.connectHealth, .connectGarmin: facts.connectGarmin, .dogWalk: facts.dogWalk,
            .profileQuestion: facts.profileQuestion
        ]
        return allCases.first { applicable[$0] == true && $0 != facts.shownByPrimary }
    }
}
