//
//  TabHeaderUITests.swift
//  Halo-fi-IOSUITests
//
//  WP4 §9 — every tab's first accessibility element is a header whose label
//  starts with the screen's verdict, per archetype. The app is launched with
//  `--ui-test-archetype=<name>`; MainTabView seeds fixtures and skips auth.
//

import XCTest

final class TabHeaderUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ archetype: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-archetype=\(archetype)"]
        app.launch()
        return app
    }

    private func header(in app: XCUIApplication) -> XCUIElement {
        let element = app.descendants(matching: .any)["screenSummaryHeader"].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 10), "summary header not found")
        return element
    }

    private func openTab(_ app: XCUIApplication, _ name: String) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "tab \(name) missing")
        tab.tap()
    }

    func testTabOrderIsMoneyBenefitsAgentSettings() {
        let app = launch("none")
        let buttons = app.tabBars.buttons
        XCTAssertTrue(buttons["Money"].waitForExistence(timeout: 10))
        XCTAssertTrue(buttons["Benefits"].exists)
        XCTAssertTrue(buttons["Agent"].exists)
        XCTAssertTrue(buttons["Settings"].exists)
    }

    func testMoneyHeader_nonBenefitUser_leadsWithCash() {
        let app = launch("none")
        openTab(app, "Money")
        let label = header(in: app).label
        XCTAssertTrue(label.hasPrefix("Balance."), label)
        XCTAssertTrue(label.contains("Cash 1,214 dollars"), label)
        XCTAssertTrue(label.contains("Owed 1,870 dollars"), label)
    }

    func testMoneyHeader_ssiBlind_leadsWithVerdictThenResources() {
        let app = launch("ssi_blind")
        openTab(app, "Money")
        let label = header(in: app).label
        XCTAssertTrue(label.hasPrefix("On track."), label)
        XCTAssertTrue(label.contains("Counted resources: 1,214 dollars of 2,000 dollars"), label)
        XCTAssertTrue(label.contains("Estimate for education only"), label)
    }

    func testBenefitsHeader_ssiBlind() {
        let app = launch("ssi_blind")
        openTab(app, "Benefits")
        let label = header(in: app).label
        XCTAssertTrue(label.hasPrefix("Your SSI is on track."), label)
        XCTAssertTrue(label.contains("Projected check about 994 dollars"), label)
    }

    func testBenefitsHeader_ssiUnverified_showsLockedBWE() {
        let app = launch("ssi_unverified")
        openTab(app, "Benefits")
        XCTAssertTrue(header(in: app).label.hasPrefix("Your SSI is on track."))
        XCTAssertTrue(app.staticTexts["Blind Work Expenses — locked"].waitForExistence(timeout: 5))
    }

    func testBenefitsHeader_ssdiOnly() {
        let app = launch("ssdi")
        openTab(app, "Benefits")
        XCTAssertTrue(header(in: app).label.hasPrefix("Your SSDI."))
    }

    func testBenefitsHeader_nonBenefitUser() {
        let app = launch("none")
        openTab(app, "Benefits")
        XCTAssertTrue(header(in: app).label.hasPrefix("No benefits set up."))
        XCTAssertFalse(app.staticTexts["Work expenses"].exists)
        XCTAssertFalse(app.staticTexts["Monthly package"].exists)
    }

    func testAgentHeader() {
        let app = launch("none")
        openTab(app, "Agent")
        XCTAssertTrue(header(in: app).label.hasPrefix("Halo."))
    }
}
