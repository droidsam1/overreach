import Testing
@testable import TodayPresentation

@Suite("Today: the one pending prompt")
struct TodayPromptTests {
    private func facts(_ prompts: [TodayPrompt], shownByPrimary: TodayPrompt? = nil) -> TodayPrompt.Facts {
        var facts = TodayPrompt.Facts()
        for prompt in prompts {
            switch prompt {
            case .rotationOffer: facts.rotationOffer = true
            case .sourceFailure: facts.sourceFailure = true
            case .confirmBreak: facts.confirmBreak = true
            case .runPain: facts.runPain = true
            case .dogRun: facts.dogRun = true
            case .checkIn: facts.checkIn = true
            case .runOffer: facts.runOffer = true
            case .connectHealth: facts.connectHealth = true
            case .connectGarmin: facts.connectGarmin = true
            case .dogWalk: facts.dogWalk = true
            case .profileQuestion: facts.profileQuestion = true
            }
        }
        facts.shownByPrimary = shownByPrimary
        return facts
    }

    @Test("nothing applicable shows no prompt")
    func none() {
        #expect(TodayPrompt.next(.init()) == nil)
    }

    @Test("each prompt alone is the pending prompt")
    func alone() {
        for prompt in TodayPrompt.allCases {
            #expect(TodayPrompt.next(facts([prompt])) == prompt)
        }
    }

    @Test("for every pair the earlier prompt wins, in either input order")
    func everyPair() {
        let all = TodayPrompt.allCases
        for (index, first) in all.enumerated() {
            for second in all[(index + 1)...] {
                #expect(TodayPrompt.next(facts([first, second])) == first)
                #expect(TodayPrompt.next(facts([second, first])) == first)
            }
        }
    }

    @Test("the full priority order, from rotation offer to profile question")
    func order() {
        #expect(
            TodayPrompt.allCases
                == [.rotationOffer, .sourceFailure, .confirmBreak, .runPain, .dogRun, .checkIn, .runOffer,
                    .connectHealth, .connectGarmin, .dogWalk, .profileQuestion]
        )
        #expect(TodayPrompt.next(facts(TodayPrompt.allCases)) == .rotationOffer)
    }

    @Test("a rotation offer wins over a run pain report and the check-in")
    func rotationOfferFirst() {
        #expect(TodayPrompt.next(facts([.runPain, .rotationOffer, .checkIn])) == .rotationOffer)
    }

    @Test("a run pain report wins over the check-in, the run offer and the questions")
    func runPainBeforeTheRest() {
        #expect(TodayPrompt.next(facts([.checkIn, .runPain])) == .runPain)
        #expect(TodayPrompt.next(facts([.runOffer, .dogRun, .runPain])) == .runPain)
        #expect(TodayPrompt.next(facts([.sourceFailure, .runPain])) == .sourceFailure)
    }

    @Test("the check-in is asked before the soft run offer, which comes before connecting a source")
    func runOfferAfterCheckIn() {
        #expect(TodayPrompt.next(facts([.runOffer, .checkIn])) == .checkIn)
        #expect(TodayPrompt.next(facts([.connectHealth, .runOffer])) == .runOffer)
    }

    @Test("a prompt the primary action shows is not repeated; the next one takes its place")
    func notRepeated() {
        #expect(TodayPrompt.next(facts([.checkIn, .connectHealth], shownByPrimary: .checkIn)) == .connectHealth)
        #expect(TodayPrompt.next(facts([.checkIn], shownByPrimary: .checkIn)) == nil)
    }
}
