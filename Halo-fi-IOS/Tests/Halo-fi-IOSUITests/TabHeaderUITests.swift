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

    /// Lazy stacks only build what is on screen: swipe until the element exists.
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, tries: Int = 4) -> Bool {
        for _ in 0..<tries {
            if element.exists { return true }
            app.swipeUp()
        }
        return element.exists
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
        XCTAssertFalse(app.buttons["Redo the questionnaire"].exists, "redo lives inside the profile now")
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

    func testMoneyAttention_ssiBlind_readsAfterHeroAndOpensDepositQuestion() {
        let app = launch("ssi_blind")
        openTab(app, "Money")
        XCTAssertTrue(header(in: app).waitForExistence(timeout: 10))
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Needs your attention.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "attention row missing")
        XCTAssertTrue(row.label.contains("First: Hand in August work expenses"), row.label)
        row.tap()
        let package = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Hand in August work expenses'")).firstMatch
        XCTAssertTrue(package.waitForExistence(timeout: 10), "deadline card missing")
        let deposit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '$412.00 from ACME PAYROLL.'")).firstMatch
        XCTAssertTrue(scrollTo(deposit, in: app), "deposit card missing")
        deposit.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'What is this?'")).firstMatch.waitForExistence(timeout: 10), "deposit question did not open")
        XCTAssertTrue(app.buttons["Work income"].exists)
        XCTAssertTrue(app.buttons["A gift or help from someone"].exists)
    }

    func testMoneyAttention_unansweredUser_isQuiet() {
        let app = launch("none")
        openTab(app, "Money")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Needs your attention.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "attention row missing")
        XCTAssertTrue(row.label.contains("Nothing right now."), row.label)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Hand in'")).firstMatch.exists)
    }

    func testMoneyAttention_noneAnswered_onlyBankCard() {
        let app = launch("none_answered")
        openTab(app, "Money")
        let income = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Income.'")).firstMatch
        XCTAssertTrue(scrollTo(income, in: app), "Income row missing")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Needs your attention.'")).firstMatch
        XCTAssertTrue(scrollTo(row, in: app), "attention row missing")
        XCTAssertTrue(row.label.contains("Reconnect Chase."), row.label)
        row.tap()
        let bank = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reconnect Chase.'")).firstMatch
        XCTAssertTrue(bank.waitForExistence(timeout: 10), "bank card missing")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Hand in'")).firstMatch.exists)
    }

    func testMoneyHero_ssiWatch_speaksProjectionAndBillCardOpens() {
        let app = launch("ssi_watch")
        openTab(app, "Money")
        let label = header(in: app).label
        XCTAssertTrue(label.contains("By October 1, about 1,940 dollars of 2,000 dollars, act now."), label)
        XCTAssertTrue(label.contains("1 possible bill not counted yet"), label)
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Needs your attention.'")).firstMatch
        XCTAssertTrue(scrollTo(row, in: app), "attention row missing")
        row.tap()
        let bill = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Is XYZ Property a bill?'")).firstMatch
        XCTAssertTrue(bill.waitForExistence(timeout: 10), "bill card missing")
        bill.tap()
        XCTAssertTrue(app.buttons["Yes, a bill"].waitForExistence(timeout: 10), "bill sheet did not open")
        XCTAssertTrue(app.buttons["No, neither"].exists)
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
