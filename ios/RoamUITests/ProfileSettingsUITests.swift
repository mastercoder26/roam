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


@MainActor
final class NavigationChromeUITests: XCTestCase {
    func testTabsRemainReachableAfterScrolling() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--preview-profile", "-roam.theme-id-v1", "dark"]
        app.launch()
        let routes = app.tabBars.buttons["Routes"]
        XCTAssertTrue(routes.waitForExistence(timeout: 30))
        XCTAssertTrue(routes.isHittable)
        app.swipeUp(velocity: .slow)
        // A short page may fit without minimizing. Navigation must remain
        // reachable when scrolling returns upward in either native state.
        attach(app, "Profile after scrolling down")
        app.swipeDown(velocity: .slow)
        let expanded = NSPredicate { _, _ in routes.isHittable }
        expectation(for: expanded, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        routes.tap()
        XCTAssertTrue(app.staticTexts["Where to?"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Roam"].exists, "The persistent brand header has been removed")
        attach(app, "Title-only Routes with restored navigation")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}


@MainActor
final class DesignConsistencyUITests: XCTestCase {
    private let app = XCUIApplication()

    func testAllThemesAcrossTabsAndAppearanceMenu() {
        continueAfterFailure = false
        launch()
        for title in ["Dark", "Light", "Goldfish", "Midnight", "Ember", "Sequoia"] {
            switchTab("Profile")
            let appearance = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Color scheme, currently")).firstMatch
            reveal(appearance)
            appearance.tap()
            XCTAssertTrue(app.navigationBars["Color scheme"].waitForExistence(timeout: 5))
            let choice = app.buttons[title]
            reveal(choice)
            choice.tap()
            XCTAssertEqual(choice.value as? String, "Selected")
            attach("\(title) — Appearance")
            app.buttons["Done"].tap()

            switchTab("Routes")
            XCTAssertTrue(app.staticTexts["Where to?"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["Roam"].exists)
            attach("\(title) — Routes")

            switchTab("Drive")
            XCTAssertTrue(app.buttons["Start drive"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Start drive"].isHittable)
            attach("\(title) — Drive")

            switchTab("Progress")
            XCTAssertTrue(app.staticTexts["Overall driving score"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Record your first drive"].exists)
            attach("\(title) — Progress")
        }
    }

    func testProfileMenusWithAccessibilityText() {
        continueAfterFailure = false
        launch(largeText: true)
        let editor = app.buttons["profile.editIdentity"]
        reveal(editor)
        editor.tap()
        XCTAssertTrue(app.textFields["profile.displayName"].waitForExistence(timeout: 5))
        attach("Large text — Edit profile")
        app.swipeUp()
        let stage = app.buttons["profile.stage.provisional"]
        reveal(stage)
        stage.tap()
        XCTAssertEqual(stage.value as? String, "Selected")
        attach("Large text — Licensing stage")
        app.buttons["Done"].tap()

        for title in ["Goals & progress", "Driving insights"] {
            let destination = app.buttons[title]
            reveal(destination)
            destination.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            attach("Large text — \(title)")
            app.swipeUp()
            attach("Large text — \(title) scrolled")
            app.navigationBars.buttons.firstMatch.tap()
        }

        let appearance = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Color scheme, currently")).firstMatch
        reveal(appearance)
        appearance.tap()
        XCTAssertTrue(app.navigationBars["Color scheme"].waitForExistence(timeout: 5))
        reveal(app.buttons["Light"])
        app.buttons["Light"].tap()
        XCTAssertEqual(app.buttons["Light"].value as? String, "Selected")
        attach("Large text — Light appearance")
        app.buttons["Done"].tap()

        let icon = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "App icon, currently")).firstMatch
        reveal(icon)
        icon.tap()
        XCTAssertTrue(app.navigationBars["App icon"].waitForExistence(timeout: 5))
        attach("Large text — App icon")
        app.buttons["Done"].tap()

        let guide = app.buttons["settings.startWalkthrough"]
        reveal(guide)
        guide.tap()
        XCTAssertTrue(app.buttons["walkthrough.next"].waitForExistence(timeout: 5))
        attach("Large text — Explore Roam")
        app.buttons["walkthrough.next"].tap()
        XCTAssertTrue(app.buttons["walkthrough.next"].exists)
        app.buttons["Done"].tap()
    }

    func testMainMenuDestinationsAndCoachingAction() {
        continueAfterFailure = false
        launch()
        switchTab("Routes")
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Route preview"].exists)
        attach("Final — Routes")
        let explanation = app.buttons["routes.howRoamWorks"]
        reveal(explanation)
        explanation.tap()
        XCTAssertTrue(app.navigationBars["How Roam works"].waitForExistence(timeout: 5))
        attach("Routes — How Roam works")
        app.buttons["Done"].tap()

        switchTab("Drive")
        attach("Final — Drive")
        app.buttons["Get help"].tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        app.buttons["Plan a recovery stop"].tap()
        XCTAssertTrue(app.navigationBars["Recovery stop"].waitForExistence(timeout: 5))
        attach("Drive — Recovery stop")
        app.buttons["Done"].tap()

        switchTab("Progress")
        attach("Final — Progress")
        let record = app.buttons["Record your first drive"]
        reveal(record)
        record.tap()
        XCTAssertTrue(app.buttons["Start drive"].waitForExistence(timeout: 5))
    }

    private func launch(largeText: Bool = false) {
        app.launchArguments = [
            "--preview-profile", "-roam.theme-id-v1", "dark",
            "-UIPreferredContentSizeCategoryName",
            largeText ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["profile.signIn"].waitForExistence(timeout: 30))
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<6 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func switchTab(_ title: String) {
        let tab = app.tabBars.buttons[title]
        if !tab.isHittable { app.swipeDown() }
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}


@MainActor
final class RecordingDesignUITests: XCTestCase {
    func testRecordingControlsPauseResumeLockAndEnd() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--preview-drive", "-roam.theme-id-v1", "dark"]
        app.launch()
        let start = app.buttons["drive.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        start.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deny = springboard.buttons["Don’t Allow"]
        if deny.waitForExistence(timeout: 3) { deny.tap() }
        let pause = app.buttons["drive.pauseResume"]
        let pauseExists = pause.waitForExistence(timeout: 8)
        if !pauseExists { print(app.debugDescription) }
        XCTAssertTrue(pauseExists)
        pause.tap()
        let toggle = app.buttons["drive.controls.pauseResume"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.label, "Resume drive")
        attach(app, "Paused drive controls")
        toggle.tap()
        XCTAssertEqual(toggle.label, "Pause drive")
        app.buttons["drive.lockControls"].tap()
        let unlock = app.descendants(matching: .any)["drive.unlockControls"].firstMatch
        XCTAssertTrue(unlock.waitForExistence(timeout: 5))
        unlock.press(forDuration: 0.25)
        XCTAssertTrue(unlock.exists, "Releasing early must keep the controls locked")
        XCTAssertFalse(app.buttons["drive.showControls"].exists)
        unlock.press(forDuration: 1.3)
        XCTAssertTrue(app.buttons["drive.showControls"].waitForExistence(timeout: 5))
        app.buttons["drive.showControls"].tap()
        XCTAssertTrue(app.buttons["drive.end"].waitForExistence(timeout: 5))
        app.buttons["drive.end"].tap()
        if app.buttons["New drive"].waitForExistence(timeout: 2) { app.buttons["New drive"].tap() }
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        attach(app, "Ready after ending a short drive")
    }

    func testMapStaysBehindDestinationEntryAndProgressHasEmptyState() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--preview-profile", "-roam.theme-id-v1", "dark"]
        app.launch()
        let routes = app.tabBars.buttons["Routes"]
        XCTAssertTrue(routes.waitForExistence(timeout: 30))
        routes.tap()
        XCTAssertTrue(app.descendants(matching: .any)["routes.backgroundMap"].firstMatch.waitForExistence(timeout: 8))
        let destination = app.textFields["Enter a destination"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        destination.tap()
        destination.typeText("Lincoln")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["routes.backgroundMap"].firstMatch.exists)
        attach(app, "Map behind native destination entry")
        app.terminate()
        app.launchArguments = ["--preview-progress", "-roam.theme-id-v1", "dark"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["progress.overallScore"].firstMatch.waitForExistence(timeout: 30))
        attach(app, "Progress state")
    }

    func testAccessibilityTextKeepsDestinationAndProgressReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--preview-routes", "-roam.theme-id-v1", "light",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let destination = app.textFields["Enter a destination"]
        XCTAssertTrue(destination.waitForExistence(timeout: 30))
        if !destination.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(destination.isHittable)
        attach(app, "Route planning at accessibility text size")
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["progress.overallScore"].firstMatch.waitForExistence(timeout: 10))
        attach(app, "Progress at accessibility text size")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
