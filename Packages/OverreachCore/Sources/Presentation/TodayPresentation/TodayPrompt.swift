/// The one secondary prompt Today shows under the hero (ADR-0041, rule 2).
public enum TodayPrompt: Int, CaseIterable, Comparable, Sendable {
    case sourceFailure, confirmBreak, dogRun, checkIn, connectHealth, connectGarmin, dogWalk, profileQuestion

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// What is true on Today right now; the priority rule only reads this.
    struct Facts: Equatable {
        var sourceFailure = false
        var confirmBreak = false
        var dogRun = false
        var checkIn = false
        var connectHealth = false
        var connectGarmin = false
        var dogWalk = false
        var profileQuestion = false
        /// The prompt the primary action already shows, which is never repeated.
        var shownByPrimary: TodayPrompt?
    }

    /// A source failure or break confirmation takes precedence over the recent run question, which expires in
    /// two days. The remaining prompts follow in case order (ADR-0041).
    static func next(_ facts: Facts) -> TodayPrompt? {
        let applicable: [TodayPrompt: Bool] = [
            .sourceFailure: facts.sourceFailure, .confirmBreak: facts.confirmBreak, .dogRun: facts.dogRun,
            .checkIn: facts.checkIn,
            .connectHealth: facts.connectHealth, .connectGarmin: facts.connectGarmin, .dogWalk: facts.dogWalk,
            .profileQuestion: facts.profileQuestion
        ]
        return allCases.first { applicable[$0] == true && $0 != facts.shownByPrimary }
    }
}
