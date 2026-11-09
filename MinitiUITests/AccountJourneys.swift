import XCTest

final class AccountJourneys: XCTestCase {
    private var app: XCUIApplication!
    private var testID = UUID().uuidString

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 60
        testID = UUID().uuidString
    }
    override func tearDown() {
        if app != nil {
            app.terminate()
            app.launchArguments = ["-MinitiUITestCleanup"]
            app.launch()
            app.terminate()
        }
        super.tearDown()
    }

    private func launch(_ scenario: String = "first", largeText: Bool = false, screenshotScene: String? = nil) {
        app = XCUIApplication()
        if let screenshotScene {
            app.launchArguments = ["-MinitiScreenshotScene", screenshotScene]
        }
        if largeText {
            app.launchEnvironment["MINITI_UI_TEST_LARGE_TEXT"] = "1"
        }
        app.launchEnvironment["MINITI_UI_TEST_ID"] = testID
        app.launchEnvironment["MINITI_UI_TEST_SCENARIO"] = scenario
        app.launch()
        guard app.staticTexts["ui-test.ready"].waitForExistence(timeout: 30) else {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.lifetime = .keepAlways; add(screenshot)
            app.terminate()
            XCTFail("Isolated Testing app did not become ready. Check runner automation authorization and host configuration.")
            return
        }
    }

    #if os(macOS)
    func testMacOwnedWindowsStayDarkWithLightAmbientAppearance() {
        launch("appearance")
        continueAfterFailure = true
        assertMacAppearance("main")
        app.buttons["account.signIn"].click()
        assertMacAppearance("email")
        app.buttons["Cancel"].firstMatch.click()
        app.typeKey(",", modifierFlags: .command)
        assertMacAppearance("settings")
        app.menuBars.menuBarItems["Window"].click()
        app.menuItems["Debug Log"].click()
        assertMacAppearance("debug")
    }

    func testMacDocsAnswerCopiesUsingKeyboardOnly() throws {
        launch("docsTargets")
        // Honour the machine's navigation setting; never change global defaults.
        let mode = app.staticTexts["ui-test.keyboardNavigation"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        guard let state = mode.value as? String,
              ["Keyboard navigation on", "Keyboard navigation off"].contains(state) else {
            XCTFail("Keyboard navigation badge is unreadable: value=\(String(describing: mode.value)), label=\(mode.label)")
            return
        }
        try XCTSkipUnless(state == "Keyboard navigation on",
                          "Keyboard navigation is off. Enable it for the Mac keyboard acceptance run.")
        XCTAssertTrue(app.buttons["Copy answer"].waitForExistence(timeout: 5))
        for _ in 0..<12 {
            app.typeKey(.tab, modifierFlags: [])
            app.typeKey(.space, modifierFlags: [])
            if app.buttons["Answer copied"].exists { break }
        }
        XCTAssertTrue(app.buttons["Answer copied"].exists, app.debugDescription)
        let capture = XCTAttachment(screenshot: app.windows["Miniti"].screenshot())
        capture.name = "Docs answer copied using only Tab and Space"
        capture.lifetime = .keepAlways
        add(capture)
    }

    private func assertMacAppearance(_ name: String) {
        let probe = app.staticTexts["appearance.\(name)"]
        XCTAssertTrue(probe.waitForExistence(timeout: 5), app.debugDescription)
        let capture = XCTAttachment(screenshot: app.windows.containing(.staticText, identifier: "appearance.\(name)").firstMatch.screenshot())
        capture.name = "Mac \(name) with Light ambient appearance"
        capture.lifetime = .keepAlways
        add(capture)
        XCTAssertEqual(probe.value as? String, "swiftUI=dark; window=dark; app=light")
    }
    #endif

    #if os(iOS)
    func testLiveMetricHelpAndCloseHaveNamedMinimumTargets() {
        launch(screenshotScene: "recording-coaching")
        assertMetricHelpTargets()
    }

    func testSavedMetricHelpAndCloseHaveNamedMinimumTargets() {
        launch(screenshotScene: "meeting-coaching")
        assertMetricHelpTargets()
    }

    private func assertMetricHelpTargets() {
        let help = app.buttons["About fillers"].firstMatch
        XCTAssertTrue(help.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertGreaterThanOrEqual(help.frame.width, 44)
        XCTAssertGreaterThanOrEqual(help.frame.height, 44)
        let listCapture = XCTAttachment(screenshot: app.screenshot())
        listCapture.name = "Coaching list with minimum help targets"
        listCapture.lifetime = .keepAlways
        add(listCapture)
        help.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: 2)).tap()
        let close = app.buttons["Close metric help"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertGreaterThanOrEqual(close.frame.width, 44)
        XCTAssertGreaterThanOrEqual(close.frame.height, 44)
        let title = app.staticTexts["Fillers"]
        XCTAssertTrue(title.exists)
        XCTAssertEqual(title.frame.midY, close.frame.midY, accuracy: 1,
                       "Help title and close action share the header centre")
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Metric help with reachable named close action"
        capture.lifetime = .keepAlways
        add(capture)
        close.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: 2)).tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        XCTAssertTrue(help.exists)
    }

    func testDocsAnswerCopyRespondsInItsExpandedTarget() {
        launch("docsTargets")
        let copy = app.buttons["Copy answer"]
        XCTAssertTrue(copy.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertGreaterThanOrEqual(copy.frame.width, 44)
        XCTAssertGreaterThanOrEqual(copy.frame.height, 44)
        copy.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: 2)).tap()
        XCTAssertTrue(app.buttons["Answer copied"].waitForExistence(timeout: 2))
    }

    func testQuestionCopyRespondsInItsExpandedTarget() {
        launch(screenshotScene: "recording-questions")
        let copy = app.buttons["Copy question"].firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertGreaterThanOrEqual(copy.frame.width, 44)
        XCTAssertGreaterThanOrEqual(copy.frame.height, 44)
        copy.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: 2)).tap()
        XCTAssertTrue(app.buttons["Question copied"].waitForExistence(timeout: 2))
    }

    func testSharedTargetsHaveNonOverlappingFramesAndDispatchAtEdges() {
        launch("controlTargets")
        let left = app.buttons["target.left"], right = app.buttons["target.right"]
        XCTAssertTrue(left.waitForExistence(timeout: 5))
        for element in [left, right, app.buttons["target.tab.focus"], app.buttons["target.tab.stats"], app.buttons["target.tab.history"]] {
            XCTAssertGreaterThanOrEqual(element.frame.width, 44)
            XCTAssertGreaterThanOrEqual(element.frame.height, 44)
        }
        XCTAssertEqual(left.frame.maxX, right.frame.minX, accuracy: 0.5)
        XCTAssertLessThanOrEqual(left.frame.maxX, right.frame.minX)
        // The top two points are outside the unchanged 30-point visual chrome.
        left.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: 2)).tap()
        XCTAssertEqual(app.staticTexts["target.counts"].label, "left=1 right=0")
        let edge = left.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: left.frame.width, dy: left.frame.height / 2))
        edge.withOffset(CGVector(dx: -1, dy: 0)).tap()
        XCTAssertEqual(app.staticTexts["target.counts"].label, "left=2 right=0")
        edge.withOffset(CGVector(dx: 1, dy: 0)).tap()
        XCTAssertEqual(app.staticTexts["target.counts"].label, "left=2 right=1")
        edge.tap()
        XCTAssertEqual(app.staticTexts["target.counts"].label, "left=2 right=2", "The trailing control owns the exact shared edge")

        let focus = app.buttons["target.tab.focus"], stats = app.buttons["target.tab.stats"], history = app.buttons["target.tab.history"]
        XCTAssertLessThanOrEqual(focus.frame.maxX, stats.frame.minX)
        XCTAssertLessThanOrEqual(stats.frame.maxX, history.frame.minX)
        stats.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: 2)).tap()
        XCTAssertEqual(app.staticTexts["target.selected"].label, "stats")
        XCTAssertTrue(stats.isSelected)

        let menu = app.buttons["target.menu"]
        XCTAssertGreaterThanOrEqual(menu.frame.height, 44)
        menu.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: 2)).tap()
        app.buttons["Choose"].tap()
        XCTAssertEqual(app.staticTexts["target.menuCounts"].label, "menu=1 disabled=0")
        let disabled = app.buttons["target.disabled"]
        XCTAssertFalse(disabled.isEnabled)
        disabled.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: 2)).tap()
        XCTAssertEqual(app.staticTexts["target.menuCounts"].label, "menu=1 disabled=0")
        XCTAssertFalse(app.buttons["Choose"].exists, "Disabled padding must not open the neighbouring menu")
        let details = app.buttons["details"]
        XCTAssertGreaterThanOrEqual(details.frame.height, 44)
        // Native grouped Forms clip the row's rounded corners. Probe its top
        // centre, inside that native surface and outside the compact label.
        details.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: details.frame.width / 2, dy: 2)).tap()
        XCTAssertTrue(app.staticTexts["target.disclosed"].waitForExistence(timeout: 3))
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Shared controls, native target frames and actions"
        capture.lifetime = .keepAlways
        add(capture)
    }

    func testExistingRecordingOffersCalendarAssociationWithoutEnding() {
        launch("association")
        let associate = app.buttons["Use for this meeting"]
        XCTAssertTrue(associate.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["Keep recording"].exists)
        XCTAssertFalse(app.buttons["End meeting"].exists)
        associate.tap()
        XCTAssertTrue(associate.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["resume recording"].exists)
        XCTAssertTrue(app.buttons["stop"].exists, "Association must keep the current recording running")
    }

    func testOnboardingChoicesRemainUsableAtAccessibilityTextSize() {
        launch("onboarding", largeText: true)
        let signIn = app.buttons["account.signIn"]
        for _ in 0..<4 where !signIn.isHittable { app.swipeUp() }
        XCTAssertTrue(signIn.isHittable, app.debugDescription)
        signIn.tap()
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.tap()
        let continueButton = app.buttons["account.continueAnonymous"]
        for _ in 0..<3 where !continueButton.isHittable { app.swipeUp() }
        XCTAssertTrue(continueButton.isHittable, app.debugDescription)
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "First launch at accessibility text size"
        evidence.lifetime = .keepAlways
        self.add(evidence)
        continueButton.tap()
        XCTAssertTrue(app.buttons["Test microphone"].waitForExistence(timeout: 10))
    }
    #endif

    func testUnavailableEnrollmentAllowsExplicitOfflineSetup() {
        launch("onboardingOffline")
        XCTAssertFalse(app.buttons["account.continueOffline"].exists)
        app.buttons["account.continueAnonymous"].tap()
        let offline = app.buttons["account.continueOffline"]
        XCTAssertTrue(offline.waitForExistence(timeout: 15), app.debugDescription)
        offline.tap()
        XCTAssertTrue(app.buttons["Test microphone"].waitForExistence(timeout: 10))
        app.buttons["Set up microphone later"].tap()
        #if os(macOS)
        app.buttons["I'll start recordings myself"].tap()
        #endif
        XCTAssertTrue(app.buttons["start meeting"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["account.signIn"].exists, "Offline setup must not invent an enrolled account")
    }

    func testAnonymousContinueShowsProgressWhileEnrollmentIsPending() {
        launch("onboardingPending")
        let button = app.buttons["account.continueAnonymous"]
        button.tap()
        XCTAssertTrue(app.staticTexts["Setting up your account..."].waitForExistence(timeout: 5))
        XCTAssertFalse(button.isEnabled)
        XCTAssertFalse(app.buttons["Test microphone"].exists)
    }

    func testHomeAnonymousContinueShowsProgressWhileEnrollmentIsPending() {
        launch("homePending")
        XCTAssertTrue(app.buttons["start meeting"].exists)
        let initialCapture = XCTAttachment(screenshot: app.screenshot())
        initialCapture.name = "Home account choices and centered feedback"; initialCapture.lifetime = .keepAlways; add(initialCapture)
        let button = app.buttons["account.continueAnonymous"]
        button.tap()
        XCTAssertTrue(app.staticTexts["Setting up your account..."].waitForExistence(timeout: 5))
        XCTAssertFalse(button.isEnabled)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Home account setup progress"; capture.lifetime = .keepAlways; add(capture)
    }

    func testHomeAnonymousContinueShowsFailureAndAllowsRetry() {
        launch("homeOffline")
        let button = app.buttons["account.continueAnonymous"]
        button.tap()
        let error = app.staticTexts.matching(NSPredicate(format: "identifier == 'account.setupMessage' AND label CONTAINS[c] 'unavailable'")).firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(button.isEnabled)
        XCTAssertTrue(app.buttons["start meeting"].exists)
    }

    func testAnonymousContinueDoesNotWaitForUsageAfterEnrollment() {
        launch("onboardingSlowUsage")
        app.buttons["account.continueAnonymous"].tap()
        XCTAssertTrue(app.buttons["Test microphone"].waitForExistence(timeout: 5), app.debugDescription)
    }

    func testAnonymousContinueSelectsManagedModeFromPreviousBYOKChoice() {
        launch("onboardingBYOK")
        app.buttons["account.continueAnonymous"].tap()
        XCTAssertTrue(app.buttons["Test microphone"].waitForExistence(timeout: 5), app.debugDescription)
    }

    func testOnboardingOffersExplicitChoicesAndCancellationKeepsFirstStep() {
        launch("onboarding")
        XCTAssertTrue(app.buttons["account.continueAnonymous"].exists)
        app.buttons["account.signIn"].tap()
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.buttons["account.continueAnonymous"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Test microphone"].exists)
        app.buttons["account.continueAnonymous"].tap()
        XCTAssertTrue(app.buttons["Test microphone"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["Set up microphone later"].tap()
        #if os(macOS)
        app.buttons["I'll start recordings myself"].tap()
        #endif
        XCTAssertTrue(app.buttons["start meeting"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["account.continueAnonymous"].exists)
    }

    func testFirstUseCancellationDoesNotCreateAnAccount() {
        launch()
        XCTAssertTrue(app.buttons["account.continueAnonymous"].exists)
        #if os(macOS)
        app.buttons["account.signIn"].click()
        #else
        app.buttons["account.signIn"].tap()
        #endif
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.buttons["account.continueAnonymous"].waitForExistence(timeout: 5))
        app.terminate()
        launch()
        XCTAssertTrue(app.buttons["account.continueAnonymous"].exists)
    }

    func testExplicitContinuePersistsAndHealthyLaunchKeepsAccount() {
        launch()
        app.buttons["account.continueAnonymous"].tap()
        XCTAssertTrue(app.buttons["account.continueAnonymous"].waitForNonExistence(timeout: 10))
        app.terminate()
        launch()
        XCTAssertFalse(app.buttons["account.continueAnonymous"].exists)
    }

    func testLockedCredentialOffersRecoveryWithoutCreatingAccount() {
        launch("locked")
        XCTAssertFalse(app.buttons["Set up this device again"].exists)
        XCTAssertTrue(app.buttons["Try again"].exists)
        XCTAssertFalse(app.buttons["account.continueAnonymous"].exists)
        app.buttons["account.signIn"].tap()
        app.buttons["Use a recovery key"].tap()
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH 'M1-'")).firstMatch.waitForExistence(timeout: 5))
    }

    func testCorruptCredentialOffersExplicitResetConfirmation() {
        launch("corrupt")
        app.buttons["Set up this device again"].tap()
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.buttons["account.signIn"].exists)
    }
    func testThrottledContinueShowsPersistedRetryDeadline() {
        launch("throttled")
        app.buttons["account.continueAnonymous"].tap()
        let retry = app.buttons["account.retrySetup"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(retry.isEnabled)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Try again after'")).firstMatch.exists)
        app.terminate(); launch("throttled")
        XCTAssertTrue(app.buttons["account.retrySetup"].exists)
        XCTAssertFalse(app.buttons["account.retrySetup"].isEnabled)
    }

    func testRevokedChoicePersistsAndRecordDoesNotCreateAnAccount() {
        launch("revoked")
        XCTAssertTrue(app.buttons["account.continueAnonymous"].exists)
        let start = app.buttons["start meeting"]
        if start.exists { start.tap() }
        XCTAssertTrue(app.buttons["account.signIn"].waitForExistence(timeout: 5))
        app.terminate(); launch("revoked")
        XCTAssertTrue(app.buttons["account.continueAnonymous"].exists)
    }

    func testEmailSignInCompletesThroughTheActualSheet() {
        launch()
        app.buttons["account.signIn"].tap()
        let email = app.textFields["Email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap(); email.typeText("fixture@example.invalid")
        app.buttons["Send link"].tap()
        XCTAssertTrue(app.buttons["account.continueAnonymous"].waitForNonExistence(timeout: 15), app.debugDescription)
        app.terminate(); launch()
        XCTAssertFalse(app.buttons["account.continueAnonymous"].exists)
    }

    func testSettingsDeviceNameCancelAndSignOutKeepExplicitChoice() {
        launch()
        app.buttons["account.continueAnonymous"].tap()
        XCTAssertTrue(app.buttons["account.continueAnonymous"].waitForNonExistence(timeout: 10))
        #if os(iOS)
        app.buttons["gearshape"].tap()
        let account = app.staticTexts["Account"].firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 5), app.debugDescription)
        account.tap()
        #else
        app.typeKey(",", modifierFlags: .command)
        app.buttons["Account"].firstMatch.tap()
        #endif
        let rename = app.buttons["account.rename.550e8400-e29b-41d4-a716-446655440000"]
        #if os(iOS)
        let form = app.collectionViews.firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        for _ in 0..<12 {
            if rename.exists && rename.isHittable { break }
            form.swipeUp(velocity: .slow)
        }
        #else
        for _ in 0..<8 where !rename.isHittable { app.swipeUp() }
        #endif
        XCTAssertTrue(rename.isHittable, app.debugDescription)
        rename.tap()
        XCTAssertTrue(app.textFields["Device name"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Cancel"].firstMatch.tap()
        let signOut = app.buttons["Sign out"].firstMatch
        signOut.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        app.alerts.buttons["Sign out"].tap()
        XCTAssertTrue(app.buttons["account.continueAnonymous"].waitForExistence(timeout: 10), app.debugDescription)
        app.terminate(); launch()
        XCTAssertTrue(app.buttons["account.continueAnonymous"].exists)
    }

    #if os(iOS)
    func testFolderActionsStayReachableAtAccessibilityTextSize() {
        launch(largeText: true)
        let account = app.buttons["account.continueAnonymous"]
        for _ in 0..<5 where !account.isHittable { app.swipeUp() }
        account.tap()
        XCTAssertTrue(account.waitForNonExistence(timeout: 10))
        app.buttons["History"].firstMatch.tap()
        app.buttons["Manage folders"].tap()
        XCTAssertFalse(app.textFields["folders.name"].exists, "Overview should not show an unrelated editor")
        XCTAssertFalse(app.buttons["folders.save"].exists)
        let create = app.buttons["folders.create"]
        for _ in 0..<10 where !create.isHittable { app.swipeUp() }
        XCTAssertTrue(create.isHittable, app.debugDescription)
        create.tap()
        let name = app.textFields["folders.name"]
        // Swipe in the form, above its fixed action area at accessibility sizes.
        func scrollForm() {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)))
        }
        for _ in 0..<20 where !name.isHittable { scrollForm() }
        XCTAssertTrue(name.isHittable, app.debugDescription)
        name.tap(); name.typeText("Accessible project")
        let save = app.buttons["folders.save"]
        XCTAssertTrue(save.isHittable, "Create must stay above the keyboard")
        let keyboardEvidence = XCTAttachment(screenshot: app.screenshot())
        keyboardEvidence.name = "Folder editor at accessibility size with keyboard"
        keyboardEvidence.lifetime = .keepAlways; add(keyboardEvidence)
        save.tap()
        let created = app.staticTexts["Accessible project"].firstMatch
        for _ in 0..<20 where !created.isHittable { scrollForm() }
        XCTAssertTrue(created.isHittable, "The folder must actually be saved")
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Folders at accessibility text size"
        evidence.lifetime = .keepAlways; self.add(evidence)
        XCTAssertTrue(app.buttons["Close"].firstMatch.isHittable)
        app.buttons["Close"].firstMatch.tap()
    }
    #endif

    func testUpgradeConsentLeadsToOneGuideAndWorkingEmailAction() {
        launch("setup")
        app.buttons["account.continueAnonymous"].tap()
        XCTAssertTrue(app.buttons["account.continueAnonymous"].waitForNonExistence(timeout: 10))
        app.terminate(); launch("setupUpgrade")
        let allow = app.buttons["allow sending meeting audio and text to Deepgram and OpenAI"]
        XCTAssertTrue(allow.waitForExistence(timeout: 10), app.debugDescription)
        allow.tap()
        let accountStep = app.buttons["setup.step.account"]
        for _ in 0..<10 where !accountStep.isHittable || accountStep.frame.maxY >= app.buttons["setup.reopen"].frame.minY { app.swipeUp() }
        if accountStep.exists && !app.buttons["setup.action.account"].exists { accountStep.tap() }
        let add = app.buttons["setup.action.account"]
        for _ in 0..<8 where !add.isHittable || add.frame.maxY >= app.buttons["setup.reopen"].frame.minY { app.swipeUp() }
        XCTAssertTrue(add.isHittable, app.debugDescription)
        XCTAssertFalse(app.buttons["setup.action.calendar"].exists)
        XCTAssertFalse(app.buttons["account.continueAnonymous"].exists)
        add.tap()
        XCTAssertTrue(app.textFields["setup.email"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["Close"].firstMatch.tap()
    }

    func testHomeSetupStagesEmailAndCalendarWithCancellationAndPersistence() {
        launch("setup")
        app.buttons["account.continueAnonymous"].tap()
        XCTAssertTrue(app.buttons["account.continueAnonymous"].waitForNonExistence(timeout: 10))
        let accountStep = app.buttons["setup.step.account"]
        for _ in 0..<10 where !accountStep.isHittable || accountStep.frame.maxY >= app.buttons["setup.reopen"].frame.minY { app.swipeUp() }
        if accountStep.exists && !app.buttons["setup.action.account"].exists { accountStep.tap() }
        let add = app.buttons["setup.action.account"]
        for _ in 0..<6 where !add.isHittable || add.frame.maxY >= app.buttons["setup.reopen"].frame.minY { app.swipeUp() }
        XCTAssertTrue(add.isHittable, app.debugDescription)
        XCTAssertFalse(app.buttons["setup.action.calendar"].exists)
        add.tap()
        let email = app.textFields["setup.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap(); email.typeText("setup@example.invalid")
        app.buttons["setup.sendEmail"].tap()
        XCTAssertTrue(app.staticTexts["setup.emailNotice"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["setup.emailNotice"].label.contains("Link sent"))
        app.buttons["Close"].firstMatch.tap()
        app.buttons["setup.step.calendar"].tap()
        XCTAssertTrue(app.buttons["setup.action.calendar"].exists)
        XCTAssertFalse(app.buttons["setup.action.account"].exists)
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Home setup with calendar next"; evidence.lifetime = .keepAlways; self.add(evidence)
        let collapse = app.buttons["setup.collapse"]
        for _ in 0..<8 where !collapse.isHittable { app.swipeDown() }
        XCTAssertTrue(collapse.isHittable, app.debugDescription)
        collapse.tap()
        XCTAssertTrue(app.buttons["setup.reopen"].exists)
        app.terminate(); launch("setup")
        XCTAssertTrue(app.buttons["setup.reopen"].waitForExistence(timeout: 5))
        app.buttons["setup.reopen"].tap()
        let calendar = app.buttons["setup.step.calendar"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 5))
        let home = app.scrollViews.firstMatch
        for _ in 0..<10 where !calendar.isHittable || calendar.frame.maxY >= app.buttons["setup.reopen"].frame.minY {
            home.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(calendar.isHittable, app.debugDescription)
        if (calendar.value as? String)?.contains("collapsed") == true { calendar.tap() }
        XCTAssertTrue(app.buttons["setup.action.calendar"].waitForExistence(timeout: 5), app.debugDescription)
    }

    #if os(iOS)
    func testSetupHelpExplainsCalendarWithoutChangingItAtLargestTextSize() {
        checkSetupCalendarHelp(largeText: true)
    }

    func testSetupHelpKeepsDocsAndCloseVisible() {
        checkSetupCalendarHelp(largeText: false)
    }

    private func checkSetupCalendarHelp(largeText: Bool) {
        launch("setup", largeText: largeText)
        let account = app.buttons["account.continueAnonymous"]
        for _ in 0..<8 where !account.isHittable { app.swipeUp() }
        account.tap()
        XCTAssertTrue(account.waitForNonExistence(timeout: 10))
        let info = app.buttons["docs.calendar"]
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<18 {
            if info.isHittable && info.frame.minY > 100 && info.frame.maxY < app.buttons["setup.reopen"].frame.minY { break }
            let startY: CGFloat = info.frame.minY < 100 ? 0.35 : 0.65
            let endY: CGFloat = info.frame.minY < 100 ? 0.65 : 0.35
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: startY))
                .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: endY)))
        }
        XCTAssertTrue(info.isHittable, app.debugDescription)
        let before = app.buttons["setup.reopen"].value as? String
        let calendarBefore = app.buttons["setup.step.calendar"].value as? String
        info.tap()
        let docs = app.descendants(matching: .any)["docs.open.calendar"].firstMatch
        XCTAssertTrue(docs.waitForExistence(timeout: 5), app.debugDescription)
        let helpBody = app.scrollViews["docs.body.calendar"]
        for _ in 0..<8 where !docs.isHittable || docs.frame.maxY > app.frame.maxY - 40 { helpBody.swipeUp() }
        XCTAssertTrue(docs.isHittable, "The docs link must remain reachable at largest text")
        let close = app.buttons["docs.close.calendar"]
        XCTAssertTrue(close.isHittable)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = largeText ? "Setup calendar help at largest text" : "Setup calendar help"
        capture.lifetime = .keepAlways; add(capture)
        close.tap()
        XCTAssertEqual(app.buttons["setup.reopen"].value as? String, before)
        XCTAssertEqual(app.buttons["setup.step.calendar"].value as? String, calendarBefore,
                       "Help must not connect or complete the task")
    }

    func testHomeCalendarAndSetupShareOneSpace() {
        launch("calendar")
        app.buttons["account.continueAnonymous"].tap()
        XCTAssertTrue(app.buttons["account.continueAnonymous"].waitForNonExistence(timeout: 10))
        let header = app.buttons["calendar.section.tomorrow"]
        let toggle = app.buttons["home.calendar.toggle"]
        let setup = app.buttons["setup.reopen"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["⬢"].exists)
        XCTAssertFalse(app.staticTexts["miniti"].exists)
        XCTAssertFalse(app.staticTexts["multi-dimensional meetings"].exists)
        XCTAssertEqual(toggle.value as? String, "shown")
        let start = app.buttons["start meeting"]
        XCTAssertTrue(start.isHittable)
        let startY = start.frame.minY
        assertHomeFooterGeometry()
        setup.tap()
        XCTAssertTrue(header.waitForNonExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "hidden")
        XCTAssertTrue(app.buttons["setup.collapse"].exists)
        XCTAssertEqual(start.frame.minY, startY, accuracy: 1, "Opening setup must not recenter Start meeting")
        toggle.tap()
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["setup.collapse"].exists)
        XCTAssertEqual(start.frame.minY, startY, accuracy: 1)
        toggle.tap()
        XCTAssertTrue(header.waitForNonExistence(timeout: 5))
        XCTAssertEqual(start.frame.minY, startY, accuracy: 1)
        app.terminate(); launch("calendar")
        XCTAssertEqual(toggle.value as? String, "hidden")
        XCTAssertFalse(header.exists)
        setup.tap()
        let collapse = app.buttons["setup.collapse"]
        for _ in 0..<8 where !collapse.isHittable { app.swipeDown() }
        collapse.tap()
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Home calendar with shared presentation controls"; capture.lifetime = .keepAlways; add(capture)
    }

    func testHomeFooterAlignmentAtLargestTextSize() {
        launch("calendar", largeText: true)
        let account = app.buttons["account.continueAnonymous"]
        for _ in 0..<8 where !account.isHittable { app.scrollViews.firstMatch.swipeUp() }
        account.tap()
        XCTAssertTrue(account.waitForNonExistence(timeout: 10))
        assertHomeFooterGeometry()
        app.buttons["setup.reopen"].tap()
        assertHomeFooterGeometry()
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Home footer at largest text size"; capture.lifetime = .keepAlways; add(capture)
    }

    private func assertHomeFooterGeometry(file: StaticString = #filePath, line: UInt = #line) {
        let setup = app.buttons["setup.reopen"]
        let calendar = app.buttons["home.calendar.toggle"]
        let feedback = app.buttons["home.feedback"]
        let start = app.buttons["home.start"]
        let language = app.buttons["home.language"]
        XCTAssertTrue(language.exists, file: file, line: line)
        XCTAssertLessThanOrEqual(language.frame.maxY, start.frame.minY, file: file, line: line)
        XCTAssertGreaterThan(start.frame.minY, app.frame.midY, file: file, line: line)
        XCTAssertLessThan(start.frame.maxY, setup.frame.minY, file: file, line: line)
        for button in [setup, calendar, feedback] {
            XCTAssertTrue(button.isHittable, file: file, line: line)
            XCTAssertEqual(button.frame.minY, setup.frame.minY, accuracy: 1, file: file, line: line)
            XCTAssertEqual(button.frame.width, setup.frame.width, accuracy: 1, file: file, line: line)
            XCTAssertEqual(button.frame.height, setup.frame.height, accuracy: 1, file: file, line: line)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, file: file, line: line)
        }
    }

    func testCalendarSectionSpacerTogglesWithoutOpeningMeeting() {
        launch("calendar")
        app.buttons["account.continueAnonymous"].tap()
        XCTAssertTrue(app.buttons["account.continueAnonymous"].waitForNonExistence(timeout: 10))
        let header = app.buttons["calendar.section.tomorrow"]
        XCTAssertTrue(header.waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<6 where !header.isHittable { app.swipeUp() }
        XCTAssertTrue(header.isHittable)
        XCTAssertEqual(header.label, "tomorrow, 1 meeting")
        let event = app.staticTexts["Fixture tomorrow call"]
        XCTAssertTrue(event.exists)
        header.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).tap()
        XCTAssertTrue(event.waitForNonExistence(timeout: 5))
        XCTAssertEqual(header.value as? String, "collapsed")
        header.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).tap()
        XCTAssertTrue(event.waitForExistence(timeout: 5))
        XCTAssertEqual(header.value as? String, "expanded")
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Calendar full-width header"; capture.lifetime = .keepAlways; add(capture)
    }

    func testSetupTasksAndGuideCanBeHiddenAndRestoredFromGeneral() {
        launch("setup")
        app.buttons["account.continueAnonymous"].tap()
        XCTAssertTrue(app.buttons["account.continueAnonymous"].waitForNonExistence(timeout: 10))
        let footer = app.buttons["setup.reopen"]
        XCTAssertTrue(footer.waitForExistence(timeout: 5))
        let progress = footer.value as? String
        let collapse = app.buttons["setup.collapse"]
        for _ in 0..<6 where !collapse.isHittable { app.swipeUp() }
        collapse.tap()
        XCTAssertTrue(collapse.waitForNonExistence(timeout: 5))
        XCTAssertTrue(footer.isHittable)
        XCTAssertEqual(footer.value as? String, progress)
        footer.tap()
        XCTAssertTrue(collapse.waitForExistence(timeout: 5))
        let calendar = app.buttons["setup.step.calendar"]
        for _ in 0..<6 where !calendar.isHittable || calendar.frame.maxY >= app.buttons["setup.reopen"].frame.minY { app.swipeUp() }
        if !app.buttons["setup.skip.calendar"].exists { calendar.tap() }
        let skip = app.buttons["setup.skip.calendar"]
        for _ in 0..<6 where !skip.isHittable || skip.frame.maxY >= app.buttons["setup.reopen"].frame.minY { app.swipeUp() }
        skip.tap()
        XCTAssertTrue(calendar.waitForNonExistence(timeout: 5))
        XCTAssertEqual(footer.value as? String, progress)
        let hide = app.buttons["setup.dismiss"]
        for _ in 0..<6 where !hide.isHittable || hide.frame.maxY >= app.buttons["setup.reopen"].frame.minY { app.swipeUp() }
        hide.tap()
        XCTAssertTrue(footer.waitForNonExistence(timeout: 5))
        app.terminate(); launch("setup")
        XCTAssertFalse(app.buttons["setup.reopen"].exists)
        XCTAssertFalse(app.buttons["setup.collapse"].exists)
        app.buttons["Settings"].tap()
        app.staticTexts["General"].firstMatch.tap()
        let restore = app.buttons["setup.restore.calendar"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5), app.debugDescription)
        restore.tap()
        XCTAssertTrue(restore.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.switches["setup.settings.visible"].value as? String, "1")
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Setup restoration in General"; evidence.lifetime = .keepAlways; add(evidence)
        app.terminate(); launch("setup")
        XCTAssertTrue(app.buttons["setup.reopen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["setup.step.calendar"].exists)
    }

    func testHomeSetupEmailAtLargestTextSize() {
        launch("setup", largeText: true)
        let account = app.buttons["account.continueAnonymous"]
        for _ in 0..<8 where !account.isHittable { app.swipeUp() }
        account.tap()
        XCTAssertTrue(account.waitForNonExistence(timeout: 10))
        let home = app.scrollViews.firstMatch
        let accountStep = app.buttons["setup.step.account"]
        for _ in 0..<10 where !accountStep.isHittable || accountStep.frame.maxY >= home.frame.maxY { home.swipeUp(velocity: .slow) }
        XCTAssertTrue(accountStep.isHittable, app.debugDescription)
        XCTAssertLessThan(accountStep.frame.height, home.frame.height, "A task header must fit within the accessible viewport")
        let headerEvidence = XCTAttachment(screenshot: app.screenshot())
        headerEvidence.name = "Home setup task header at accessibility text size"
        headerEvidence.lifetime = .keepAlways; self.add(headerEvidence)
        if accountStep.exists && !app.buttons["setup.action.account"].exists { accountStep.tap() }
        let add = app.buttons["setup.action.account"]
        for _ in 0..<10 where !add.isHittable || add.frame.maxY >= home.frame.maxY { home.swipeUp(velocity: .slow) }
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Home setup at accessibility text size"; evidence.lifetime = .keepAlways; self.add(evidence)
        XCTAssertTrue(add.isHittable, app.debugDescription)
        add.tap()
        let email = app.textFields["setup.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        for _ in 0..<8 where !email.isHittable { app.swipeUp() }
        XCTAssertTrue(email.isHittable)
        XCTAssertTrue(app.buttons["Close"].firstMatch.isHittable)
        app.buttons["Close"].firstMatch.tap()
    }
    #endif

    func testFolderPreviewSummarizesBroadCategoriesBeforeApplying() {
        launch("folders")
        app.buttons["account.continueAnonymous"].tap()
        XCTAssertTrue(app.buttons["account.continueAnonymous"].waitForNonExistence(timeout: 10))
        app.buttons["History"].firstMatch.tap()
        app.buttons["Manage folders"].tap()
        app.buttons["folders.preview"].tap()
        let total = app.staticTexts["4 meetings across 2 folders"]
        XCTAssertTrue(total.waitForExistence(timeout: 5), app.debugDescription)
        let customers = app.staticTexts["Customers"].firstMatch
        for _ in 0..<8 where !customers.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(customers.isHittable, app.debugDescription)
        XCTAssertTrue(app.staticTexts["Customer conversations, sales calls and demos."].exists)
        XCTAssertEqual(app.staticTexts["folders.preview.count.Customers"].label, "2 meetings to file")
        let team = app.staticTexts["Team"].firstMatch
        for _ in 0..<5 where !team.isHittable { app.swipeUp() }
        XCTAssertTrue(team.isHittable, app.debugDescription)
        XCTAssertTrue(app.staticTexts["Team catch-ups, standups and one-to-ones."].exists)
        XCTAssertEqual(app.staticTexts["folders.preview.count.Team"].label, "2 meetings to file")
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Broad folder preview with counts and descriptions"
        evidence.lifetime = .keepAlways; add(evidence)
        let apply = app.buttons["folders.apply"]
        for _ in 0..<5 where !apply.isHittable { app.swipeUp() }
        apply.tap()
        XCTAssertTrue(total.waitForNonExistence(timeout: 5))
        app.buttons["Close"].firstMatch.tap()
    }

    func testFoldersCanBeCreatedAndRenamedInHistory() {
        launch()
        app.buttons["account.continueAnonymous"].tap()
        XCTAssertTrue(app.buttons["account.continueAnonymous"].waitForNonExistence(timeout: 10))
        app.buttons["History"].firstMatch.tap()
        app.buttons["Manage folders"].tap()
        XCTAssertFalse(app.textFields["folders.name"].exists, "Overview should not show an unrelated editor")
        XCTAssertFalse(app.buttons["folders.save"].exists)
        let overviewEvidence = XCTAttachment(screenshot: app.screenshot())
        overviewEvidence.name = "Folder journey overview on iPhone"
        overviewEvidence.lifetime = .keepAlways; add(overviewEvidence)
        let create = app.buttons["folders.create"]
        for _ in 0..<10 where !create.isHittable { app.swipeUp() }
        XCTAssertTrue(create.isHittable, app.debugDescription)
        create.tap()
        let name = app.textFields["folders.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), app.debugDescription)
        #if os(iOS)
        // Bring the whole field above the fixed footer before asking for keyboard focus.
        for _ in 0..<8 where !name.isHittable || name.frame.maxY >= app.buttons["folders.save"].frame.minY {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
        }
        XCTAssertLessThan(name.frame.maxY, app.buttons["folders.save"].frame.minY)
        #endif
        XCTAssertTrue(name.isHittable, app.debugDescription)
        name.tap(); name.typeText("Atlas project")
        let save = app.buttons["folders.save"]
        for _ in 0..<4 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isHittable, app.debugDescription)
        save.tap()
        let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'folders.edit.'")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(save.exists, "Save belongs only to the editor")
        edit.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Atlas project", app.debugDescription)
        name.tap(); name.typeText(" launch")
        for _ in 0..<4 where !save.isHittable { app.swipeUp() }
        save.tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Folders with synthetic project"
        screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Manage folders"].exists)
    }

    #if os(iOS)
    func testFolderSetupRequiresConfirmationAndCanBeHiddenAndRestored() {
        executionTimeAllowance = 120
        launch("setup")
        app.buttons["account.continueAnonymous"].tap()
        XCTAssertTrue(app.buttons["account.continueAnonymous"].waitForNonExistence(timeout: 10))
        let step = app.buttons["setup.step.folders"]
        for _ in 0..<12 where !step.isHittable || step.frame.maxY >= app.buttons["setup.reopen"].frame.minY { app.swipeUp() }
        XCTAssertTrue(step.isHittable, app.debugDescription)
        XCTAssertTrue((step.value as? String)?.contains("optional") == true)
        step.tap()
        let open = app.buttons["setup.action.folders"]
        for _ in 0..<5 where !open.isHittable || open.frame.maxY >= app.buttons["setup.reopen"].frame.minY { app.swipeUp() }
        open.tap()
        XCTAssertTrue(app.buttons["folders.create"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["folders.name"].exists)
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue((step.value as? String)?.contains("optional") == true, "Opening is not confirmation")
        app.buttons["setup.skip.folders"].tap()
        XCTAssertTrue(step.waitForNonExistence(timeout: 5))
        app.buttons["Settings"].tap()
        app.staticTexts["General"].firstMatch.tap()
        let restore = app.buttons["setup.restore.folders"]
        for _ in 0..<8 where !restore.isHittable { app.swipeUp() }
        restore.tap()
        app.terminate(); launch("setup")
        for _ in 0..<12 where !step.isHittable || step.frame.maxY >= app.buttons["setup.reopen"].frame.minY { app.swipeUp() }
        step.tap()
        for _ in 0..<5 where !open.isHittable || open.frame.maxY >= app.buttons["setup.reopen"].frame.minY { app.swipeUp() }
        open.tap()
        let confirm = app.buttons["setup.folders.confirm"]
        for _ in 0..<8 where !confirm.isHittable { app.swipeUp() }
        confirm.tap()
        let configured = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "configured"), object: step)
        XCTAssertEqual(XCTWaiter.wait(for: [configured], timeout: 5), .completed, app.debugDescription)
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Folder setup explicitly confirmed"; evidence.lifetime = .keepAlways; add(evidence)
    }

    #endif

    func testRecordStopHistoryPreservesFinalWordsOnce() {
        launch()
        app.buttons["account.continueAnonymous"].tap()
        XCTAssertTrue(app.buttons["account.continueAnonymous"].waitForNonExistence(timeout: 10))
        app.buttons["start meeting"].tap()
        let stop = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'stop'")).firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 10), app.debugDescription)
        stop.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Fixture final words'")).firstMatch.waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["History"].firstMatch.tap()
        let saved = app.buttons.matching(NSPredicate(format: "label CONTAINS '2 segments'"))
        XCTAssertTrue(saved.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(saved.count, 1)
        saved.firstMatch.tap()
        let transcript = app.buttons["transcript"].firstMatch
        if transcript.waitForExistence(timeout: 5) { transcript.tap() }
        let finalWords = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Fixture final words' OR value CONTAINS 'Fixture final words'")).firstMatch
        XCTAssertTrue(finalWords.waitForExistence(timeout: 10), app.debugDescription)
    }

}
