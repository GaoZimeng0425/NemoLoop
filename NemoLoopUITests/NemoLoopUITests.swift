import XCTest

/// End-to-end smoke for the settings surface, entered via `--settings` —
/// deliberately NOT the menu-bar item (NSStatusItem is notoriously hard to
/// query in the accessibility hierarchy) and NOT any TCC-gated flow (OCR
/// capture, appearance automation prompts — those stay on the human
/// acceptance checklist). The smoke pins the plugin architecture's most
/// load-bearing UI: the Plugins tab exists, lists the three built-ins,
/// and a connect toggle actually flips.
///
/// ENVIRONMENT NOTE (2026-09-09): under CLI `xcodebuild` with the
/// self-signed NemoLoopDev identity the runner dead-hangs at session
/// establishment with zero log output — the macOS automation gate for
/// unattended XCUITest. To unblock, run this suite once from the Xcode GUI
/// (which surfaces the Accessibility consent for the runner) or pre-grant
/// Accessibility to NemoLoopUITests-Runner / xcodebuild in System Settings;
/// with the stable NemoLoopDev identity the grant persists across rebuilds.
/// The target itself builds clean: `xcodebuild build-for-testing
/// -only-testing:NemoLoopUITests` exits 0.
final class NemoLoopUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--settings"]
    }

    func testSettingsOpensWithTabsAndBuiltInPluginCards() throws {
        app.launch()

        // The sidebar's first tab proves the window came up (accessory app:
        // no Dock icon to wait on, so poll the AX tree instead).
        XCTAssertTrue(app.staticTexts["General"].firstMatch.waitForExistence(timeout: 10),
                      "settings window did not open")

        for tab in ["Ring", "Plugins", "Appearance", "About"] {
            XCTAssertTrue(app.staticTexts[tab].firstMatch.exists, "missing sidebar tab \(tab)")
        }

        // Default tab is Ring; switch to Plugins and expect the three
        // built-in plugin cards.
        app.buttons["Plugins"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["System"].firstMatch.waitForExistence(timeout: 5),
                      "System plugin card missing")
        XCTAssertTrue(app.staticTexts["Appearance"].firstMatch.exists, "Appearance card missing")
        XCTAssertTrue(app.staticTexts["Screenshot"].firstMatch.exists, "Screenshot card missing")
    }

    func testConnectToggleFlips() throws {
        app.launch()

        app.buttons["Plugins"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["Screenshot"].firstMatch.waitForExistence(timeout: 5))

        // Any card's connect switch: read its AX value, click, and assert the
        // value actually changed — a dead binding (the Task 5 failure mode)
        // leaves the knob unmoved.
        let toggle = app.switches.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 3), "no connect switch found")
        let before = toggle.value as? String
        toggle.click()
        // The async connect() round-trip needs a beat before the knob reads back.
        let flipped = NSPredicate(format: "value != %@", before ?? "")
        let expectation = expectation(for: flipped, evaluatedWith: toggle)
        wait(for: [expectation], timeout: 5)
    }
}
