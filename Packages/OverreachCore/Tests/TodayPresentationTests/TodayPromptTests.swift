import Testing
@testable import TodayPresentation

@Suite("Today: the one pending prompt")
struct TodayPromptTests {
    private func facts(_ prompts: [TodayPrompt], shownByPrimary: TodayPrompt? = nil) -> TodayPrompt.Facts {
        var facts = TodayPrompt.Facts()
        for prompt in prompts {
            switch prompt {
            case .sourceFailure: facts.sourceFailure = true
            case .confirmBreak: facts.confirmBreak = true
            case .dogRun: facts.dogRun = true
            case .checkIn: facts.checkIn = true
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

    @Test("order: source failure, break, dog run, check-in, Health, Garmin, dog walk, profile question")
    func order() {
        #expect(
            TodayPrompt.allCases
                == [.sourceFailure, .confirmBreak, .dogRun, .checkIn, .connectHealth, .connectGarmin, .dogWalk,
                    .profileQuestion]
        )
        #expect(TodayPrompt.next(facts(TodayPrompt.allCases)) == .sourceFailure)
    }

    @Test("a prompt the primary action shows is not repeated; the next one takes its place")
    func notRepeated() {
        #expect(TodayPrompt.next(facts([.checkIn, .connectHealth], shownByPrimary: .checkIn)) == .connectHealth)
        #expect(TodayPrompt.next(facts([.checkIn], shownByPrimary: .checkIn)) == nil)
    }
}
