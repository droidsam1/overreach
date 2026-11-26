import XCTest

/// Drives the real app (in-memory data, see `AppContainer.uiTesting()`) through flows that unit tests on models
/// cannot see: a button that renders but does nothing, a sheet that never opens.
@MainActor
final class TrainFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let train = app.tabBars.buttons["Train"]
        XCTAssertTrue(train.waitForExistence(timeout: 10))
        train.tap()
    }

    /// Regression: with no exercise yet, "Add exercise" did nothing.
    func testAddExerciseToAnEmptySession() {
        app.buttons["Start empty session"].tap()

        let addExercise = app.buttons["Add exercise"]
        XCTAssertTrue(addExercise.waitForExistence(timeout: 5), "An empty session offers Add exercise")
        addExercise.tap()

        let picker = app.navigationBars["Add exercise"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Add exercise opens the exercise picker")

        app.buttons["Bench Press (Barbell)"].tap()
        XCTAssertTrue(app.buttons["Add set"].waitForExistence(timeout: 5), "The picked exercise joins the session")
        XCTAssertFalse(picker.exists, "The picker closes after picking")
    }

    /// Adding a second exercise works the same once the session has sets.
    func testAddASecondExercise() {
        app.buttons["Start empty session"].tap()
        for name in ["Bench Press (Barbell)", "Bent Over Row (Barbell)"] {
            app.buttons["Add exercise"].firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Add exercise"].waitForExistence(timeout: 5))
            app.buttons[name].tap()
            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5), "\(name) joins the session")
        }
    }
}
