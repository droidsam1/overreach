import PresentationKit
import Testing

@Suite("L10n")
struct L10nTests {
    @Test func fillsValuesInAnyOrder() {
        #expect(L10n.format("{2} before {1}, {2} again", "first", 2) == "2 before first, 2 again")
    }

    @Test func leavesUnknownPlaceholdersAndValueTextAlone() {
        #expect(L10n.format("{1} and {3} {x}", "{2}", "second") == "{2} and {3} {x}")
    }
}
