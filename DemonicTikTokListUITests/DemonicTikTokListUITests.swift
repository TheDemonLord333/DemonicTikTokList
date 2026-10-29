//
//  DemonicTikTokListUITests.swift
//  DemonicTikTokListUITests
//

import XCTest

final class DemonicTikTokListUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestInMemoryStore"]
        app.launch()
        return app
    }

    @MainActor
    func testEmptyStateAndToolbar() throws {
        let app = launchApp()
        XCTAssertTrue(app.navigationBars["Demonic TikTok List"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Füge dein erstes TikTok-Profil über + hinzu"].exists)
        XCTAssertTrue(app.navigationBars.buttons["Bearbeiten"].exists)
        XCTAssertTrue(app.navigationBars.buttons["Profil hinzufügen"].exists)
    }

    @MainActor
    func testRejectsForeignDomainAndCancelDiscardsInput() throws {
        let app = launchApp()
        app.navigationBars.buttons["Profil hinzufügen"].tap()

        let field = app.textFields["profileLinkField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("https://tiktok.com.example.org/@username")
        app.buttons["Speichern"].tap()

        XCTAssertTrue(app.staticTexts["Der Link gehört nicht zu TikTok. Bitte verwende einen Link von tiktok.com."]
            .waitForExistence(timeout: 5))

        app.buttons["Abbrechen"].tap()
        XCTAssertTrue(app.staticTexts["Füge dein erstes TikTok-Profil über + hinzu"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAddEditModeAndDeleteProfile() throws {
        let app = launchApp()
        app.navigationBars.buttons["Profil hinzufügen"].tap()

        let field = app.textFields["profileLinkField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("tiktok.com/@demonic_test_user?is_from_webapp=1")
        app.buttons["Speichern"].tap()

        // Die Listenzeile ist ein einzelnes Bedienelement mit kombiniertem VoiceOver-Label.
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "@demonic_test_user")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        app.navigationBars.buttons["Bearbeiten"].tap()
        XCTAssertTrue(app.navigationBars.buttons["Fertig"].waitForExistence(timeout: 2))

        app.buttons["Profil @demonic_test_user löschen"].tap()
        let alert = app.alerts["Möchtest du dieses Profil aus deiner Liste löschen?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Löschen"].tap()

        XCTAssertTrue(app.staticTexts["Füge dein erstes TikTok-Profil über + hinzu"].waitForExistence(timeout: 5))
    }
}
