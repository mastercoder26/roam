import XCTest

@MainActor
final class ProfileSettingsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        let previewsSignedIn = name.contains("testSignedInSummary")
        app.launchArguments = [
            previewsSignedIn ? "--preview-profile-signed-in" : "--preview-profile",
            "-roam.theme-id-v1", "dark",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"
        ]
        app.launch()
        let ready = previewsSignedIn
            ? app.descendants(matching: .any)["profile.summary.miles"]
            : app.buttons["profile.signIn"]
        XCTAssertTrue(ready.waitForExistence(timeout: 30))
    }

    func testSignedInSummaryShowsRealEmptyHistory() {
        XCTAssertFalse(app.buttons["profile.signIn"].exists)
        let miles = app.descendants(matching: .any)["profile.summary.miles"]
        let drives = app.descendants(matching: .any)["profile.summary.drives"]
        let days = app.descendants(matching: .any)["profile.summary.days"]
        XCTAssertEqual(miles.value as? String, "0.0")
        XCTAssertEqual(drives.value as? String, "0")
        XCTAssertEqual(days.value as? String, "0")
        XCTAssertGreaterThan(miles.frame.minY, app.staticTexts["profile.greeting"].frame.maxY)
        XCTAssertLessThan(miles.frame.maxY, app.buttons["profile.editIdentity"].frame.minY)
        attachScreenshot("Signed-in summary with empty history")
    }

    func testGuestCanEditLocalProfile() {
        XCTAssertTrue(app.staticTexts["Welcome"].exists)
        XCTAssertFalse(app.buttons["Sign out"].exists)
        XCTAssertFalse(app.otherElements["profile.drivingSummary"].exists)
        XCTAssertLessThan(app.staticTexts["profile.greeting"].frame.minY, app.frame.height * 0.20)
        app.buttons["profile.editIdentity"].tap()
        XCTAssertTrue(app.textFields["profile.displayName"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Edit profile"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["profile.signIn"].waitForExistence(timeout: 5))

        app.buttons["profile.signIn"].tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["profile.signIn"].waitForExistence(timeout: 5))
    }

    func testPreferenceSheetsOpenAndDismiss() {
        let appearance = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Color scheme, currently")).firstMatch
        if !appearance.isHittable { app.swipeUp() }
        appearance.tap()
        XCTAssertTrue(app.navigationBars["Color scheme"].waitForExistence(timeout: 5))
        app.buttons["Light"].tap()
        XCTAssertEqual(app.buttons["Light"].value as? String, "Selected")
        app.buttons["Dark"].tap()
        XCTAssertEqual(app.buttons["Dark"].value as? String, "Selected")
        app.buttons["Done"].tap()

        let icon = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "App icon, currently")).firstMatch
        if !icon.isHittable { app.swipeUp() }
        icon.tap()
        XCTAssertTrue(app.navigationBars["App icon"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(appearance.waitForExistence(timeout: 5))
    }

    func testDrivingDestinationsAndHelpOpen() {
        for title in ["Goals & progress", "Driving insights"] {
            app.buttons[title].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.buttons["profile.signIn"].waitForExistence(timeout: 5))
        }

        let help = app.buttons["settings.startWalkthrough"]
        if !help.isHittable { app.swipeUp() }
        help.tap()
        XCTAssertTrue(app.navigationBars["Explore Roam"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["walkthrough.next"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(help.waitForExistence(timeout: 5))
    }

    func testPullReturnsToRestAndPreservesNavigation() {
        let greeting = app.staticTexts["Welcome"]
        let restingY = greeting.frame.minY
        attachScreenshot("Profile at rest")
        // Start on the open landscape above the raised sign-in card.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.14))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.60))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 2)

        let returned = NSPredicate { _, _ in abs(greeting.frame.minY - restingY) < 2 }
        expectation(for: returned, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        attachScreenshot("Profile after release")

        app.buttons["profile.editIdentity"].tap()
        XCTAssertTrue(app.navigationBars["Edit profile"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
