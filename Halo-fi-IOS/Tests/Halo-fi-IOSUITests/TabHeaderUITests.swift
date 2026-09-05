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

    func testMoneyHeader_ssiBlind_balanceThenResourceCounter() {
        // The balance card IS the resource counter for SSI users (2026-09-04).
        let app = launch("ssi_blind")
        openTab(app, "Money")
        let label = header(in: app).label
        XCTAssertTrue(label.hasPrefix("Balance."), label)
        XCTAssertTrue(label.contains("Cash 1,214 dollars"), label)
        XCTAssertTrue(label.contains("Counts toward your SSI limit: 1,214 dollars of 2,000 dollars, on track"), label)
        XCTAssertTrue(label.contains("Estimate for education only"), label)
    }

    func testMoneyHero_ssiBlind_opensResourceMonitor() {
        let app = launch("ssi_blind")
        openTab(app, "Money")
        let hero = header(in: app)
        XCTAssertTrue(hero.isHittable)
        hero.tap()
        XCTAssertTrue(app.navigationBars["Resource monitor"].waitForExistence(timeout: 10)
                      || app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'counted'")).firstMatch.waitForExistence(timeout: 10),
                      "resource monitor did not open")
    }

    func testBenefitsHeader_ssiWatch_leadsWithUrgentItemAndBanner() {
        let app = launch("ssi_watch")
        openTab(app, "Benefits")
        let label = header(in: app).label
        XCTAssertTrue(label.hasPrefix("Resources getting close."), label)
        XCTAssertTrue(label.contains("Resources 1,800 dollars of 2,000 dollars"), label)
        let banner = app.descendants(matching: .any)["resourceAlertBanner"].firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "alert banner missing in the watch band")
        XCTAssertTrue(banner.label.hasPrefix("Getting close to your SSI resource limit"), banner.label)
    }

    func testBenefitsTab_ssiBlind_hasNoBannerOnTrackAndShowsProfileRow() {
        let app = launch("ssi_blind")
        openTab(app, "Benefits")
        XCTAssertFalse(app.descendants(matching: .any)["resourceAlertBanner"].exists, "banner must not render while on track")
        XCTAssertFalse(app.staticTexts["Resource monitor"].exists, "resource monitor row moved to the Money tab")
        let profileRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Your benefits profile'")).firstMatch
        XCTAssertTrue(profileRow.waitForExistence(timeout: 10), "profile row missing")
        XCTAssertTrue(app.buttons["Redo the questionnaire"].exists)
    }

    func testTabBar_answeredNoBenefits_hidesBenefitsTab() {
        let app = launch("none_answered")
        let buttons = app.tabBars.buttons
        XCTAssertTrue(buttons["Money"].waitForExistence(timeout: 10))
        XCTAssertFalse(buttons["Benefits"].exists, "Benefits tab must be hidden for answered no-benefit users")
        XCTAssertTrue(buttons["Agent"].exists)
        XCTAssertTrue(buttons["Settings"].exists)
        openTab(app, "Settings")
        XCTAssertTrue(app.buttons["Set up benefits"].waitForExistence(timeout: 10)
                      || app.staticTexts["Set up benefits"].waitForExistence(timeout: 10), "Settings entry to bring the tab back is missing")
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

    func testBenefitsQuestionnaireOpensFromEmptyTab() {
        let app = launch("none")
        openTab(app, "Benefits")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Start the benefits questionnaire'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "questionnaire row missing")
        row.tap()
        XCTAssertTrue(app.staticTexts["Benefits questionnaire"].waitForExistence(timeout: 10), "intro did not open")
        XCTAssertTrue(app.buttons["I understand, start"].exists)
    }

    func testAgentHeader() {
        let app = launch("none")
        openTab(app, "Agent")
        XCTAssertTrue(header(in: app).label.hasPrefix("Halo Assistant."))
    }

    func testBudgetOpensFromMoney() {
        let app = launch("ssi_blind")
        openTab(app, "Money")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Budget.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "budget row missing")
        row.tap()
        // The pushed Budget screen must render (it used to be a blank screen).
        XCTAssertTrue(app.navigationBars["Budget"].waitForExistence(timeout: 10), "Budget screen did not open")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Spent'")).firstMatch.waitForExistence(timeout: 10), "budget content missing")
    }
}
