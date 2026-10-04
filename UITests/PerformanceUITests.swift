import XCTest

/// Measurements of fixed workloads on synthetic fixtures: the sample habits (ten habits, about 220 days) and `large`
/// (thirty habits over five years, about 40,000 logged days). No time is asserted: XCTest reports each metric, and a
/// baseline set in Xcode flags a regression. They take several minutes and only mean something on a quiet machine or
/// a device, so they run when asked: TEST_RUNNER_BUDDY_PERFORMANCE=1.
final class PerformanceUITests: XCTestCase {
    private let subsystem = "com.iyashwant.habbitbuddy"
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BUDDY_PERFORMANCE"] == "1", "Takes several minutes; opt in with TEST_RUNNER_BUDDY_PERFORMANCE=1")
        continueAfterFailure = false
    }
    private func app(_ screen: String, fixture: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["BUDDY_VISUAL_SCREEN": screen, "BUDDY_VISUAL_DATE": "2026-08-18", "BUDDY_VISUAL_THEME": "dark"]
        if let fixture { app.launchEnvironment["BUDDY_VISUAL_FIXTURE"] = fixture }
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        return app
    }
    /// Launches until the first frame responds, and until the habits show (the app's "First load" signpost).
    func testLaunch() { launch("cards") }
    func testLaunchLarge() { launch("cards", fixture: "large") }
    /// The streak layout shows every habit's streak as it opens.
    func testLaunchLargeStreaks() { launch("streaks", fixture: "large") }
    private func launch(_ screen: String, fixture: String? = nil) {
        // The first launch writes the fixture; the measured ones read it from disk as a normal launch does.
        let app = app(screen, fixture: fixture), habit = app.staticTexts["Gym Day"].firstMatch
        app.launch()
        XCTAssertTrue(habit.waitForExistence(timeout: 60))
        app.terminate()
        app.launchEnvironment["BUDDY_VISUAL_RESET"] = "false"
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true), XCTOSSignpostMetric(subsystem: subsystem, category: "Interaction", name: "First load")]) {
            app.launch()
            XCTAssertTrue(habit.waitForExistence(timeout: 60))
        }
    }
    /// The main thread's time from a check-in tap until the update that shows it has run (the app's "Check-in" signpost).
    func testCheckIn() { checkIn() }
    func testCheckInLarge() { checkIn(fixture: "large") }
    private func checkIn(fixture: String? = nil) {
        let app = app("cards", fixture: fixture)
        app.launch()
        let check = app.buttons["Log progress for Gym Day"]
        XCTAssertTrue(check.waitForExistence(timeout: 60))
        let options = XCTMeasureOptions()
        options.iterationCount = 10
        measure(metrics: [XCTOSSignpostMetric(subsystem: subsystem, category: "Interaction", name: "Check-in")], options: options) { check.tap() }
    }
    /// Flinging the cards up: hitches and frame rate while scrolling and decelerating, memory and CPU.
    func testScrollingCards() { scroll("cards") { $0.buttons["Log progress for Gym Day"] } }
    func testScrollingCardsLarge() { scroll("cards", fixture: "large") { $0.buttons["Log progress for Gym Day"] } }
    /// Flinging the dashboard up, with every design on it.
    func testScrollingDashboard() { scroll("widgets") { $0.buttons["Edit Dashboard"] } }
    private func scroll(_ screen: String, fixture: String? = nil, ready: (XCUIApplication) -> XCUIElement) {
        let app = app(screen, fixture: fixture)
        app.launch()
        XCTAssertTrue(ready(app).waitForExistence(timeout: 60))
        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStop]
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric, XCTMemoryMetric(application: app), XCTCPUMetric(application: app)], options: options) {
            app.swipeUp(velocity: .fast)
            stopMeasuring()
            app.swipeDown(velocity: .fast)
        }
    }
}
