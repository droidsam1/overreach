import Domain
import Fixtures
import Foundation
@testable import OnboardingPresentation
import Testing

@MainActor
@Suite("Tour and what's new")
struct TourAndWhatsNewTests {
    // MARK: Tour

    @Test func aFirstLaunchStartsWithTheTour() async {
        let store = TestStore()
        let model = OnboardingModel(profiles: store, workouts: store, status: store)
        await model.presentIfNeeded()

        #expect(model.tourPage == .welcome)
        #expect(model.tourIndex == 0 && model.tourCount == OnboardingModel.TourPage.allCases.count)
        #expect(!model.canGoBackInTour)

        model.nextTourPage()
        #expect(model.tourPage == .logging && model.canGoBackInTour)
        model.previousTourPage()
        #expect(model.tourPage == .welcome)

        for _ in OnboardingModel.TourPage.allCases.dropLast() { model.nextTourPage() }
        #expect(model.isLastTourPage)
        model.nextTourPage()
        #expect(model.tourPage == nil)
        #expect(model.step == .goal)
    }

    @Test func theTourCanBeSkipped() async {
        let store = TestStore()
        let model = OnboardingModel(profiles: store, workouts: store, status: store)
        await model.presentIfNeeded()
        model.skipTour()
        #expect(model.tourPage == nil)
        #expect(model.isPresented)
    }

    // MARK: What's new

    private func notes(_ versions: String...) -> [ReleaseNotes] {
        versions.map { version in
            ReleaseNotes(version: version, highlights: [
                ReleaseHighlight(symbol: "star.fill", title: "In \(version)", detail: "Detail"),
            ])
        }
    }

    private func session() -> StrengthSession {
        StrengthSession(name: "Old", startedAt: Date(timeIntervalSince1970: 0), entries: [])
    }

    @Test func showsWhatChangedSinceTheLastSeenVersion() async {
        let store = TestStore(sessions: [session()])
        await store.markReleaseNotesSeen(version: "0.1.0")
        let model = WhatsNewModel(status: store, workouts: store, currentVersion: "0.3.0",
                                  notes: notes("0.3.0", "0.2.0", "0.1.0"))
        await model.checkAtLaunch()

        #expect(model.isPresented)
        #expect(model.title == "What's new in 0.3.0")
        #expect(model.highlights.map(\.title) == ["In 0.3.0", "In 0.2.0"])

        await model.dismiss()
        #expect(!model.isPresented)
        #expect(await store.lastSeenReleaseNotesVersion() == "0.3.0")
    }

    @Test func newUsersDoNotSeeItButEarlierTestersDo() async {
        let fresh = TestStore()
        let newUser = WhatsNewModel(status: fresh, workouts: fresh, currentVersion: "0.1.0", notes: notes("0.1.0"))
        await newUser.checkAtLaunch()
        #expect(!newUser.isPresented)
        #expect(await fresh.lastSeenReleaseNotesVersion() == "0.1.0")

        let tester = TestStore(sessions: [session()])
        let existing = WhatsNewModel(status: tester, workouts: tester, currentVersion: "0.1.0", notes: notes("0.1.0"))
        await existing.checkAtLaunch()
        #expect(existing.isPresented)
    }

    @Test func nothingNewShowsNothing() async {
        let store = TestStore(sessions: [session()])
        await store.markReleaseNotesSeen(version: "0.2.0")
        let model = WhatsNewModel(status: store, workouts: store, currentVersion: "0.2.1", notes: notes("0.2.0"))
        await model.checkAtLaunch()
        #expect(!model.isPresented)
        #expect(await store.lastSeenReleaseNotesVersion() == "0.2.1")
    }

    @Test func versionsCompareAsNumbers() {
        #expect(WhatsNewModel.components("0.10.0").lexicographicallyPrecedes(WhatsNewModel.components("0.9.0")) == false)
        #expect(WhatsNewModel.components("1.2") == [1, 2, 0, 0])
    }

    @Test func everyShippedVersionHasHighlights() {
        #expect(ReleaseNotes.all.allSatisfy { !$0.highlights.isEmpty })
        #expect(ReleaseNotes.all.first?.version == "0.1.0")
    }
}
