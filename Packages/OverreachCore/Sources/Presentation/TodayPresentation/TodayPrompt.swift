/// The one secondary prompt Today shows under the hero (ADR-0041, rule 2).
public enum TodayPrompt: Int, CaseIterable, Comparable, Sendable {
    case rotationOffer, sourceFailure, confirmBreak, runPain, dogRun, checkIn, runOffer, connectHealth,
         connectGarmin, dogWalk, profileQuestion

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// What is true on Today right now; the priority rule only reads this.
    struct Facts: Equatable {
        var rotationOffer = false
        var sourceFailure = false
        var confirmBreak = false
        var runPain = false
        var dogRun = false
        var checkIn = false
        var runOffer = false
        var connectHealth = false
        var connectGarmin = false
        var dogWalk = false
        var profileQuestion = false
        /// The prompt the primary action already shows, which is never repeated.
        var shownByPrimary: TodayPrompt?
    }

    /// The strength rotation offer adjusts the hero's own session, so it comes first. A source failure or break
    /// confirmation takes precedence over the recent run question, which expires in two days, and a pain report
    /// over the rest. The soft run offer waits behind the check-in, which can change it. The remaining prompts
    /// follow in case order (ADR-0041).
    static func next(_ facts: Facts) -> TodayPrompt? {
        let applicable: [TodayPrompt: Bool] = [
            .rotationOffer: facts.rotationOffer, .sourceFailure: facts.sourceFailure,
            .confirmBreak: facts.confirmBreak, .runPain: facts.runPain, .dogRun: facts.dogRun,
            .checkIn: facts.checkIn, .runOffer: facts.runOffer,
            .connectHealth: facts.connectHealth, .connectGarmin: facts.connectGarmin, .dogWalk: facts.dogWalk,
            .profileQuestion: facts.profileQuestion
        ]
        return allCases.first { applicable[$0] == true && $0 != facts.shownByPrimary }
    }
}
