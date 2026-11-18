import Testing
import TodayPresentation

@MainActor
@Suite("Today empty state")
struct TodayEmptyStateTests {
    @Test func explainsWhyThereIsNoData() async {
        let model = TodayModel(sources: [])

        await model.load()

        #expect(model.showsNoDataHint)
    }
}
