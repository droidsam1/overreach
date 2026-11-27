import XCTest

@MainActor
final class PlanAuditUITests: XCTestCase {
    func testFindingShowsEvidenceAndCanBeDismissedAtLargestTextSize() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "-ui-testing-plan", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()

        let plan = app.tabBars.buttons["Plan"]
        XCTAssertTrue(plan.waitForExistence(timeout: 10))
        plan.tap()
        let block = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Current block")).firstMatch
        for _ in 0..<6 where !block.isHittable { app.swipeUp() }
        XCTAssertTrue(block.isHittable)
        block.tap()

        let finding = "No upper-body strength sets."
        let dismiss = app.buttons["Dismiss finding: \(finding)"]
        for _ in 0..<12 where !dismiss.isHittable { app.swipeUp() }
        XCTAssertTrue(dismiss.isHittable)
        XCTAssertGreaterThanOrEqual(dismiss.frame.height, 44)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", finding, "Evidence: coaching heuristic"
        )).firstMatch.exists)

        dismiss.tap()
        XCTAssertFalse(dismiss.exists)
    }
}
