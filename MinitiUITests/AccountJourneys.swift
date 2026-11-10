import XCTest
#if os(macOS)
import AppKit
#else
import UIKit
#endif

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

    private func resetAccountMatrixFixture() {
        // Each previous case deliberately enrolled its synthetic account.
        app.terminate()
        app.launchArguments = ["-MinitiUITestCleanup"]
        app.launch()
        XCTAssertTrue(app.staticTexts["ui-test.ready"].waitForExistence(timeout: 10))
    }

    private func launch(_ scenario: String = "first", largeText: Bool = false, screenshotScene: String? = nil, interfaceScale: Int? = nil, usesSystemTextSize: Bool = false) {
        app = XCUIApplication()
        if let screenshotScene {
            app.launchArguments = ["-MinitiScreenshotScene", screenshotScene]
        }
        if scenario == "prepPresentation" {
            app.launchArguments += ["-homeSetup.hidden.v1", "YES", "-home.calendarHidden.v1", "NO"]
        }
        if let interfaceScale {
            // ScreenshotMode preserves explicit arguments in its volatile domain.
            app.launchArguments += ["-interfaceScale", String(interfaceScale)]
            app.launchEnvironment["MINITI_UI_TEST_READING_MATRIX"] = "1"
        }
        if largeText && !usesSystemTextSize {
            app.launchEnvironment["MINITI_UI_TEST_LARGE_TEXT"] = "1"
        } else if interfaceScale != nil && !usesSystemTextSize {
            app.launchEnvironment["MINITI_UI_TEST_NORMAL_TEXT"] = "1"
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

    private func openCoachingHistory(narrow: Bool = false) {
        launch(narrow ? "narrowCoaching" : "first", screenshotScene: "coaching")
        let history = app.buttons["coaching.tab.history"]
        XCTAssertTrue(history.waitForExistence(timeout: 10), app.debugDescription)
        #if os(macOS)
        history.click()
        #else
        history.tap()
        #endif
        XCTAssertTrue(app.buttons["coaching.sort.date"].waitForExistence(timeout: 10), app.debugDescription)
    }

    #if os(macOS)
    func testMacLiveNotesRemainEditableAtMinimumHeight() {
        launch(screenshotScene: "recording-insights")
        let copy = app.buttons["section.copy.notes"]
        let editor = app.textViews["meeting.notes.editor"]
        XCTAssertTrue(copy.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(editor.exists, app.debugDescription)
        // The divider sits above the header's 10pt inset and 24pt Copy target.
        let initialHeight = editor.frame.height
        let handle = copy.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: -80, dy: -14))
        handle.click(forDuration: 0.2, thenDragTo: handle.withOffset(CGVector(dx: 0, dy: -100)))
        XCTAssertGreaterThan(editor.frame.height, initialHeight + 80,
                             "Prove the real divider moved before checking its lower bound")
        let expandedHandle = copy.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: -80, dy: -14))
        expandedHandle.click(forDuration: 0.2,
                             thenDragTo: expandedHandle.withOffset(CGVector(dx: 0, dy: 180)))
        let capture = XCTAttachment(screenshot: app.windows["Miniti"].screenshot())
        capture.name = "Live notes at minimum pane height"
        capture.lifetime = .keepAlways; add(capture)
        let frames = XCTAttachment(string: "Copy: \(copy.frame)\nEditor: \(editor.frame)")
        frames.name = "Minimum notes editor frames"
        frames.lifetime = .keepAlways; add(frames)
        XCTAssertGreaterThanOrEqual(editor.frame.height, 32,
                                    "Keep room for a readable editable line below the header")
        XCTAssertTrue(editor.isHittable)
        let original = editor.value as? String ?? ""
        editor.click()
        editor.typeText(" UI1 minimum note")
        let updated = editor.value as? String ?? ""
        XCTAssertTrue(updated.contains("UI1 minimum note"))
        XCTAssertEqual(updated.count, original.count + " UI1 minimum note".count)
    }
    #endif

    #if os(macOS)
    func testLiveCoachingFillerSummariesKeepCountAndRateText() {
        launch(screenshotScene: "recording-coaching")
        let summaries = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coaching.fillers.summary."))
        XCTAssertTrue(summaries.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertGreaterThan(summaries.count, 0)
        for summary in summaries.allElementsBoundByIndex {
            let text = summary.value as? String ?? ""
            XCTAssertTrue(text.contains(" fillers ("), text)
            XCTAssertTrue(text.hasSuffix("/min)"), text)
        }
        captureAppScreen("Live Coaching readable filler summaries")
    }
    #endif

    func testCoachingStatsShowsAllSixAggregateValues() {
        launch(screenshotScene: "coaching")
        let stats = app.buttons["coaching.tab.stats"]
        XCTAssertTrue(stats.waitForExistence(timeout: 5), app.debugDescription)
        #if os(macOS)
        stats.click()
        #else
        stats.tap()
        #endif
        let values = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coaching.stats.all."))
        XCTAssertTrue(values.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(values.count, 6, app.debugDescription)
        for value in values.allElementsBoundByIndex {
            #if os(macOS)
            let text = value.value as? String ?? ""
            #else
            let text = value.label
            #endif
            XCTAssertFalse(text.isEmpty, "Aggregate values must remain exposed as readable native text")
        }
        captureAppScreen("Coaching stats aggregate values")
    }

    func testCoachingHistorySortTargetsDoNotOverlap() {
        openCoachingHistory()
        #if os(macOS)
        let minimum: CGFloat = 24
        #else
        let minimum: CGFloat = 44
        #endif
        #if os(iOS)
        XCTAssertFalse(app.scrollViews["coaching.history.horizontal"].exists,
                       "Normal-width history should not need horizontal scrolling")
        #endif
        guard assertCoachingSortFrames(minimum: minimum) else { return }
        let date = app.buttons["coaching.sort.date"]
        XCTAssertEqual(date.value as? String, "Descending")
        activateCoachingSort(date)
        XCTAssertEqual(date.value as? String, "Ascending")
        let firstRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Open ")).firstMatch
        XCTAssertEqual(firstRow.label, "Open Vendor call: data warehouse")
        for column in ["fillers", "pace", "clarity", "questions"] {
            let button = app.buttons["coaching.sort.\(column)"]
            activateCoachingSort(button)
            XCTAssertEqual(button.value as? String, "Ascending")
            XCTAssertTrue(button.isSelected)
            XCTAssertEqual(date.value as? String, "Not sorted")
        }
    }

    private func assertCoachingSortFrames(minimum: CGFloat) -> Bool {
        continueAfterFailure = true
        // XCUI can report 44pt as 43.99999999999997 after coordinate conversion.
        let epsilon: CGFloat = 0.001
        var frames = ""
        var previousFrame: CGRect?
        var validLayout = true
        for column in ["date", "name", "fillers", "pace", "clarity", "questions"] {
            let button = app.buttons["coaching.sort.\(column)"]
            XCTAssertTrue(button.exists)
            let frame = button.frame
            XCTAssertGreaterThanOrEqual(frame.width + epsilon, minimum, column)
            XCTAssertGreaterThanOrEqual(frame.height + epsilon, minimum, column)
            if let previousFrame {
                XCTAssertLessThanOrEqual(previousFrame.maxX, frame.minX + epsilon, column)
                validLayout = validLayout && previousFrame.maxX <= frame.minX + epsilon
            }
            validLayout = validLayout && frame.width + epsilon >= minimum && frame.height + epsilon >= minimum
            frames += "\(column): \(frame)\n"
            previousFrame = frame
        }
        let evidence = XCTAttachment(string: frames)
        evidence.name = "Coaching history sort target frames"
        evidence.lifetime = .keepAlways; add(evidence)
        captureAppScreen("Coaching history sort targets")
        continueAfterFailure = false
        return validLayout
    }

    private func activateCoachingSort(_ button: XCUIElement) {
        let padding = button.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: 2))
        #if os(macOS)
        padding.click()
        #else
        padding.tap()
        #endif
    }

    private func captureAppScreen(_ name: String) {
        #if os(macOS)
        let capture = XCTAttachment(screenshot: app.windows["Miniti"].screenshot())
        #else
        let capture = XCTAttachment(screenshot: app.screenshot())
        #endif
        capture.name = name
        capture.lifetime = .keepAlways; add(capture)
    }

    #if os(iOS)
    func testSavedActionItemsHaveNoTemporaryCompletionControls() {
        launch(screenshotScene: "meeting")
        let text = "Share the data retention and deletion policy with Marcus"
        let action = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)).firstMatch
        for _ in 0..<5 {
            if action.exists && action.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(action.exists && action.isHittable, app.debugDescription)
        captureAppScreen("Saved action rows without completion controls")
        let completionButtons = app.buttons.matching(NSPredicate(format: "label IN %@", ["[ ]", "[x]"]))
        XCTAssertEqual(completionButtons.count, 0,
                       "Meeting actions must not imply a completion state that is never saved")
        action.tap()
        XCTAssertEqual(completionButtons.count, 0)
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Action text is selectable, not editable")
        app.buttons["meeting.section.notes"].tap()
        app.buttons["meeting.section.insights"].tap()
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertEqual(completionButtons.count, 0)
    }

    func testSavedInsightListSharesTextAndOffersSelectionMenu() {
        launch(screenshotScene: "meeting")
        let first = "Share the data retention and deletion policy with Marcus"
        let last = "Send the security questionnaire back before Friday"
        let actions = app.textViews.matching(NSPredicate(format: "value CONTAINS %@", first)).firstMatch
        for _ in 0..<5 {
            if actions.exists && actions.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(actions.exists && actions.isHittable, app.debugDescription)
        XCTAssertTrue((actions.value as? String)?.contains(last) == true,
                      "All action items must share one selectable text surface")
        captureAppScreen("Saved insight lists before selection")
        actions.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 50, dy: 8)).press(forDuration: 1)
        let copy = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Copy'")).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        captureAppScreen("Saved action native selection menu")
    }

    func testLiveMeetingSectionsHaveSharedTargetsAndRetainNotes() {
        launch(screenshotScene: "recording-insights")
        assertMeetingSectionNavigation()
    }

    func testSavedMeetingSectionsHaveSharedTargetsAndRetainNotes() {
        launch(screenshotScene: "meeting")
        assertMeetingSectionNavigation()
    }

    func testLiveMeetingNavigationAtLargestTextAcrossInterfaceScales() {
        assertMeetingNavigationAtTextSize(scene: "recording-insights", largeText: true)
    }

    func testSavedMeetingNavigationAtLargestTextAcrossInterfaceScales() {
        assertMeetingNavigationAtTextSize(scene: "meeting", largeText: true)
    }

    func testLiveMeetingNavigationAtNormalTextAcrossInterfaceScales() {
        assertMeetingNavigationAtTextSize(scene: "recording-insights", largeText: false)
    }

    func testSavedMeetingNavigationAtNormalTextAcrossInterfaceScales() {
        assertMeetingNavigationAtTextSize(scene: "meeting", largeText: false)
    }

    private func assertMeetingNavigationAtTextSize(scene: String, largeText: Bool) {
        executionTimeAllowance = 180
        for scale in 0...2 {
            app?.terminate()
            launch("readingMatrix", largeText: largeText, screenshotScene: scene, interfaceScale: scale)
            let metrics = app.staticTexts["ui-test.readingMetrics"]
            XCTAssertTrue(metrics.waitForExistence(timeout: 5))
            let category = largeText ? "largest" : "normal"
            XCTAssertEqual(metrics.label, "Reading scale \(scale), text \(category)",
                           "Prove the requested scale reaches the actual scene")
            for section in ["transcript", "insights", "notes"] {
                let button = app.buttons["meeting.section.\(section)"]
                XCTAssertTrue(button.waitForExistence(timeout: 5))
                XCTAssertTrue(button.isHittable)
                XCTAssertGreaterThanOrEqual(button.frame.minX, app.frame.minX)
                XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX + 0.5)
                XCTAssertGreaterThanOrEqual(button.frame.minY, app.frame.minY)
                XCTAssertLessThanOrEqual(button.frame.maxY, app.frame.maxY + 0.5)
            }
            captureAppScreen("\(scene) \(category) text, interface scale \(scale)")
            assertMeetingSectionNavigation()
        }
    }

    private func assertMeetingSectionNavigation() {
        let sections = ["transcript", "insights", "notes"]
        var previous: CGRect?
        var frames = ""
        for section in sections {
            let button = app.buttons["meeting.section.\(section)"]
            XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertEqual(button.label, section)
            let frame = button.frame
            XCTAssertGreaterThanOrEqual(frame.width + 0.001, 44)
            XCTAssertGreaterThanOrEqual(frame.height + 0.001, 44)
            if let previous {
                XCTAssertEqual(previous.width, frame.width, accuracy: 0.5,
                               "Section targets must have equal widths")
                XCTAssertEqual(previous.maxX, frame.minX, accuracy: 0.5,
                               "Section targets must meet without a dead gap")
                XCTAssertLessThanOrEqual(previous.maxX, frame.minX + 0.001)
            }
            frames += "\(section): \(frame)\n"
            previous = frame
        }
        let attachment = XCTAttachment(string: frames)
        attachment.name = "Meeting section target frames"
        attachment.lifetime = .keepAlways; add(attachment)
        captureAppScreen("Meeting section picker before navigation")
        XCTAssertTrue(app.buttons["meeting.section.insights"].isSelected)
        for section in ["transcript", "notes"] {
            app.buttons["meeting.section.\(section)"].coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: 2, dy: 2)).tap()
            for candidate in sections {
                XCTAssertEqual(app.buttons["meeting.section.\(candidate)"].isSelected, candidate == section)
            }
            XCTAssertFalse(app.buttons["insights.update"].exists)
        }
        let notes = app.textViews["meeting.notes.editor"]
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        notes.tap()
        notes.typeText(" UI2 retained note")
        let edited = notes.value as? String
        XCTAssertTrue(edited?.contains("UI2 retained note") == true)
        app.buttons["meeting.section.insights"].tap()
        XCTAssertTrue(app.buttons["insights.update"].waitForExistence(timeout: 5))
        XCTAssertFalse(notes.exists)
        app.buttons["meeting.section.notes"].tap()
        XCTAssertEqual(notes.value as? String, edited)
    }

    func testNarrowCoachingHistoryScrollsWithoutShrinkingTargets() {
        openCoachingHistory(narrow: true)
        guard assertCoachingSortFrames(minimum: 44) else { return }
        let scroll = app.scrollViews["coaching.history.horizontal"]
        XCTAssertTrue(scroll.exists)
        XCTAssertLessThan(scroll.frame.width, 328)
        let meeting = app.buttons["coaching.sort.name"]
        activateCoachingSort(meeting)
        XCTAssertEqual(meeting.value as? String, "Descending")
        captureAppScreen("Narrow Coaching history with meeting sort selected")
        scroll.swipeLeft()
        let questions = app.buttons["coaching.sort.questions"]
        XCTAssertEqual(questions.frame.intersection(scroll.frame).width, 44, accuracy: 0.5,
                       "The full target must become visible after scrolling")
        activateCoachingSort(questions)
        XCTAssertEqual(questions.value as? String, "Ascending")
        captureAppScreen("Narrow Coaching history after horizontal scrolling")
    }

    func testCoachingHistoryMetricHelpHasNamedCloseTarget() {
        openCoachingHistory()
        let fillers = app.buttons["coaching.sort.fillers"]
        let originalSort = fillers.value as? String
        fillers.press(forDuration: 0.6)
        let close = app.buttons["coaching.help.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), app.debugDescription)
        captureAppScreen("Coaching history metric help")
        XCTAssertGreaterThanOrEqual(close.frame.width, 44)
        XCTAssertGreaterThanOrEqual(close.frame.height, 44)
        XCTAssertEqual(close.label, "Close metric help")
        let title = app.staticTexts["Fillers"]
        XCTAssertTrue(title.exists)
        XCTAssertEqual(title.frame.midY, close.frame.midY, accuracy: 1)
        close.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: 2)).tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        XCTAssertEqual(fillers.value as? String, originalSort,
                       "Opening metric help must not also change the sort")
    }
    #endif

    func testLiveInsightUpdateHasMinimumTarget() {
        launch(screenshotScene: "recording-insights")
        assertInsightUpdateTarget()
    }

    func testLiveStandardSectionsKeepNamesOrderAndCoverage() {
        launch(screenshotScene: "recording-insights")
        assertStandardSectionOrder(saved: false)
        captureAppScreen("Live standard sections")
    }

    func testSavedStandardSectionsKeepNamesOrderAndCoverage() {
        launch(screenshotScene: "meeting")
        assertStandardSectionOrder(saved: true)
        captureAppScreen("Saved standard sections")
        #if os(macOS)
        let discussion = app.textViews.matching(NSPredicate(format: "value CONTAINS %@",
            "Marcus demoed the Attio pipeline and the fields reps must fill")).firstMatch
        XCTAssertTrue(discussion.exists, app.debugDescription)
        let discussionText = discussion.value as? String ?? ""
        XCTAssertTrue(discussionText.hasPrefix("1. Marcus"))
        XCTAssertTrue(discussionText.contains("4. Rollout plan for the remaining reps after the pilot"))
        let actions = app.textViews.matching(NSPredicate(format: "value CONTAINS %@",
            "Share the data retention and deletion policy with Marcus")).firstMatch
        XCTAssertTrue(actions.exists, app.debugDescription)
        XCTAssertTrue((actions.value as? String)?.contains("Send the security questionnaire back before Friday") == true,
                      "All actions must share one native text surface")
        let pane = app.windows["Miniti"].scrollViews.allElementsBoundByIndex.max { $0.frame.minX < $1.frame.minX }
        XCTAssertNotNil(pane)
        for _ in 0..<4 {
            if actions.isHittable { break }
            pane?.scroll(byDeltaX: 0, deltaY: -300)
        }
        XCTAssertTrue(actions.isHittable, app.debugDescription)
        captureAppScreen("Saved Mac selectable standard lists")
        #endif
    }

    private func assertStandardSectionOrder(saved: Bool) {
        var expected = ["discussion", "actions", "topics"]
        #if os(iOS)
        if saved { expected.insert("decisions", at: 2) }
        #endif
        // Summary also names the mode tab; the remaining section names are unique.
        let names = ["discussion", "actions", "action items", "decisions", "topics"]
        XCTAssertTrue(app.staticTexts["discussion"].waitForExistence(timeout: 5), app.debugDescription)
        #if os(macOS)
        let headings = app.staticTexts.matching(NSPredicate(format: "value IN %@", names))
        XCTAssertEqual(headings.allElementsBoundByIndex.map { $0.value as? String ?? "<unreadable>" }, expected,
                       app.debugDescription)
        #else
        let headings = app.staticTexts.matching(NSPredicate(format: "label IN %@", names))
        XCTAssertEqual(headings.allElementsBoundByIndex.map(\.label), expected, app.debugDescription)
        #endif
    }

    func testLiveSalesSectionsKeepNamedFieldOrder() {
        launch(screenshotScene: "recording-sales")
        assertSalesSectionOrder()
        captureAppScreen("Live Sales sections")
    }

    func testSavedSalesSectionsKeepNamedFieldOrder() {
        launch(screenshotScene: "meeting")
        #if os(macOS)
        let more = app.menuButtons["More insight views"]
        #else
        let more = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == 'More insight views'")).firstMatch
        #endif
        XCTAssertTrue(more.waitForExistence(timeout: 5), app.debugDescription)
        #if os(macOS)
        more.click()
        let sales = app.menuItems["Sales"]
        XCTAssertTrue(sales.waitForExistence(timeout: 5), app.debugDescription)
        sales.click()
        #else
        more.tap()
        let sales = app.buttons["Sales"]
        XCTAssertTrue(sales.waitForExistence(timeout: 5), app.debugDescription)
        sales.tap()
        #endif
        assertSalesSectionOrder()
        captureAppScreen("Saved Sales sections")
    }

    private func assertSalesSectionOrder() {
        let expected = ["metrics", "economic buyer", "decision criteria", "decision process",
                        "paper process", "identified pain", "champion", "competition"]
        XCTAssertTrue(app.staticTexts["metrics"].waitForExistence(timeout: 5), app.debugDescription)
        #if os(macOS)
        let headings = app.staticTexts.matching(NSPredicate(format: "value IN %@", expected))
        XCTAssertEqual(headings.allElementsBoundByIndex.map { $0.value as? String ?? "<unreadable>" },
                       expected, app.debugDescription)
        #else
        let headings = app.staticTexts.matching(NSPredicate(format: "label IN %@", expected))
        XCTAssertEqual(headings.allElementsBoundByIndex.map(\.label), expected, app.debugDescription)
        #endif
    }

    func testSavedInsightUpdateHasMinimumTarget() {
        launch(screenshotScene: "meeting")
        assertInsightUpdateTarget()
    }

    private func assertInsightUpdateTarget() {
        let update = app.buttons["insights.update"].firstMatch
        XCTAssertTrue(update.waitForExistence(timeout: 10), app.debugDescription)
        #if os(macOS)
        let minimum: CGFloat = 24
        let capture = XCTAttachment(screenshot: app.windows["Miniti"].screenshot())
        #else
        let minimum: CGFloat = 44
        let capture = XCTAttachment(screenshot: app.screenshot())
        #endif
        capture.name = "Insight Update target in production layout"
        capture.lifetime = .keepAlways
        add(capture)
        XCTAssertGreaterThanOrEqual(update.frame.width, minimum)
        XCTAssertGreaterThanOrEqual(update.frame.height, minimum)
        XCTAssertTrue(update.isHittable)
        var frames = "update: \(update.frame)"
        let modeRowY = app.buttons["summary"].firstMatch.frame.midY
        for label in ["summary", "questions", "coaching"] {
            // Mac also has a Coaching sidebar action. Select the actual mode row.
            let matches = app.buttons.matching(identifier: label).allElementsBoundByIndex
                .filter { abs($0.frame.midY - modeRowY) < 1 }
            XCTAssertEqual(matches.count, 1, "Expected one insight mode in this row: \(label)")
            guard let tab = matches.first else { return }
            let overlap = update.frame.intersection(tab.frame)
            XCTAssertTrue(overlap.isNull || overlap.isEmpty,
                          "Update overlaps \(label): \(overlap)")
            frames += "\n\(label): \(tab.frame)"
        }
        let frameEvidence = XCTAttachment(string: frames)
        frameEvidence.name = "Update and neighboring mode target frames"
        frameEvidence.lifetime = .keepAlways
        add(frameEvidence)
        assertNeutralUpdateChrome(update)
        // Layout-only: screenshot scenes do not stub user-triggered AI requests.
        // Action dispatch for the shared target primitive is covered separately.
    }

    func testLiveInsightUpdateStaysDisabledDuringGeneration() {
        launch("insightUpdating", screenshotScene: "recording-insights")
        #if os(macOS)
        assertGeneratingUpdate(hasProgress: false)
        #else
        assertGeneratingUpdate(hasProgress: true)
        #endif
    }

    func testSavedInsightUpdateStaysDisabledDuringGeneration() {
        launch("insightUpdating", screenshotScene: "meeting")
        assertGeneratingUpdate(hasProgress: true)
    }

    private func assertGeneratingUpdate(hasProgress: Bool) {
        let update = app.buttons["insights.update"]
        XCTAssertTrue(update.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(update.isEnabled, "Generation in progress must keep the real Update button disabled")
        #if os(macOS)
        let minimum: CGFloat = 24
        #else
        let minimum: CGFloat = 44
        #endif
        XCTAssertGreaterThanOrEqual(update.frame.width, minimum)
        XCTAssertGreaterThanOrEqual(update.frame.height, minimum)
        var frames = "disabled update: \(update.frame)"
        if hasProgress {
            let indicator = app.descendants(matching: .any).matching(identifier: "insights.update.progress").firstMatch
            let status = app.staticTexts["updating..."].firstMatch
            for neighbor in [indicator, status] {
                XCTAssertTrue(neighbor.waitForExistence(timeout: 5), app.debugDescription)
                XCTAssertGreaterThan(neighbor.frame.width, 0)
                XCTAssertGreaterThan(neighbor.frame.height, 0)
                let overlap = update.frame.intersection(neighbor.frame)
                XCTAssertTrue(overlap.isNull || overlap.isEmpty, "Busy Update overlaps its progress sibling")
                frames += "\nprogress sibling: \(neighbor.frame)"
            }
        }
        let evidence = XCTAttachment(string: frames)
        evidence.name = "Busy Update and progress frames"
        evidence.lifetime = .keepAlways; add(evidence)
        captureAppScreen("Update disabled during generation")
        // Never activate a production AI action from the offline screenshot scenes.
    }

    func testInsightUpdateLabelKeepsNativeActionsAndDisabledState() {
        launch("insightUpdateTargets")
        let update = app.buttons["update.fixture.enabled"]
        let regenerate = app.buttons["update.fixture.regenerate"]
        let disabled = app.buttons["update.fixture.disabled"]
        XCTAssertTrue(update.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(update.isEnabled && regenerate.isEnabled)
        XCTAssertFalse(disabled.isEnabled)
        XCTAssertTrue(regenerate.label.contains("regenerate") && regenerate.label.contains("sales"))
        XCTAssertTrue(disabled.label.contains("finishing"))
        #if os(macOS)
        let minimum: CGFloat = 24
        #else
        let minimum: CGFloat = 44
        #endif
        for control in [update, regenerate, disabled] {
            XCTAssertGreaterThanOrEqual(control.frame.width, minimum)
            XCTAssertGreaterThanOrEqual(control.frame.height, minimum)
            let coordinate = control.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: 1))
            #if os(macOS)
            coordinate.click()
            #else
            coordinate.tap()
            #endif
        }
        let counts = app.staticTexts["update.fixture.counts"]
        let expected = "update=1 regenerate=1 disabled=0"
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@ OR value == %@", expected, expected), object: counts)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 3), .completed,
                       "Native enabled buttons act once; disabled target never dispatches")
        captureAppScreen("Shared Update native actions and disabled target")
    }

    private func assertNeutralUpdateChrome(_ update: XCUIElement) {
        #if os(macOS)
        // Keep the real pointer off the control: this check owns resting chrome.
        app.windows["Miniti"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).hover()
        #endif
        let native = update.screenshot().image
        do {
            #if os(macOS)
            let raster = try XCTUnwrap(native.cgImage(forProposedRect: nil, context: nil, hints: nil))
            #else
            let raster = try XCTUnwrap(native.cgImage)
            #endif
            var pixels = [UInt8](repeating: 0, count: raster.width * raster.height * 4)
            let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
            try pixels.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: raster.width, height: raster.height,
                    bitsPerComponent: 8, bytesPerRow: raster.width * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(raster, in: CGRect(x: 0, y: 0, width: raster.width, height: raster.height))
            }
            var panelPixels = 0
            for i in stride(from: 0, to: pixels.count, by: 4) {
                if abs(Int(pixels[i]) - 15) <= 3 && abs(Int(pixels[i + 1]) - 15) <= 3 && abs(Int(pixels[i + 2]) - 17) <= 3 {
                    panelPixels += 1
                }
            }
            let fraction = Double(panelPixels) / Double(raster.width * raster.height)
            XCTAssertGreaterThan(fraction, 0.2,
                                 "Update must use neutral panel chrome, not just a thin background strip around the target")
        } catch {
            XCTFail("Could not inspect the real Update control: \(error)")
        }
    }

    #if os(macOS)
    func testMacLiveSectionCopiesHaveNamedMinimumTargets() throws {
        launch(screenshotScene: "recording-insights")
        try assertMacSectionCopies(saved: false)
    }

    func testMacSavedSectionCopiesHaveNamedMinimumTargets() throws {
        launch(screenshotScene: "meeting")
        try assertMacSectionCopies(saved: true)
    }

    private func assertMacSectionCopies(saved: Bool) throws {
        let pasteboard = NSPasteboard.general
        // Never read or rewrite the user's clipboard, including password-manager items.
        try XCTSkipUnless(pasteboard.types?.isEmpty != false,
                          "Section-copy journeys require an empty clipboard; existing content is left untouched.")
        var lastCopyChangeCount: Int?
        defer {
            if let lastCopyChangeCount, pasteboard.changeCount == lastCopyChangeCount {
                pasteboard.clearContents()
            }
        }
        let expectedNotes = saved ? "weekly digest of pilot usage" : "run the pilot day to day"
        let expectedInsights = saved ? "Technical review" : "40-person sales team"
        var frames = ""
        for (section, expectedText) in [("transcript", "Attio"), ("notes", expectedNotes), ("insights", expectedInsights)] {
            let copy = app.buttons["section.copy.\(section)"]
            XCTAssertTrue(copy.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertGreaterThanOrEqual(copy.frame.width, 24)
            XCTAssertGreaterThanOrEqual(copy.frame.height, 24)
            XCTAssertEqual(copy.label, "Copy \(section)")
            let title = app.staticTexts["section.title.\(section)"]
            XCTAssertTrue(title.exists)
            XCTAssertTrue(copy.frame.intersection(title.frame).isEmpty,
                          "Copy must not overlap its header title")
            frames += "\(section) title: \(title.frame); copy: \(copy.frame)\n"
            if !saved && section == "notes" {
                let shortcut = app.staticTexts["⌘⇧N"].firstMatch
                XCTAssertTrue(shortcut.exists)
                XCTAssertTrue(copy.frame.intersection(shortcut.frame).isEmpty,
                              "Copy must not overlap the neighboring keyboard hint")
            }
            // The top point is inside the allocated target but outside the compact chrome.
            copy.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: 1)).click()
            let observedChangeCount = pasteboard.changeCount
            let copiedExpectedSection = (pasteboard.string(forType: .string) ?? "").contains(expectedText)
            if copiedExpectedSection && pasteboard.changeCount == observedChangeCount {
                lastCopyChangeCount = observedChangeCount
            }
            XCTAssertTrue(copiedExpectedSection,
                          "Copy must put the correct synthetic section on the clipboard")
            XCTAssertEqual(copy.label, "\(section.capitalized) copied")
        }
        let frameEvidence = XCTAttachment(string: frames)
        frameEvidence.name = "Section Copy target and neighboring title frames"
        frameEvidence.lifetime = .keepAlways; add(frameEvidence)
        let capture = XCTAttachment(screenshot: app.windows["Miniti"].screenshot())
        capture.name = "Section Copy controls in production layout"
        capture.lifetime = .keepAlways; add(capture)
    }

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

    func testMacEmailGuidanceGrowsWithInterfaceScale() {
        executionTimeAllowance = 120
        var compactHeight: CGFloat = 0
        for scale in [0, 2] {
            app?.terminate()
            launch("appearance", interfaceScale: scale)
            app.buttons["account.signIn"].click()
            let probe = app.buttons["ui-test.readingScope.accessEmail"]
            XCTAssertTrue(probe.waitForExistence(timeout: 5))
            XCTAssertTrue(probe.label.contains("scale \(scale);"))
            probe.click()
            XCTAssertTrue(probe.waitForNonExistence(timeout: 5))
            let heading = app.staticTexts["account.emailSignIn.heading"]
            XCTAssertTrue(heading.waitForExistence(timeout: 5))
            if scale == 0 { compactHeight = heading.frame.height }
            else { XCTAssertGreaterThan(heading.frame.height, compactHeight + 1) }
            let cancel = app.buttons["Cancel"].firstMatch
            XCTAssertTrue(cancel.isHittable)
            XCTAssertFalse(app.buttons["Send link"].isEnabled)
            let frames = XCTAttachment(string: "scale=\(scale); heading=\(heading.frame); cancel=\(cancel.frame)")
            frames.name = "Mac email reading geometry"; frames.lifetime = .keepAlways; add(frames)
            captureAppScreen("Mac email interface scale \(scale)")
            app.activate()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
            cancel.click()
            XCTAssertTrue(heading.waitForNonExistence(timeout: 5))
        }
    }

    func testMacRecoveryKeySaveAtInterfaceScales() {
        executionTimeAllowance = 180
        var compactHeight: CGFloat = 0
        for scale in [0, 2] {
            if app != nil { resetAccountMatrixFixture() }
            launch("setup", interfaceScale: scale)
            app.activate()
            let guest = app.buttons["account.continueAnonymous"]
            XCTAssertTrue(guest.waitForExistence(timeout: 5)); guest.click()
            XCTAssertTrue(guest.waitForNonExistence(timeout: 10))
            let step = app.buttons["setup.step.account"]
            XCTAssertTrue(step.waitForExistence(timeout: 5))
            let open = app.buttons["setup.account.recovery"]
            if !open.exists { step.click() }
            XCTAssertTrue(open.waitForExistence(timeout: 5)); open.click()
            let probe = app.buttons["ui-test.readingScope.saveRecovery"]
            XCTAssertTrue(probe.waitForExistence(timeout: 5))
            XCTAssertTrue(probe.label.contains("scale \(scale);")); probe.click()
            XCTAssertTrue(probe.waitForNonExistence(timeout: 5))
            let key = app.staticTexts["account.recoveryKey.value"]
            XCTAssertTrue(key.waitForExistence(timeout: 5))
            if scale == 0 { compactHeight = key.frame.height }
            else { XCTAssertGreaterThan(key.frame.height, compactHeight) }
            let next = app.buttons["account.recoveryKey.continue"]
            XCTAssertFalse(next.isEnabled)
            app.checkBoxes["account.recoveryKey.saved"].click()
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: next)
            XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
            captureAppScreen("Mac fixture recovery key scale \(scale)")
            app.activate(); next.click()
            XCTAssertTrue(key.waitForNonExistence(timeout: 5))
        }
    }

    private func requireMacKeyboardNavigation() throws {
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        let mode = app.staticTexts["ui-test.keyboardNavigation"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        let state = try XCTUnwrap(mode.value as? String)
        XCTAssertTrue(["Keyboard navigation on", "Keyboard navigation off"].contains(state),
                      "Keyboard navigation badge must be readable")
        try XCTSkipUnless(state == "Keyboard navigation on",
                          "Enable Keyboard Navigation for this acceptance run, then restore its original state.")
    }

    func testMacHomeSearchShortcutAndDelayedReactivation() throws {
        launch("homeKeyboard", screenshotScene: "home")
        app.activate()
        let mode = app.staticTexts["ui-test.keyboardNavigation"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        let navigation = try XCTUnwrap(mode.value as? String)
        XCTAssertTrue(["Keyboard navigation on", "Keyboard navigation off"].contains(navigation))
        let state = app.staticTexts["ui-test.homeSearchState"]
        XCTAssertTrue(state.waitForExistence(timeout: 5))
        func assertSearch(_ expected: String) {
            let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: state)
            XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 5), .completed)
        }
        assertSearch("Search inactive")
        // Exercise reactivation after the sidebar's initial 1.5s focus guard.
        // This does not model a process whose first activation is delayed.
        let settings = XCUIApplication(bundleIdentifier: "com.apple.systempreferences")
        let settingsWasRunning = settings.state != .notRunning
        defer { if !settingsWasRunning { settings.terminate() } }
        settings.activate()
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        let elapsed = expectation(description: "Beyond initial sidebar focus guard")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { elapsed.fulfill() }
        wait(for: [elapsed], timeout: 3)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        assertSearch("Search inactive")
        let lateFocus = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Search active"), object: state)
        lateFocus.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [lateFocus], timeout: 2), .completed,
                       "Search must remain inactive while delayed focus callbacks settle")
        captureAppScreen("Home after delayed reactivation, \(navigation)")
        app.typeKey("/", modifierFlags: [])
        assertSearch("Search active")
        let search = app.textFields["search meetings"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        app.typeText("Halcyon")
        XCTAssertEqual(search.value as? String, "Halcyon")
        app.typeKey(.escape, modifierFlags: [])
        assertSearch("Search inactive")
        XCTAssertEqual(search.value as? String, "")
        captureAppScreen("Home after keyboard search and Escape, \(navigation)")
    }

    func testMacSharedUpdateSupportsKeyboardAndKeepsDisabledInactive() throws {
        launch("insightUpdateTargets")
        try requireMacKeyboardNavigation()
        let counts = app.staticTexts["update.fixture.counts"]
        XCTAssertFalse(app.buttons["update.fixture.disabled"].isEnabled)
        for step in 0..<8 {
            app.typeKey(.tab, modifierFlags: [])
            if step < 2 { captureAppScreen("Update keyboard focus \(step)") }
            app.typeKey(.space, modifierFlags: [])
            let value = counts.value as? String ?? counts.label
            XCTAssertTrue(value.contains("disabled=0"))
            if !value.contains("update=0") && !value.contains("regenerate=0") { break }
        }
        let value = counts.value as? String ?? counts.label
        XCTAssertFalse(value.contains("update=0") || value.contains("regenerate=0"))
        XCTAssertTrue(value.contains("disabled=0"))
        captureAppScreen("Native Update keyboard action counters")
    }

    func testMacSharedTabsAndMenuSupportKeyboard() throws {
        launch("controlTargets")
        try requireMacKeyboardNavigation()
        let counts = app.staticTexts["target.counts"]
        let menuCounts = app.staticTexts["target.menuCounts"]
        for step in 0..<20 {
            app.typeKey(.tab, modifierFlags: [])
            if step < 3 { captureAppScreen("Shared controls keyboard focus \(step)") }
            app.typeKey(.space, modifierFlags: [])
            if app.menuItems["Choose"].exists {
                app.typeKey(.downArrow, modifierFlags: [])
                app.typeKey(.return, modifierFlags: [])
            }
            let value = counts.value as? String ?? counts.label
            let menuValue = menuCounts.value as? String ?? menuCounts.label
            XCTAssertTrue(menuValue.contains("disabled=0"))
            if !value.contains("left=0") && !value.contains("right=0") &&
                !menuValue.contains("menu=0") && app.buttons["target.tab.history"].isSelected { break }
        }
        let value = counts.value as? String ?? counts.label
        let menuValue = menuCounts.value as? String ?? menuCounts.label
        XCTAssertFalse(value.contains("left=0") || value.contains("right=0"))
        XCTAssertFalse(menuValue.contains("menu=0"))
        XCTAssertTrue(menuValue.contains("disabled=0"))
        XCTAssertTrue(app.buttons["target.tab.history"].isSelected)
        captureAppScreen("Native shared control keyboard outcomes")
    }

    func testMacDocsAnswerCopiesUsingKeyboardOnly() throws {
        let pasteboard = NSPasteboard.general
        try XCTSkipUnless(pasteboard.types?.isEmpty != false,
                          "Keyboard Copy requires an empty clipboard; existing content is left untouched.")
        var copiedChangeCount: Int?
        defer {
            if let copiedChangeCount, pasteboard.changeCount == copiedChangeCount {
                pasteboard.clearContents()
            }
        }
        launch("docsTargets")
        try requireMacKeyboardNavigation()
        XCTAssertTrue(app.buttons["Copy answer"].waitForExistence(timeout: 5))
        for _ in 0..<12 {
            app.typeKey(.tab, modifierFlags: [])
            let beforeCopy = pasteboard.changeCount
            app.typeKey(.space, modifierFlags: [])
            if app.buttons["Answer copied"].exists {
                XCTAssertEqual(pasteboard.changeCount, beforeCopy + 1,
                               "Copied feedback must accompany exactly one clipboard change")
                // Do not clear a concurrent copy observed after this action.
                if pasteboard.changeCount == beforeCopy + 1 {
                    copiedChangeCount = beforeCopy + 1
                }
                break
            }
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

    func testBillingAndCompactTabsAtNormalTextAcrossScales() {
        for scale in 0...2 { assertBillingAndCompactTabs(scale: scale, largest: false) }
    }

    func testBillingAndCompactTabsAtLargestTextAcrossScales() {
        for scale in 0...2 { assertBillingAndCompactTabs(scale: scale, largest: true) }
    }

    private func enterBillingFixture(scale: Int, largest: Bool, realSystem: Bool = false) {
        if app != nil { resetAccountMatrixFixture() }
        launch(realSystem ? "realOSReading" : "billingMatrix", largeText: largest,
               interfaceScale: scale, usesSystemTextSize: realSystem)
        let ready = app.staticTexts["ui-test.readingMetrics"]
        XCTAssertTrue(ready.waitForExistence(timeout: 5))
        XCTAssertEqual(ready.label, "Reading scale \(scale), text \(largest ? "largest" : "normal")")
        app.buttons["ui-test.hideStatus"].tap()
        XCTAssertTrue(app.staticTexts["ui-test.ready"].waitForNonExistence(timeout: 5))
        let guest = app.buttons["account.continueAnonymous"]
        for _ in 0..<8 {
            if guest.isHittable { break }
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(guest.isHittable); guest.tap()
        XCTAssertTrue(guest.waitForNonExistence(timeout: 10))
    }

    private func assertBillingAndCompactTabs(scale: Int, largest: Bool) {
        executionTimeAllowance = 420
        enterBillingFixture(scale: scale, largest: largest)
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        for title in ["Coaching", "History", "Record"] {
            let tab = bar.buttons[title]
            XCTAssertTrue(tab.isHittable); tab.tap()
            XCTAssertTrue(tab.isSelected)
        }
        let tabs = ["Record", "Coaching", "History"].map { bar.buttons[$0] }
        for tab in tabs {
            XCTAssertGreaterThanOrEqual(tab.frame.width, 44 - 0.001)
            XCTAssertGreaterThanOrEqual(tab.frame.height, 44 - 0.001)
        }
        let tabFrames = tabs.map { $0.frame }
        let geometry = XCTAttachment(string: "tabs=\(tabFrames)")
        geometry.name = "Native tab target frames"; geometry.lifetime = .keepAlways; add(geometry)
        // Native accessibility rectangles overlap on iOS 27. Centre dispatch
        // above is verified; these rectangles do not prove exclusive hit regions.
        captureAppScreen("Native tabs \(largest ? "largest" : "normal") scale \(scale)")
        app.buttons["Settings"].tap()
        let scope = app.buttons["ui-test.readingScope.settings"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        XCTAssertEqual(scope.label, "scale \(scale); reading \(largest ? "largest" : "normal"); controls \(largest ? "accessibility5" : ["large", "xLarge", "xxLarge"][scale])")
        scope.tap(); XCTAssertTrue(scope.waitForNonExistence(timeout: 5))
        app.staticTexts["Account"].firstMatch.tap()
        let form = app.collectionViews.firstMatch
        let purchase = app.buttons["billing.purchase"]
        for _ in 0..<20 {
            if purchase.isHittable { break }
            form.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(purchase.isHittable)
        let title = app.staticTexts["billing.plan.title"]
        XCTAssertGreaterThanOrEqual(title.frame.width, title.frame.height,
                                    "Plan must not become a broken-word column")
        XCTAssertGreaterThanOrEqual(purchase.frame.height, 44 - 0.001)
        captureAppScreen("Plan and purchase \(largest ? "largest" : "normal") scale \(scale)")
        let restore = app.buttons["billing.restore"]
        for _ in 0..<16 {
            if restore.isHittable { break }
            form.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(restore.isHittable)
        XCTAssertGreaterThanOrEqual(restore.frame.height, 44 - 0.001)
        let terms = app.descendants(matching: .any)["billing.terms"].firstMatch
        let privacy = app.descendants(matching: .any)["billing.privacy"].firstMatch
        XCTAssertTrue(terms.exists); XCTAssertTrue(privacy.exists)
        for link in [terms, privacy] {
            XCTAssertGreaterThanOrEqual(link.frame.height, 44 - 0.001)
        }
        XCTAssertFalse(terms.frame.intersects(privacy.frame))
        captureAppScreen("Purchase disclosure and restore \(largest ? "largest" : "normal") scale \(scale)")
        let explanation = app.staticTexts["billing.restore.explanation"]
        for _ in 0..<8 {
            if explanation.isHittable { break }
            form.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(explanation.isHittable)
        captureAppScreen("Restore explanation \(largest ? "largest" : "normal") scale \(scale)")
        // Read-only billing check: do not purchase, restore or open external links.
    }

    func testRealSystemTextChangeReachesOpenSettings() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MINITI_REAL_OS_READING"] == "1",
                          "Requires the coordinated simulator text-size run and restoration of the original setting.")
        executionTimeAllowance = 150
        enterBillingFixture(scale: 2, largest: false, realSystem: true)
        app.buttons["Settings"].tap()
        let scope = app.buttons["ui-test.readingScope.settings"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        XCTAssertEqual(scope.label, "scale 2; reading normal; controls xxLarge")
        print("MINITI_REAL_OS_WAIT: change the simulator OS category now")
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "scale 2; reading largest; controls accessibility5"), object: scope)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 90), .completed)
        captureAppScreen("Open Settings adopts actual OS largest text without relaunch")
        scope.tap(); XCTAssertTrue(scope.waitForNonExistence(timeout: 5))
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
    }

    func testZRealSystemMeetingPickerLargeContentViewer() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MINITI_REAL_OS_READING"] == "1",
                          "Requires the coordinated simulator text-size run and restoration of the original setting.")
        executionTimeAllowance = 90
        launch("realOSReading", screenshotScene: "meeting", interfaceScale: 2, usesSystemTextSize: true)
        let ready = app.staticTexts["ui-test.readingMetrics"]
        XCTAssertTrue(ready.waitForExistence(timeout: 5))
        XCTAssertEqual(ready.label, "Reading scale 2, text largest")
        app.buttons["ui-test.hideStatus"].tap()
        let transcript = app.buttons["meeting.section.transcript"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 5))
        // The result recording is inspected during this hold, not after release.
        print("MINITI_LARGE_CONTENT_HOLD")
        transcript.press(forDuration: 3)
        captureAppScreen("Meeting picker after native large-content hold")
        let notes = app.buttons["meeting.section.notes"]
        notes.tap(); XCTAssertTrue(notes.isSelected)
        XCTAssertTrue(app.textViews["meeting.notes.editor"].waitForExistence(timeout: 5))
    }

    func testPendingAccountEmailActionsKeepMinimumTargets() {
        for largest in [false, true] { assertAccountEmailStateTargets(pending: true, largest: largest) }
    }

    func testAccountDeviceActionsAtNormalAndLargestText() {
        executionTimeAllowance = 240
        for largest in [false, true] {
            if app != nil { resetAccountMatrixFixture() }
            launch("first", largeText: largest, interfaceScale: 2)
            let guest = app.buttons["account.continueAnonymous"]
            XCTAssertTrue(guest.waitForExistence(timeout: 5))
            for _ in 0..<8 {
                if guest.isHittable { break }
                app.swipeUp(velocity: .slow)
            }
            guest.tap()
            XCTAssertTrue(guest.waitForNonExistence(timeout: 10))
            app.buttons["Settings"].tap()
            let scope = app.buttons["ui-test.readingScope.settings"]
            XCTAssertTrue(scope.waitForExistence(timeout: 5)); scope.tap()
            XCTAssertTrue(scope.waitForNonExistence(timeout: 5))
            app.staticTexts["Account"].firstMatch.tap()
            let id = "550e8400-e29b-41d4-a716-446655440000"
            let rename = app.buttons["account.rename.\(id)"]
            let remove = app.buttons["account.device.remove.\(id)"]
            let title = app.staticTexts["account.device.title.\(id)"]
            let form = app.collectionViews.firstMatch
            for _ in 0..<16 {
                if rename.isHittable && remove.isHittable { break }
                form.swipeUp(velocity: .slow)
            }
            XCTAssertTrue(rename.isHittable)
            XCTAssertTrue(remove.isHittable)
            for action in [rename, remove] {
                XCTAssertGreaterThanOrEqual(action.frame.width, 44 - 0.001)
                XCTAssertGreaterThanOrEqual(action.frame.height, 44 - 0.001)
                XCTAssertFalse(action.frame.intersects(title.frame))
            }
            XCTAssertFalse(rename.frame.intersects(remove.frame))
            let frames = XCTAttachment(string: "title=\(title.frame); rename=\(rename.frame); remove=\(remove.frame)")
            frames.name = "Account device row \(largest ? "largest" : "normal")"
            frames.lifetime = .keepAlways; add(frames)
            captureAppScreen("Account device actions \(largest ? "largest" : "normal")")
            rename.tap()
            XCTAssertTrue(app.alerts.textFields["Device name"].waitForExistence(timeout: 5))
            app.alerts.buttons["Cancel"].tap()
            XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout: 5))
            remove.tap()
            XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
            app.alerts.buttons["Cancel"].tap()
            XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout: 5))
            XCTAssertTrue(rename.exists, "Cancelling removal keeps the fixture device")
            XCTAssertFalse(app.buttons["account.continueAnonymous"].exists)
        }
    }

    func testUnavailableAccountEmailRetryKeepsMinimumTarget() {
        for largest in [false, true] { assertAccountEmailStateTargets(pending: false, largest: largest) }
    }

    private func assertAccountEmailStateTargets(pending: Bool, largest: Bool) {
        executionTimeAllowance = 180
        if app != nil { resetAccountMatrixFixture() }
        launch(pending ? "accountEmailPending" : "accountEmailError", largeText: largest, interfaceScale: largest ? 2 : 0)
        let guest = app.buttons["account.continueAnonymous"]
        XCTAssertTrue(guest.waitForExistence(timeout: 5))
        for _ in 0..<8 {
            if guest.isHittable { break }
            app.swipeUp(velocity: .slow)
        }
        guest.tap()
        XCTAssertTrue(guest.waitForNonExistence(timeout: 10))
        app.buttons["Settings"].tap()
        let scope = app.buttons["ui-test.readingScope.settings"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5)); scope.tap()
        XCTAssertTrue(scope.waitForNonExistence(timeout: 5))
        app.staticTexts["Account"].firstMatch.tap()
        let form = app.collectionViews.firstMatch
        let identifiers = pending ? ["account.email.resend", "Change", "account.email.remove"] : ["account.email.retry"]
        for identifier in identifiers {
            let action = app.buttons[identifier]
            for _ in 0..<16 {
                if action.exists && action.isHittable { break }
                form.swipeUp(velocity: .slow)
            }
            XCTAssertTrue(action.isHittable)
            XCTAssertGreaterThanOrEqual(action.frame.width, 44 - 0.001)
            XCTAssertGreaterThanOrEqual(action.frame.height, 44 - 0.001)
        }
        // Read all frames again at the final scroll position, never compare
        // coordinates captured before and after a scroll.
        let frames = identifiers.map { app.buttons[$0].frame }
        for (left, right) in zip(frames, frames.dropFirst()) {
            XCTAssertFalse(left.intersects(right))
        }
        let attachment = XCTAttachment(string: zip(identifiers, frames).map { "\($0): \($1)" }.joined(separator: "\n"))
        attachment.name = "Email state targets \(pending ? "pending" : "error") \(largest ? "largest" : "normal")"
        attachment.lifetime = .keepAlways; add(attachment)
        captureAppScreen("Email state \(pending ? "pending" : "error") \(largest ? "largest" : "normal")")
        // No Resend, Remove or Retry action is invoked by this geometry check.
    }

    func testAccountEmailEditorAtNormalTextAcrossScales() {
        for scale in 0...2 { assertAccountEmailEditor(scale: scale, largest: false) }
    }

    func testAccountEmailEditorAtLargestTextAcrossScales() {
        for scale in 0...2 { assertAccountEmailEditor(scale: scale, largest: true) }
    }

    private func assertAccountEmailEditor(scale: Int, largest: Bool) {
        executionTimeAllowance = 300
        if app != nil { resetAccountMatrixFixture() }
        launch("first", largeText: largest, interfaceScale: scale)
        let guest = app.buttons["account.continueAnonymous"]
        XCTAssertTrue(guest.waitForExistence(timeout: 5))
        for _ in 0..<8 {
            if guest.isHittable { break }
            app.swipeUp(velocity: .slow)
        }
        guest.tap()
        XCTAssertTrue(guest.waitForNonExistence(timeout: 10))
        app.buttons["Settings"].tap()
        let scope = app.buttons["ui-test.readingScope.settings"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5)); scope.tap()
        XCTAssertTrue(scope.waitForNonExistence(timeout: 5))
        app.staticTexts["Account"].firstMatch.tap()
        let form = app.collectionViews.firstMatch
        let addEmail = app.buttons["account.email.add"]
        for _ in 0..<16 {
            if addEmail.exists && addEmail.isHittable { break }
            form.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(addEmail.isHittable)
        captureAppScreen("Account email entry \(largest ? "largest" : "normal") scale \(scale)")
        addEmail.tap()
        let field = app.textFields["account.email.draft"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        // An address needs a usable editing width on this 393pt iPhone fixture.
        XCTAssertGreaterThanOrEqual(field.frame.width, 280)
        let send = app.buttons["account.email.send"]
        let cancel = app.buttons["account.email.cancel"]
        XCTAssertFalse(send.isEnabled)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("layout@example.invalid")
        XCTAssertTrue(NSPredicate(format: "value == %@", "layout@example.invalid").evaluate(with: field))
        XCTAssertTrue(send.isEnabled)
        var frameEvidence = "field=\(field.frame); keyboard=\(app.keyboards.firstMatch.frame); cancel=\(cancel.frame)\n"
        for _ in 0..<16 {
            let keyboardTop = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : form.frame.maxY
            let top = max(form.frame.minY, app.navigationBars["Account"].frame.maxY) + 12
            let bottom = min(form.frame.maxY, keyboardTop) - 12
            if cancel.isHittable && cancel.frame.minY >= top && cancel.frame.maxY <= bottom { break }
            XCTAssertGreaterThan(bottom - top, 100)
            let lower = bottom - (bottom - top) * 0.15
            let upper = top + (bottom - top) * 0.2
            let needsDown = cancel.frame.maxY < top
            let x = form.frame.minX + form.frame.width * 0.05
            let start = CGPoint(x: x, y: needsDown ? upper : lower)
            let end = CGPoint(x: x, y: needsDown ? lower : upper)
            frameEvidence += "drag=\(start)->\(end); cancel=\(cancel.frame)\n"
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: start.x, dy: start.y))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: end.x, dy: end.y)))
        }
        frameEvidence += "final field=\(field.frame); send=\(send.frame); cancel=\(cancel.frame); keyboard=\(app.keyboards.firstMatch.frame)"
        let frames = XCTAttachment(string: frameEvidence)
        frames.name = "Account email editor frames \(largest ? "largest" : "normal") scale \(scale)"
        frames.lifetime = .keepAlways; add(frames)
        XCTAssertTrue(cancel.isHittable)
        let finalKeyboardTop = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : form.frame.maxY
        XCTAssertGreaterThanOrEqual(cancel.frame.minY, app.navigationBars["Account"].frame.maxY)
        XCTAssertLessThanOrEqual(cancel.frame.maxY, min(form.frame.maxY, finalKeyboardTop))
        for button in [send, cancel] {
            XCTAssertGreaterThanOrEqual(button.frame.width, 44 - 0.001)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44 - 0.001)
            XCTAssertFalse(button.frame.intersects(field.frame))
        }
        XCTAssertFalse(send.frame.intersects(cancel.frame))
        captureAppScreen("Account email editing \(largest ? "largest" : "normal") scale \(scale)")
        cancel.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    }

    func testAccountRecoveryRowAtNormalTextAcrossScales() {
        for scale in 0...2 { assertAccountRecoveryRow(scale: scale, largest: false) }
    }

    func testAccountRecoveryRowAtLargestTextAcrossScales() {
        for scale in 0...2 { assertAccountRecoveryRow(scale: scale, largest: true) }
    }

    private func assertAccountRecoveryRow(scale: Int, largest: Bool) {
        executionTimeAllowance = 240
        if app != nil { resetAccountMatrixFixture() }
        launch("first", largeText: largest, interfaceScale: scale)
        let guest = app.buttons["account.continueAnonymous"]
        XCTAssertTrue(guest.waitForExistence(timeout: 5))
        for _ in 0..<8 {
            if guest.isHittable { break }
            app.swipeUp(velocity: .slow)
        }
        guest.tap()
        XCTAssertTrue(guest.waitForNonExistence(timeout: 10))
        app.buttons["Settings"].tap()
        let scope = app.buttons["ui-test.readingScope.settings"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5)); scope.tap()
        XCTAssertTrue(scope.waitForNonExistence(timeout: 5))
        app.staticTexts["Account"].firstMatch.tap()
        let form = app.collectionViews.firstMatch
        let title = app.staticTexts["account.recovery.title"]
        for _ in 0..<16 {
            if title.exists && title.isHittable { break }
            form.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(title.isHittable)
        let status = app.staticTexts["account.recovery.status"]
        XCTAssertTrue(status.exists)
        // Reject the captured narrow columns; captures still own full wrapping proof.
        XCTAssertGreaterThanOrEqual(title.frame.width, title.frame.height * 2)
        XCTAssertGreaterThanOrEqual(status.frame.width, status.frame.height)
        for identifier in ["account.recovery.show", "account.recovery.replace"] {
            let button = app.buttons[identifier]
            for _ in 0..<16 {
                if button.exists && button.isHittable { break }
                form.swipeUp(velocity: .slow)
            }
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.width, 44 - 0.001)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44 - 0.001)
            let sibling = app.buttons[identifier == "account.recovery.show" ? "account.recovery.replace" : "account.recovery.show"]
            XCTAssertFalse(button.frame.intersects(sibling.frame))
            captureAppScreen("Recovery row \(largest ? "largest" : "normal") scale \(scale) \(identifier)")
            button.tap()
            let confirmation = app.buttons[identifier == "account.recovery.show" ? "Show key" : "Replace key"]
            XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons[identifier == "account.recovery.show" ? "Replace key" : "Show key"].exists)
            let cancel = app.buttons["Cancel"].firstMatch
            if cancel.exists {
                cancel.tap()
            } else {
                // iOS 27 presents this native confirmation as a popover, with
                // a dismissal region rather than a visible Cancel action.
                let backdrop = app.otherElements["PopoverDismissRegion"]
                XCTAssertTrue(backdrop.waitForExistence(timeout: 5))
                let point = CGPoint(x: backdrop.frame.minX + backdrop.frame.width * 0.02,
                                    y: backdrop.frame.midY)
                XCTAssertFalse(app.popovers.firstMatch.frame.contains(point))
                backdrop.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).tap()
            }
            XCTAssertTrue(confirmation.waitForNonExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Hide"].exists)
        }
    }

    func testFallbackEmailRestoreKeepsFailureVisible() {
        assertFallbackRestore(recovery: false, succeeds: false)
    }

    func testFallbackKeyRestoreKeepsFailureVisible() {
        assertFallbackRestore(recovery: true, succeeds: false)
    }

    func testFallbackKeyRestoreShowsLargestTextErrorAboveKeyboard() {
        assertFallbackRestore(recovery: true, succeeds: false, largeText: true)
    }

    func testFallbackEmailRestoreShowsLargestTextError() {
        assertFallbackRestore(recovery: false, succeeds: false, largeText: true)
    }

    func testFallbackEmailWaitingAtLargestText() {
        assertFallbackRestore(recovery: false, succeeds: false, largeText: true, waitsForApproval: true)
    }

    func testFallbackEmailRestoreCompletesWithoutReopening() {
        assertFallbackRestore(recovery: false, succeeds: true)
    }

    func testFallbackKeyRestoreCompletesWithoutReopening() {
        assertFallbackRestore(recovery: true, succeeds: true)
    }

    private func assertFallbackRestore(recovery: Bool, succeeds: Bool, largeText: Bool = false, waitsForApproval: Bool = false) {
        executionTimeAllowance = 120
        launch(waitsForApproval ? "accountFallbackWaiting" : succeeds ? "accountFallbackSuccess" : "accountFallbackFailure", largeText: largeText, interfaceScale: largeText ? 2 : 0)
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let scope = app.buttons["ui-test.readingScope.settings"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        scope.tap()
        app.staticTexts["Account"].firstMatch.tap()
        let entry = app.buttons[recovery ? "Sign in with recovery key…" : "Sign in with email…"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15), app.debugDescription)
        entry.tap()
        let probe = app.buttons["ui-test.readingScope.account" + (recovery ? "Key" : "Email") + "Restore"]
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        probe.tap()
        XCTAssertTrue(probe.waitForNonExistence(timeout: 5))
        let field = recovery
            ? app.textFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH 'M1-'")).firstMatch
            : app.textFields["Email"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        if recovery || largeText {
            for _ in 0..<16 {
                if field.isHittable { break }
                app.scrollViews[recovery ? "account.restore.scroll" : "account.emailSignIn.scroll"].swipeUp(velocity: .slow)
            }
        }
        XCTAssertTrue(field.isHittable)
        field.tap()
        field.typeText(recovery ? "M1-000G-40R4-0M30-E209-185G-R38E-1WET-S870" : "fixture@example.invalid")
        let submit = recovery
            ? app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Sign in", "account.signIn")).element
            : app.buttons["Send link"]
        XCTAssertTrue(submit.isEnabled)
        submit.tap()
        if waitsForApproval {
            let status = app.staticTexts["account.emailSignIn.waiting"]
            XCTAssertTrue(status.waitForExistence(timeout: 10))
            assertEmailResponseVisible(status)
            XCTAssertFalse(field.isEnabled)
            XCTAssertFalse(submit.isEnabled)
            captureAppScreen("Email awaiting approval at largest text")
            app.buttons["Cancel"].firstMatch.tap()
            XCTAssertTrue(app.buttons["Cancel"].firstMatch.waitForNonExistence(timeout: 5))
        } else if succeeds {
            XCTAssertTrue(app.buttons["Cancel"].firstMatch.waitForNonExistence(timeout: 20))
            XCTAssertTrue(app.buttons["Switch account…"].waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertFalse(app.buttons["Cancel"].firstMatch.exists)
        } else {
            let error = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "fixture_restore_failed")).firstMatch
            XCTAssertTrue(error.waitForExistence(timeout: 20), app.debugDescription)
            XCTAssertTrue(field.exists, "The original sheet keeps its input and error")
            XCTAssertEqual(field.value as? String, recovery ? "M1-000G-40R4-0M30-E209-185G-R38E-1WET-S870" : "fixture@example.invalid")
            if !recovery { XCTAssertTrue(app.buttons["Try again"].exists) }
            if largeText && !recovery {
                assertEmailResponseVisible(app.staticTexts["account.emailSignIn.error"])
                for label in ["Cancel", "Try again", "New link"] {
                    let action = app.buttons[label].firstMatch
                    XCTAssertTrue(action.isHittable)
                    XCTAssertGreaterThanOrEqual(action.frame.height, 44 - 0.001)
                }
            }
            if largeText && recovery {
                let sheetError = app.staticTexts["account.restore.error"]
                let scroll = app.scrollViews["account.restore.scroll"]
                let keyboard = app.keyboards.firstMatch
                XCTAssertTrue(keyboard.exists)
                let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    sheetError.isHittable && sheetError.frame.minY >= scroll.frame.minY - 1
                        && sheetError.frame.maxY <= scroll.frame.maxY + 1
                }, object: nil)
                let result = XCTWaiter.wait(for: [visible], timeout: 5)
                let frames = XCTAttachment(string: "error=\(sheetError.frame); scroll=\(scroll.frame); keyboard=\(keyboard.frame)")
                frames.name = "Recovery failure visibility"; frames.lifetime = .keepAlways; add(frames)
                captureAppScreen("Largest recovery failure with keyboard")
                XCTAssertEqual(result, .completed, "The returned error must be visible without another user scroll")
                XCTAssertLessThanOrEqual(sheetError.frame.maxY, keyboard.frame.minY)
            }
            captureAppScreen("Fallback restore failure retains sheet and input")
            app.buttons["Cancel"].firstMatch.tap()
            XCTAssertTrue(app.buttons["Cancel"].firstMatch.waitForNonExistence(timeout: 5))
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
        }
        captureAppScreen("Fallback restore completed")
    }

    private func assertEmailResponseVisible(_ status: XCUIElement) {
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let scroll = app.scrollViews["account.emailSignIn.scroll"]
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            status.isHittable && status.frame.minY >= scroll.frame.minY - 1
                && status.frame.maxY <= scroll.frame.maxY + 1
        }, object: nil)
        let result = XCTWaiter.wait(for: [visible], timeout: 5)
        let frames = XCTAttachment(string: "status=\(status.frame); scroll=\(scroll.frame)")
        frames.name = "Email response visibility"; frames.lifetime = .keepAlways; add(frames)
        captureAppScreen("Email response after keyboard dismissal")
        XCTAssertEqual(result, .completed)
    }

    func testSettingsEmailRestoreInheritsInterfaceSize() {
        assertSettingsAccountPresentation(move: false, recovery: false, largeText: false)
    }

    func testSettingsKeyRestoreInheritsInterfaceSize() {
        assertSettingsAccountPresentation(move: false, recovery: true, largeText: false)
    }

    func testSettingsEmailMoveInheritsInterfaceSize() {
        assertSettingsAccountPresentation(move: true, recovery: false, largeText: false)
    }

    func testSettingsKeyMoveInheritsInterfaceSize() {
        assertSettingsAccountPresentation(move: true, recovery: true, largeText: false)
    }

    func testSettingsEmailRestoreAtLargestText() {
        assertSettingsAccountPresentation(move: false, recovery: false, largeText: true)
    }

    func testSettingsKeyRestoreAtLargestText() {
        assertSettingsAccountPresentation(move: false, recovery: true, largeText: true)
    }

    func testSettingsEmailMoveAtLargestText() {
        assertSettingsAccountPresentation(move: true, recovery: false, largeText: true)
    }

    func testSettingsKeyMoveAtLargestText() {
        assertSettingsAccountPresentation(move: true, recovery: true, largeText: true)
    }

    private func assertSettingsAccountPresentation(move: Bool, recovery: Bool, largeText: Bool) {
        executionTimeAllowance = 150
        launch(move ? "first" : "accountKeyUnavailable", largeText: largeText, interfaceScale: 2)
        if move {
            let guest = app.buttons["account.continueAnonymous"]
            XCTAssertTrue(guest.waitForExistence(timeout: 5))
            for _ in 0..<8 {
                if guest.isHittable { break }
                app.swipeUp(velocity: .slow)
            }
            XCTAssertTrue(guest.isHittable)
            guest.tap()
            XCTAssertTrue(guest.waitForNonExistence(timeout: 10))
        }
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        XCTAssertTrue(settings.isHittable)
        settings.tap()
        let settingsScope = app.buttons["ui-test.readingScope.settings"]
        XCTAssertTrue(settingsScope.waitForExistence(timeout: 5))
        settingsScope.tap()
        XCTAssertTrue(settingsScope.waitForNonExistence(timeout: 5))
        let account = app.staticTexts["Account"].firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        XCTAssertTrue(account.isHittable)
        account.tap()
        let form = app.collectionViews.firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        let menu = app.buttons[move ? "Switch account…" : "Sign in again…"]
        for _ in 0..<16 {
            if menu.exists && menu.isHittable { break }
            form.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(menu.isHittable, app.debugDescription)
        // Form exposes the whole row plus the actual Menu label as a child button.
        // Tap that label, not the empty middle of the row's accessibility frame.
        let menuLabel = menu.buttons.firstMatch
        XCTAssertTrue(menuLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(menu.isEnabled)
        XCTAssertGreaterThan(menuLabel.frame.width, 0)
        captureAppScreen("Account menu before opening")
        let menuFrames = XCTAttachment(string: "Row: \(menu.frame)\nLabel: \(menuLabel.frame)\nForm: \(form.frame)")
        menuFrames.name = "Account menu target frames"; menuFrames.lifetime = .keepAlways; add(menuFrames)
        menu.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: menuLabel.frame.midX - menu.frame.minX,
            dy: menuLabel.frame.midY - menu.frame.minY
        )).tap()
        let method = app.buttons[recovery ? "With recovery key…" : "With email…"]
        XCTAssertTrue(method.waitForExistence(timeout: 5))
        method.tap()
        let name = "account" + (recovery ? "Key" : "Email") + (move ? "Move" : "Restore")
        let probe = app.buttons["ui-test.readingScope.\(name)"]
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        XCTAssertEqual(probe.label, "scale 2; reading \(largeText ? "largest" : "normal"); controls \(largeText ? "accessibility5" : "xxLarge")")
        probe.tap()
        XCTAssertTrue(probe.waitForNonExistence(timeout: 5))
        let submit = recovery && !move
            ? app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Sign in", "account.signIn")).element
            : app.buttons[recovery ? "Switch" : "Send link"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        XCTAssertFalse(submit.isEnabled)
        if recovery { assertRecoveryReadingAndTyping(largeText: largeText) }
        else { assertEmailReadingAndTyping(largeText: largeText) }
        captureAppScreen("\(name) \(largeText ? "largest" : "normal") scale 2")
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(cancel.isHittable)
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 5))
        app.terminate()
    }

    func testAccessEmailInheritsInterfaceSize() {
        assertAccessPresentation(recovery: false, largeText: false, scale: 2)
    }

    func testAccessRecoveryInheritsInterfaceSize() {
        assertAccessPresentation(recovery: true, largeText: false, scale: 2)
    }

    func testAccessEmailAtNormalTextAcrossInterfaceScales() {
        executionTimeAllowance = 180
        for scale in 0...2 { assertAccessPresentation(recovery: false, largeText: false, scale: scale) }
    }

    func testAccessEmailAtLargestTextAcrossInterfaceScales() {
        executionTimeAllowance = 180
        for scale in 0...2 { assertAccessPresentation(recovery: false, largeText: true, scale: scale) }
    }

    func testAccessRecoveryAtNormalTextAcrossInterfaceScales() {
        executionTimeAllowance = 180
        for scale in 0...2 { assertAccessPresentation(recovery: true, largeText: false, scale: scale) }
    }

    func testAccessRecoveryAtLargestTextAcrossInterfaceScales() {
        executionTimeAllowance = 180
        for scale in 0...2 { assertAccessPresentation(recovery: true, largeText: true, scale: scale) }
    }

    private func assertAccessPresentation(recovery: Bool, largeText: Bool, scale: Int) {
        launch(largeText: largeText, interfaceScale: scale)
        let signIn = app.buttons["account.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 10))
        for _ in 0..<6 {
            if signIn.isHittable { break }
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(signIn.isHittable)
        signIn.tap()
        let email = app.textFields["Email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        if recovery {
            let useKey = app.buttons["Use a recovery key"]
            XCTAssertTrue(useKey.waitForExistence(timeout: 5))
            XCTAssertTrue(useKey.isHittable)
            useKey.tap()
            XCTAssertTrue(app.textFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH 'M1-'")).firstMatch.waitForExistence(timeout: 5))
        }
        let name = recovery ? "accessRecovery" : "accessEmail"
        let probe = app.buttons["ui-test.readingScope.\(name)"]
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        XCTAssertEqual(probe.label, "scale \(scale); reading \(largeText ? "largest" : "normal"); controls \(largeText ? "accessibility5" : ["large", "xLarge", "xxLarge"][scale])")
        probe.tap()
        XCTAssertTrue(probe.waitForNonExistence(timeout: 5))
        let submit = app.buttons.matching(NSPredicate(
            format: "label == %@ AND identifier != %@", recovery ? "Sign in" : "Send link", "account.signIn"
        )).element
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        XCTAssertFalse(submit.isEnabled, "An empty credential field must not allow submission")
        if recovery { assertRecoveryReadingAndTyping(largeText: largeText) }
        else { assertEmailReadingAndTyping(largeText: largeText) }
        captureAppScreen("\(name) \(largeText ? "largest" : "normal") scale \(scale)")
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(cancel.isHittable)
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["account.continueAnonymous"].waitForExistence(timeout: 5))
        app.terminate()
    }

    private func assertEmailReadingAndTyping(largeText: Bool) {
        let heading = app.staticTexts["account.emailSignIn.heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        if largeText { XCTAssertGreaterThanOrEqual(heading.frame.height, 30.5) }
        captureAppScreen("Email sign-in reading before keyboard")
        let field = app.textFields["account.emailSignIn.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        for _ in 0..<16 {
            if field.isHittable { break }
            app.scrollViews["account.emailSignIn.scroll"].swipeUp(velocity: .slow)
        }
        XCTAssertTrue(field.isHittable)
        field.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        field.typeText("layout@example.invalid")
        let entered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "layout@example.invalid"), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [entered], timeout: 5), .completed)
        XCTAssertEqual(field.value as? String, "layout@example.invalid")
        let send = app.buttons["Send link"]
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(send.isEnabled)
        for action in [cancel, send] {
            XCTAssertTrue(action.isHittable)
            XCTAssertGreaterThanOrEqual(action.frame.width, 44 - 0.001)
            XCTAssertGreaterThanOrEqual(action.frame.height, 44 - 0.001)
            XCTAssertLessThanOrEqual(action.frame.maxY, keyboard.frame.minY)
        }
        XCTAssertFalse(cancel.frame.intersects(send.frame))
        let useKey = app.buttons["Use a recovery key"]
        if useKey.exists {
            XCTAssertTrue(useKey.isHittable)
            XCTAssertGreaterThanOrEqual(useKey.frame.height, 44 - 0.001)
            XCTAssertLessThanOrEqual(useKey.frame.maxY, keyboard.frame.minY)
            XCTAssertFalse(send.frame.intersects(useKey.frame))
            XCTAssertFalse(cancel.frame.intersects(useKey.frame))
        }
        let frames = XCTAttachment(string: "field=\(field.frame); cancel=\(cancel.frame); send=\(send.frame); keyboard=\(keyboard.frame)")
        frames.name = "Email sign-in typing frames"; frames.lifetime = .keepAlways; add(frames)
        // The caller cancels. This helper never taps Send or sends a newline.
    }

    private func assertRecoveryReadingAndTyping(largeText: Bool) {
        let heading = app.staticTexts["account.restore.heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        if largeText {
            // The fixed 17pt heading previously stayed about 20pt tall.
            XCTAssertGreaterThanOrEqual(heading.frame.height, 30.5)
        }
        captureAppScreen("Recovery sign-in reading before keyboard")
        let field = app.textFields["account.restore.key"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let scroll = app.scrollViews["account.restore.scroll"]
        for _ in 0..<16 {
            if field.isHittable { break }
            XCTAssertTrue(scroll.exists)
            scroll.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(field.isHittable)
        XCTAssertGreaterThanOrEqual(field.frame.width, 280)
        if largeText { XCTAssertGreaterThanOrEqual(field.frame.height, 40) }
        field.tap()
        let key = "M1-000G-40R4-0M30-E209-185G-R38E-1WET-S870"
        field.typeText(key)
        XCTAssertEqual(field.value as? String, key)
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        let submit = app.buttons["account.restore.submit"]
        let cancel = app.buttons["account.restore.cancel"]
        XCTAssertTrue(submit.isEnabled)
        for action in [cancel, submit] {
            XCTAssertTrue(action.isHittable)
            XCTAssertGreaterThanOrEqual(action.frame.width, 44 - 0.001)
            XCTAssertGreaterThanOrEqual(action.frame.height, 44 - 0.001)
            XCTAssertLessThanOrEqual(action.frame.maxY, keyboard.frame.minY)
        }
        XCTAssertFalse(cancel.frame.intersects(submit.frame))
        let frames = XCTAttachment(string: "heading=\(heading.frame); field=\(field.frame); cancel=\(cancel.frame); submit=\(submit.frame); keyboard=\(keyboard.frame)")
        frames.name = "Recovery sign-in typing frames"; frames.lifetime = .keepAlways; add(frames)
        // The caller taps Cancel. No return/newline or submit action is sent.
    }

    func testLiveInvestigationInheritsInterfaceSize() {
        assertLiveOrPrepPresentation("liveInvestigation", largeText: false, scale: 2)
    }

    func testLiveCatchUpInheritsInterfaceSize() {
        assertLiveOrPrepPresentation("liveCatchUp", largeText: false, scale: 2)
    }

    func testEventPreparationInheritsInterfaceSize() {
        assertLiveOrPrepPresentation("eventPrep", largeText: false, scale: 2)
    }

    func testLiveInvestigationAtNormalTextAcrossInterfaceScales() {
        executionTimeAllowance = 180
        for scale in 0...2 { assertLiveOrPrepPresentation("liveInvestigation", largeText: false, scale: scale) }
    }

    func testLiveInvestigationAtLargestTextAcrossInterfaceScales() {
        executionTimeAllowance = 180
        for scale in 0...2 { assertLiveOrPrepPresentation("liveInvestigation", largeText: true, scale: scale) }
    }

    func testLiveCatchUpAtNormalTextAcrossInterfaceScales() {
        executionTimeAllowance = 180
        for scale in 0...2 { assertLiveOrPrepPresentation("liveCatchUp", largeText: false, scale: scale) }
    }

    func testLiveCatchUpAtLargestTextAcrossInterfaceScales() {
        executionTimeAllowance = 180
        for scale in 0...2 { assertLiveOrPrepPresentation("liveCatchUp", largeText: true, scale: scale) }
    }

    func testEventPreparationAtNormalTextAcrossInterfaceScales() {
        executionTimeAllowance = 180
        for scale in 0...2 { assertLiveOrPrepPresentation("eventPrep", largeText: false, scale: scale) }
    }

    func testEventPreparationAtLargestTextAcrossInterfaceScales() {
        executionTimeAllowance = 180
        for scale in 0...2 { assertLiveOrPrepPresentation("eventPrep", largeText: true, scale: scale) }
    }

    private func assertLiveOrPrepPresentation(_ name: String, largeText: Bool, scale: Int) {
        let preparing = name == "eventPrep"
        let scenario = preparing ? "prepPresentation" : name + "Presentation"
        launch(scenario, largeText: largeText, screenshotScene: preparing ? "home" : "recording-insights", interfaceScale: scale)
        let event = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Halcyon Labs: pricing follow-up")).firstMatch
        if preparing {
            XCTAssertTrue(event.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(event.isHittable)
            event.tap()
        }
        let scope = app.buttons["ui-test.readingScope.\(name)"]
        XCTAssertTrue(scope.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(scope.label, "scale \(scale); reading \(largeText ? "largest" : "normal"); controls \(largeText ? "accessibility5" : ["large", "xLarge", "xxLarge"][scale])")
        scope.tap()
        XCTAssertTrue(scope.waitForNonExistence(timeout: 5))
        captureAppScreen("\(name) \(largeText ? "largest" : "normal") scale \(scale)")
        if preparing { assertEventPreparationLayout(largeText: largeText, scale: scale) }
        let close = app.buttons[name == "liveCatchUp" ? "close" : "Done"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(close.isHittable)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        if preparing { XCTAssertTrue(event.waitForExistence(timeout: 5)) }
        else { XCTAssertTrue(app.buttons["meeting.section.transcript"].waitForExistence(timeout: 5)) }
        app.terminate()
    }

    private func assertEventPreparationLayout(largeText: Bool, scale: Int) {
        let title = app.staticTexts["prep.title"]
        let bar = app.navigationBars["prep notes"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        let initial = XCTAttachment(string: "Toolbar: \(bar.frame)\nTitle: \(title.frame)")
        initial.name = "Preparation initial bounds"
        initial.lifetime = .keepAlways
        add(initial)
        XCTAssertGreaterThanOrEqual(title.frame.minY, bar.frame.maxY - 0.5, "Preparation title must start below its toolbar")
        guard title.frame.minY >= bar.frame.maxY - 0.5 else { return }
        let scroll = app.scrollViews["prep.content"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        let targets = [title, app.staticTexts["prep.time"], app.staticTexts["prep.guidance"],
                       app.textViews["prep.notes"], app.buttons["prep.join"], app.buttons["prep.start"]]
        var evidence = ""
        for target in targets {
            XCTAssertTrue(target.waitForExistence(timeout: 5))
            for _ in 0..<16 {
                let visible = scroll.frame.intersection(app.frame).intersection(CGRect(x: 0, y: bar.frame.maxY, width: app.frame.width, height: app.frame.maxY - bar.frame.maxY))
                let frame = target.frame
                if target.isHittable && frame.minY >= visible.minY - 0.5 && frame.maxY <= visible.maxY + 0.5 { break }
                let movingDown = frame.minY < visible.minY
                // Standard native swipes expand the medium detent before scrolling its content.
                if movingDown { scroll.swipeDown(velocity: .slow) }
                else { scroll.swipeUp(velocity: .slow) }
            }
            let visible = scroll.frame.intersection(app.frame).intersection(CGRect(x: 0, y: bar.frame.maxY, width: app.frame.width, height: app.frame.maxY - bar.frame.maxY))
            XCTAssertTrue(target.isHittable)
            XCTAssertGreaterThanOrEqual(target.frame.minY, visible.minY - 0.5)
            XCTAssertLessThanOrEqual(target.frame.maxY, visible.maxY + 0.5)
            XCTAssertGreaterThanOrEqual(target.frame.minX, visible.minX - 0.5)
            XCTAssertLessThanOrEqual(target.frame.maxX, visible.maxX + 0.5)
            if target.identifier == "prep.guidance" {
                captureAppScreen("Preparation guidance \(largeText ? "largest" : "normal") scale \(scale)")
            }
            evidence += "\(target.identifier): \(target.frame); viewport: \(visible)\n"
        }
        let join = app.buttons["prep.join"]
        let start = app.buttons["prep.start"]
        XCTAssertGreaterThanOrEqual(join.frame.height, 44 - 0.001)
        XCTAssertGreaterThanOrEqual(start.frame.height, 44 - 0.001)
        XCTAssertLessThanOrEqual(join.frame.maxY, start.frame.minY)
        let frames = XCTAttachment(string: evidence)
        frames.name = "Preparation reachable content"
        frames.lifetime = .keepAlways
        add(frames)
        captureAppScreen("Preparation end \(largeText ? "largest" : "normal") scale \(scale)")
    }

    func testHistorySpeakerRenameInheritsInterfaceSize() {
        assertHistoryDetailPresentation(renaming: true, largeText: false, scale: 2)
    }

    func testHistoryMetricHelpInheritsInterfaceSize() {
        assertHistoryDetailPresentation(renaming: false, largeText: false, scale: 2)
    }

    func testHistorySpeakerRenameAtNormalTextAcrossInterfaceScales() {
        executionTimeAllowance = 180
        for scale in 0...2 { assertHistoryDetailPresentation(renaming: true, largeText: false, scale: scale) }
    }

    func testHistorySpeakerRenameAtLargestTextAcrossInterfaceScales() {
        executionTimeAllowance = 180
        for scale in 0...2 { assertHistoryDetailPresentation(renaming: true, largeText: true, scale: scale) }
    }

    func testHistoryMetricHelpAtNormalTextAcrossInterfaceScales() {
        executionTimeAllowance = 180
        for scale in 0...2 { assertHistoryDetailPresentation(renaming: false, largeText: false, scale: scale) }
    }

    func testHistoryMetricHelpAtLargestTextAcrossInterfaceScales() {
        executionTimeAllowance = 180
        for scale in 0...2 { assertHistoryDetailPresentation(renaming: false, largeText: true, scale: scale) }
    }

    private func assertHistoryDetailPresentation(renaming: Bool, largeText: Bool, scale: Int) {
        launch("readingMatrix", largeText: largeText,
               screenshotScene: renaming ? "meeting" : "meeting-coaching", interfaceScale: scale)
        let entry: XCUIElement
        if renaming {
            let transcript = app.buttons["meeting.section.transcript"]
            XCTAssertTrue(transcript.waitForExistence(timeout: 10))
            transcript.tap()
            entry = app.buttons["Marcus Lee"].firstMatch
        } else {
            entry = app.buttons["About fillers"].firstMatch
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 10), app.debugDescription)
        entry.tap()
        let scope = app.buttons["ui-test.readingScope.\(renaming ? "speakerRename" : "savedMetricHelp")"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(scope.label, "scale \(scale); reading \(largeText ? "largest" : "normal"); controls \(largeText ? "accessibility5" : ["large", "xLarge", "xxLarge"][scale])")
        scope.tap()
        XCTAssertTrue(scope.waitForNonExistence(timeout: 5))
        captureAppScreen("History \(renaming ? "speaker rename" : "metric help") \(largeText ? "largest" : "normal") scale \(scale)")
        let close = app.buttons[renaming ? "cancel" : "Close metric help"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(close.isHittable)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        app.terminate()
    }

    func testSpeakerGuidanceRetainsIdentityAndAttendeeActions() {
        launch("speakerGuidance")
        let guest = app.buttons["Fixture guest"]
        XCTAssertTrue(guest.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["(you + 1 remote)"].exists)
        guest.tap()
        XCTAssertTrue(app.staticTexts["Action: rename:0"].waitForExistence(timeout: 2))
        let attendee = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ada@example.invalid")).firstMatch
        for _ in 0..<3 where !attendee.isHittable { app.swipeUp() }
        XCTAssertTrue(attendee.isHittable, app.debugDescription)
        XCTAssertTrue(app.staticTexts["diarization sometimes splits one person across IDs. mark each one."].exists)
        attendee.tap()
        XCTAssertTrue(app.staticTexts["Action: picked:ada@example.invalid"].waitForExistence(timeout: 2))
        captureAppScreen("Speaker guidance and attendee selection")
    }

    func testQuestionAndDocsGuidanceStatesRemainVisible() {
        for (scenario, expected) in [
            ("manual", "tap a topic to look it up in your docs"),
            ("error", "Synthetic lookup failure"),
            ("questions", "use update above to generate")
        ] {
            launch("docsGuidance-" + scenario)
            let text = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", expected)).firstMatch
            XCTAssertTrue(text.waitForExistence(timeout: 5), app.debugDescription)
            captureAppScreen("Readable guidance: " + scenario)
        }
    }

    func testDocsTopicRetryAndAnsweredContentRemainAvailable() {
        launch("docsGuidance-noMatch")
        let row = app.buttons["docs.topic.fixture topic"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["no docs match this topic"].exists)
        row.tap()
        XCTAssertTrue(app.staticTexts["lookups=1"].waitForExistence(timeout: 2))
        captureAppScreen("Docs no-match retry dispatch")

        launch("docsGuidance-answered")
        let snippet = app.staticTexts["A synthetic grounded citation snippet."]
        XCTAssertTrue(snippet.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["Copy answer"].exists)
        captureAppScreen("Docs answer with citation snippet")
    }

    func testDocsAnswersCollapseAndReopenWithAndWithoutCitations() {
        for scenario in ["docsTargets", "docsGuidance-answered"] {
            launch(scenario)
            let row = app.buttons["docs.topic.fixture topic"]
            XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(app.buttons["Copy answer"].exists)
            row.tap()
            XCTAssertTrue(app.images["chevron.down"].waitForExistence(timeout: 2), app.debugDescription)
            XCTAssertFalse(app.buttons["Copy answer"].exists)
            XCTAssertFalse(app.textViews.firstMatch.exists)
            if scenario == "docsGuidance-answered" {
                XCTAssertFalse(app.staticTexts["A synthetic grounded citation snippet."].exists)
            }
            row.tap()
            XCTAssertTrue(app.images["chevron.up"].waitForExistence(timeout: 2))
            XCTAssertTrue(app.buttons["Copy answer"].exists)
            XCTAssertTrue(app.textViews.firstMatch.exists)
            if scenario == "docsGuidance-answered" {
                XCTAssertTrue(app.staticTexts["A synthetic grounded citation snippet."].exists)
            }
            captureAppScreen("Docs reopened: " + scenario)
        }
    }

    func testDocsAnswerKeepsNativeTextSelection() {
        launch("docsTargets")
        let answer = app.textViews.matching(NSPredicate(format: "value == %@",
            "A synthetic answer with a real copy action.")).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 5), app.debugDescription)
        answer.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 50, dy: 8)).press(forDuration: 1)
        let copy = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Copy'")).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        captureAppScreen("Docs answer native selection menu")
    }

    func testDocsAnswerCopyRespondsInItsExpandedTarget() {
        launch("docsTargets")
        let copy = app.buttons["Copy answer"]
        XCTAssertTrue(copy.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertGreaterThanOrEqual(copy.frame.width, 44)
        XCTAssertGreaterThanOrEqual(copy.frame.height, 44)
        copy.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: 2)).tap()
        XCTAssertTrue(app.buttons["Answer copied"].waitForExistence(timeout: 2))
        captureAppScreen("Shared docs Copy feedback")
    }

    func testQuestionCopyRespondsInItsExpandedTarget() {
        launch(screenshotScene: "recording-questions")
        let copy = app.buttons["Copy question"].firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertGreaterThanOrEqual(copy.frame.width, 44)
        XCTAssertGreaterThanOrEqual(copy.frame.height, 44)
        copy.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: 2)).tap()
        XCTAssertTrue(app.buttons["Question copied"].waitForExistence(timeout: 2))
        captureAppScreen("Shared question Copy feedback")
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
        assertOnboardingChoicesRemainUsable()
    }

    func testOnboardingChoicesAtNormalTextAcrossInterfaceScales() {
        assertOnboardingChoicesAcrossInterfaceScales(largeText: false)
    }

    func testOnboardingChoicesAtLargestTextAcrossInterfaceScales() {
        assertOnboardingChoicesAcrossInterfaceScales(largeText: true)
    }

    private func assertOnboardingChoicesAcrossInterfaceScales(largeText: Bool) {
        executionTimeAllowance = 180
        for scale in 0...2 {
            if scale > 0 { resetAccountMatrixFixture() }
            app?.terminate()
            launch("onboardingReadingMatrix", largeText: largeText, interfaceScale: scale)
            let probe = app.staticTexts["ui-test.readingMetrics"]
            XCTAssertTrue(probe.waitForExistence(timeout: 5))
            let category = largeText ? "largest" : "normal"
            XCTAssertEqual(probe.label, "Reading scale \(scale), text \(category)")
            captureAppScreen("Onboarding \(category) text, interface scale \(scale)")
            assertOnboardingChoicesRemainUsable()
        }
    }

    private func assertOnboardingChoicesRemainUsable() {
        let signIn = app.buttons["account.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        for _ in 0..<4 where !signIn.isHittable { app.swipeUp() }
        XCTAssertTrue(signIn.isHittable, app.debugDescription)
        XCTAssertGreaterThanOrEqual(signIn.frame.height, 44)
        signIn.tap()
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.tap()
        let continueButton = app.buttons["account.continueAnonymous"]
        for _ in 0..<3 where !continueButton.isHittable { app.swipeUp() }
        XCTAssertTrue(continueButton.isHittable, app.debugDescription)
        XCTAssertGreaterThanOrEqual(continueButton.frame.height, 44)
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "First launch choices after sign-in cancellation"
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

    func testSettingsInheritsResolvedLargestControlSize() {
        launch("first", largeText: true, interfaceScale: 2)
        let root = app.staticTexts["ui-test.readingMetrics"]
        XCTAssertTrue(root.waitForExistence(timeout: 5))
        XCTAssertEqual(root.label, "Reading scale 2, text largest")
        app.buttons["Settings"].tap()
        let scope = app.buttons["ui-test.readingScope.settings"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        captureAppScreen("Settings inherited control-size probe")
        XCTAssertEqual(scope.label, "scale 2; reading largest; controls accessibility5")
    }

    func testHistoryFilterInheritsInterfaceSize() {
        openHistoryFilters(largeText: false, scale: 2)
        let scope = app.buttons["ui-test.readingScope.historyFilters"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        captureAppScreen("History filters normal Large category probe")
        XCTAssertEqual(scope.label, "scale 2; reading normal; controls xxLarge")
    }

    func testDebugLogInheritsInterfaceSize() {
        openDebugLog(largeText: false, scale: 2)
        let scope = app.buttons["ui-test.readingScope.debugLog"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        captureAppScreen("Debug Log normal Large category probe")
        XCTAssertEqual(scope.label, "scale 2; reading normal; controls xxLarge")
    }

    func testHistoryFiltersAtNormalTextAcrossInterfaceScales() {
        assertAuxiliarySheetAcrossInterfaceScales(debugLog: false, largeText: false)
    }

    func testHistoryFiltersAtLargestTextAcrossInterfaceScales() {
        assertAuxiliarySheetAcrossInterfaceScales(debugLog: false, largeText: true)
    }

    func testDebugLogAtNormalTextAcrossInterfaceScales() {
        assertAuxiliarySheetAcrossInterfaceScales(debugLog: true, largeText: false)
    }

    func testDebugLogAtLargestTextAcrossInterfaceScales() {
        assertAuxiliarySheetAcrossInterfaceScales(debugLog: true, largeText: true)
    }

    private func assertAuxiliarySheetAcrossInterfaceScales(debugLog: Bool, largeText: Bool) {
        for scale in 0...2 {
            // History enrollment persists in the test-ID suite between launches.
            if !debugLog && scale > 0 { resetAccountMatrixFixture() }
            app?.terminate()
            if debugLog { openDebugLog(largeText: largeText, scale: scale) }
            else { openHistoryFilters(largeText: largeText, scale: scale) }
            executionTimeAllowance = 360
            let name = debugLog ? "debugLog" : "historyFilters"
            let category = largeText ? "largest" : "normal"
            let scope = app.buttons["ui-test.readingScope.\(name)"]
            XCTAssertTrue(scope.waitForExistence(timeout: 5))
            XCTAssertEqual(scope.label, "scale \(scale); reading \(category); controls \(largeText ? "accessibility5" : ["large", "xLarge", "xxLarge"][scale])")
            scope.tap()
            XCTAssertTrue(scope.waitForNonExistence(timeout: 5))
            captureAppScreen("\(name) \(category) text, scale \(scale)")
            if debugLog { assertDebugLogHeaderFits() }
            let close = debugLog ? app.buttons["close"] : app.navigationBars["Filter"].buttons["Done"]
            XCTAssertTrue(close.isHittable)
            close.tap()
            XCTAssertTrue(close.waitForNonExistence(timeout: 5))
            XCTAssertTrue(app.navigationBars[debugLog ? "About" : "History"].exists)
            if !debugLog {
                XCTAssertTrue(app.buttons["Filter meetings by person or date"].isHittable)
            }
        }
    }

    func testDebugLogOptionsKeepFilterAndDisplayActions() {
        openDebugLog(largeText: false, scale: 2)
        let scope = app.buttons["ui-test.readingScope.debugLog"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        scope.tap()
        XCTAssertTrue(scope.waitForNonExistence(timeout: 5))
        assertDebugLogHeaderFits()
        let options = app.buttons["debugLog.options"]
        func expectOptionsValue(_ value: String) {
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: options)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        }
        expectOptionsValue("all categories, routine hidden, pretty")
        options.tap()
        for name in ["audio", "deepgram", "app", "show routine", "raw", "copy", "clear"] {
            XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 5))
        }
        app.buttons["audio"].tap()
        expectOptionsValue("audio, routine hidden, pretty")
        options.tap()
        captureAppScreen("Debug Log options with audio selected")
        app.buttons["audio"].tap()
        expectOptionsValue("all categories, routine hidden, pretty")
        options.tap()
        app.buttons["show routine"].tap()
        expectOptionsValue("all categories, routine shown, pretty")
        options.tap()
        app.buttons["hide routine"].tap()
        expectOptionsValue("all categories, routine hidden, pretty")
        options.tap()
        app.buttons["raw"].tap()
        expectOptionsValue("all categories, routine hidden, raw")
        options.tap()
        app.buttons["pretty"].tap()
        expectOptionsValue("all categories, routine hidden, pretty")
        captureAppScreen("Debug Log after options round trip")
        app.buttons["close"].tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 5))
    }

    func testDebugLogCloseRespondsInAddedPadding() {
        openDebugLog(largeText: false, scale: 0)
        let scope = app.buttons["ui-test.readingScope.debugLog"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        scope.tap()
        XCTAssertTrue(scope.waitForNonExistence(timeout: 5))
        let close = app.buttons["close"]
        XCTAssertGreaterThanOrEqual(close.frame.height, 44 - 0.001)
        close.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: 1)).tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["About"].exists)
    }

    func testHistoryFolderSelectorAtLargestTextAcrossInterfaceScales() {
        assertHistoryFolderSelectorAcrossInterfaceScales(largeText: true)
    }

    func testHistoryFolderSelectorAtNormalTextAcrossInterfaceScales() {
        assertHistoryFolderSelectorAcrossInterfaceScales(largeText: false)
    }

    private func assertHistoryFolderSelectorAcrossInterfaceScales(largeText: Bool) {
        for scale in 0...2 {
            if scale > 0 { resetAccountMatrixFixture(); app.terminate() }
            openHistoryFilters(largeText: largeText, scale: scale)
            let scope = app.buttons["ui-test.readingScope.historyFilters"]
            XCTAssertTrue(scope.waitForExistence(timeout: 5))
            XCTAssertEqual(scope.label, "scale \(scale); reading \(largeText ? "largest" : "normal"); controls \(largeText ? "accessibility5" : ["large", "xLarge", "xxLarge"][scale])")
            scope.tap()
            XCTAssertTrue(scope.waitForNonExistence(timeout: 5))
            app.navigationBars["Filter"].buttons["Done"].tap()
            let picker = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Filter meetings by folder")).firstMatch
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            let manage = app.buttons["Manage folders"]
            captureAppScreen("History folder selector \(largeText ? "largest" : "normal") scale \(scale)")
            let frames = XCTAttachment(string: "Picker: \(picker.frame)\nManage: \(manage.frame)")
            frames.name = "History folder control frames"; frames.lifetime = .keepAlways; add(frames)
            XCTAssertGreaterThan(picker.frame.width, picker.frame.height * 2)
            XCTAssertFalse(picker.frame.intersects(manage.frame))
            XCTAssertTrue(picker.isHittable)
            XCTAssertTrue(manage.isHittable)
            picker.tap()
            app.buttons["Unfiled"].tap()
            XCTAssertTrue(picker.staticTexts["Unfiled"].waitForExistence(timeout: 5))
            picker.tap()
            app.buttons["All meetings"].tap()
            XCTAssertTrue(picker.staticTexts["All meetings"].waitForExistence(timeout: 5))
        }
    }

    func testHistoryDateRangeIsReachableAtLargestText() {
        openHistoryFilters(largeText: true, scale: 2)
        let scope = app.buttons["ui-test.readingScope.historyFilters"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        scope.tap()
        XCTAssertTrue(scope.waitForNonExistence(timeout: 5))
        let range = app.buttons["Apply range"]
        var swipes = 0
        for _ in 0..<16 {
            if range.isHittable && range.frame.maxY <= app.frame.maxY - 50 { break }
            app.collectionViews.firstMatch.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(range.isHittable)
        XCTAssertLessThanOrEqual(range.frame.maxY, app.frame.maxY - 50)
        XCTAssertGreaterThan(swipes, 0)
        captureAppScreen("History Date range at largest text")
        range.tap()
        app.navigationBars["Filter"].buttons["Done"].tap()
        let search = app.searchFields["Search meetings..."]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        captureAppScreen("History query after Date range")
        XCTAssertTrue((search.value as? String ?? "").contains("after:"), "Actual search value: \(String(describing: search.value))")
        XCTAssertTrue((search.value as? String ?? "").contains("before:"))
        app.buttons["Filter meetings by person or date"].tap()
        let newScope = app.buttons["ui-test.readingScope.historyFilters"]
        XCTAssertTrue(newScope.waitForExistence(timeout: 5))
        newScope.tap()
        XCTAssertTrue(newScope.waitForNonExistence(timeout: 5))
        let clear = app.buttons["Clear filters"]
        for _ in 0..<16 {
            if clear.isHittable && clear.frame.maxY <= app.frame.maxY - 50 { break }
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(clear.isHittable)
        XCTAssertLessThanOrEqual(clear.frame.maxY, app.frame.maxY - 50)
        clear.tap()
        app.navigationBars["Filter"].buttons["Done"].tap()
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard search.exists, let value = search.value as? String else { return false }
            return !value.contains("after:") && !value.contains("before:")
        }, object: search)
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 5), .completed)
    }

    private func assertDebugLogHeaderFits() {
        let title = app.staticTexts["debugLog.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        // The short title must have a wide text frame, not a column of broken words.
        XCTAssertGreaterThan(title.frame.width, title.frame.height * 2)
        let options = app.buttons["debugLog.options"]
        let close = app.buttons["close"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        for button in [options, close] {
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.width, 44 - 0.001)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44 - 0.001)
            XCTAssertLessThanOrEqual(title.frame.maxY, button.frame.minY)
        }
        XCTAssertFalse(options.frame.intersects(close.frame))
    }

    private func openHistoryFilters(largeText: Bool, scale: Int) {
        executionTimeAllowance = 360
        launch("first", largeText: largeText, interfaceScale: scale)
        let guest = app.buttons["account.continueAnonymous"]
        XCTAssertTrue(guest.waitForExistence(timeout: 5))
        for _ in 0..<8 where !guest.isHittable { app.scrollViews.firstMatch.swipeUp() }
        guest.tap()
        XCTAssertTrue(guest.waitForNonExistence(timeout: 5))
        app.buttons["History"].firstMatch.tap()
        let filter = app.buttons["Filter meetings by person or date"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.tap()
    }

    private func openDebugLog(largeText: Bool, scale: Int) {
        executionTimeAllowance = 360
        launch("first", largeText: largeText, interfaceScale: scale)
        app.buttons["Settings"].tap()
        let settingsScope = app.buttons["ui-test.readingScope.settings"]
        XCTAssertTrue(settingsScope.waitForExistence(timeout: 5))
        settingsScope.tap()
        XCTAssertTrue(settingsScope.waitForNonExistence(timeout: 5))
        let about = app.staticTexts["settings.title.about"]
        let search = app.searchFields["Search settings"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        for _ in 0..<14 {
            if about.isHittable && about.frame.maxY < search.frame.minY - 24 { break }
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(about.isHittable)
        XCTAssertLessThan(about.frame.maxY, search.frame.minY - 24)
        about.tap()
        let version = app.staticTexts["settings.about.version"]
        XCTAssertTrue(version.waitForExistence(timeout: 5))
        version.tap(withNumberOfTaps: 5, numberOfTouches: 1)
    }

    func testPrivacyConsentInheritsResolvedInterfaceSize() {
        openPrivacyConsent(largeText: false, scale: 2)
        let scope = app.buttons["ui-test.readingScope.consent.sheet"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        captureAppScreen("Privacy consent normal Large category probe")
        XCTAssertEqual(scope.label, "scale 2; reading normal; controls xxLarge")
        scope.tap()
        app.buttons["consent.decline"].tap()
        XCTAssertTrue(app.navigationBars["Privacy"].waitForExistence(timeout: 5))
    }

    func testPrivacyConsentAtNormalTextAcrossInterfaceScales() {
        assertPrivacyConsentAcrossInterfaceScales(largeText: false)
    }

    func testPrivacyConsentAtLargestTextAcrossInterfaceScales() {
        assertPrivacyConsentAcrossInterfaceScales(largeText: true)
    }

    private func assertPrivacyConsentAcrossInterfaceScales(largeText: Bool) {
        for scale in 0...2 {
            app?.terminate()
            openPrivacyConsent(largeText: largeText, scale: scale)
            executionTimeAllowance = 360
            let category = largeText ? "largest" : "normal"
            let scope = app.buttons["ui-test.readingScope.consent.sheet"]
            XCTAssertTrue(scope.waitForExistence(timeout: 5))
            XCTAssertEqual(scope.label, "scale \(scale); reading \(category); controls \(largeText ? "accessibility5" : ["large", "xLarge", "xxLarge"][scale])")
            scope.tap()
            XCTAssertTrue(scope.waitForNonExistence(timeout: 5))
            assertConsentSheetActions("Privacy consent \(category) text, scale \(scale)", requiresScroll: largeText, returnButton: "Allow…")
            XCTAssertTrue(app.navigationBars["Privacy"].exists)
            XCTAssertTrue(app.buttons["Allow…"].isHittable)
            XCTAssertFalse(app.buttons["Withdraw permission"].exists)
        }
    }

    private func openPrivacyConsent(largeText: Bool, scale: Int) {
        executionTimeAllowance = 360
        launch("privacyConsent", largeText: largeText, interfaceScale: scale)
        app.buttons["Settings"].tap()
        let settingsScope = app.buttons["ui-test.readingScope.settings"]
        XCTAssertTrue(settingsScope.waitForExistence(timeout: 5))
        settingsScope.tap()
        XCTAssertTrue(settingsScope.waitForNonExistence(timeout: 5))
        let privacy = app.staticTexts["settings.title.privacy"]
        let search = app.searchFields["Search settings"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        // Native search chrome extends above its text-field frame. Hittable alone
        // can still place the row's tap under that chrome at normal text size.
        for _ in 0..<12 where !privacy.isHittable || privacy.frame.maxY >= search.frame.minY - 24 {
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(privacy.isHittable, app.debugDescription)
        XCTAssertLessThan(privacy.frame.maxY, search.frame.minY - 24)
        captureAppScreen("Privacy destination clear of search, scale \(scale), largest \(largeText)")
        privacy.tap()
        XCTAssertTrue(app.navigationBars["Privacy"].waitForExistence(timeout: 5))
        let showConsent = app.buttons["Allow…"]
        for _ in 0..<12 where !showConsent.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(showConsent.isHittable, app.debugDescription)
        showConsent.tap()
    }

    func testConsentDisclosureGrowsAtLargestText() {
        launch("consentSheet", interfaceScale: 0)
        let normal = app.staticTexts["consent.heading"]
        XCTAssertTrue(normal.waitForExistence(timeout: 5))
        let normalHeight = normal.frame.height
        let normalBodyHeight = app.staticTexts["consent.provider.Deepgram"].frame.height
        app.terminate()
        launch("consentSheet", largeText: true, interfaceScale: 0)
        let large = app.staticTexts["consent.heading"]
        XCTAssertTrue(large.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(large.frame.height, normalHeight * 1.5)
        XCTAssertGreaterThan(app.staticTexts["consent.provider.Deepgram"].frame.height, normalBodyHeight * 1.5)
    }

    func testFirstConsentResetsPriorFixtureDecline() {
        launch("consentSheet", interfaceScale: 0)
        XCTAssertTrue(app.buttons["consent.decline"].waitForExistence(timeout: 5))
        app.buttons["consent.decline"].tap()
        app.terminate()
        launch("setupUpgrade", interfaceScale: 0)
        let first = app.buttons["ui-test.readingScope.consent.first"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        app.buttons["ui-test.hideStatus"].tap()
        XCTAssertTrue(app.staticTexts["ui-test.ready"].waitForNonExistence(timeout: 5))
        let decline = app.buttons["consent.decline"]
        XCTAssertTrue(decline.isHittable)
        XCTAssertTrue(decline.label.hasPrefix("not now:"))
        decline.tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
    }

    func testConsentSheetInheritsInterfaceSize() {
        launch("consentSheet", interfaceScale: 2)
        let scope = app.buttons["ui-test.readingScope.consent.sheet"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        XCTAssertEqual(scope.label, "scale 2; reading normal; controls xxLarge")
    }

    func testConsentSheetActionsMeetMinimumTargets() {
        launch("consentSheet", largeText: true, interfaceScale: 2)
        let scope = app.buttons["ui-test.readingScope.consent.sheet"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        scope.tap()
        XCTAssertTrue(scope.waitForNonExistence(timeout: 5))
        assertConsentSheetActions()
    }

    func testFirstConsentAtNormalTextAcrossInterfaceScales() {
        assertFirstConsentAcrossInterfaceScales(largeText: false)
    }

    func testFirstConsentAtLargestTextAcrossInterfaceScales() {
        assertFirstConsentAcrossInterfaceScales(largeText: true)
    }

    private func assertFirstConsentAcrossInterfaceScales(largeText: Bool) {
        executionTimeAllowance = 240
        for scale in 0...2 {
            app?.terminate()
            launch("setupUpgrade", largeText: largeText, interfaceScale: scale)
            let category = largeText ? "largest" : "normal"
            let scope = app.buttons["ui-test.readingScope.consent.first"]
            XCTAssertTrue(scope.waitForExistence(timeout: 5))
            XCTAssertEqual(scope.label, "scale \(scale); reading \(category); controls \(largeText ? "accessibility5" : ["large", "xLarge", "xxLarge"][scale])")
            scope.tap()
            app.buttons["ui-test.hideStatus"].tap()
            XCTAssertTrue(app.staticTexts["ui-test.ready"].waitForNonExistence(timeout: 5))
            XCTAssertTrue(app.buttons["consent.decline"].label.hasPrefix("not now:"))
            assertConsentSheetActions("First consent \(category) text, scale \(scale)", requiresScroll: largeText)
        }
    }

    func testConsentSheetAtNormalTextAcrossInterfaceScales() {
        assertConsentSheetAcrossInterfaceScales(largeText: false)
    }

    func testConsentSheetAtLargestTextAcrossInterfaceScales() {
        assertConsentSheetAcrossInterfaceScales(largeText: true)
    }

    private func assertConsentSheetAcrossInterfaceScales(largeText: Bool) {
        executionTimeAllowance = 240
        for scale in 0...2 {
            app?.terminate()
            launch("consentSheet", largeText: largeText, interfaceScale: scale)
            let category = largeText ? "largest" : "normal"
            let scope = app.buttons["ui-test.readingScope.consent.sheet"]
            XCTAssertTrue(scope.waitForExistence(timeout: 5))
            XCTAssertEqual(scope.label, "scale \(scale); reading \(category); controls \(largeText ? "accessibility5" : ["large", "xLarge", "xxLarge"][scale])")
            scope.tap()
            XCTAssertTrue(scope.waitForNonExistence(timeout: 5))
            assertConsentSheetActions("Consent \(category) text, scale \(scale)", requiresScroll: largeText)
        }
    }

    private func assertConsentSheetActions(_ name: String = "Consent sheet action bounds", requiresScroll: Bool = false, returnButton: String = "Settings") {
        let allow = app.buttons["consent.allow"]
        let cancel = app.buttons["consent.decline"]
        XCTAssertTrue(allow.waitForExistence(timeout: 5))
        XCTAssertTrue(cancel.exists)
        captureAppScreen(name)
        let frames = XCTAttachment(string: "Allow: \(allow.frame)\nCancel: \(cancel.frame)")
        frames.name = name + " frames"; frames.lifetime = .keepAlways; add(frames)
        for button in [allow, cancel] {
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44 - 0.001)
            XCTAssertGreaterThanOrEqual(button.frame.width, 44 - 0.001)
        }
        XCTAssertFalse(allow.frame.intersects(cancel.frame))
        let initialAllowY = allow.frame.minY
        let links = app.descendants(matching: .any)["consent.links"].firstMatch
        var scrollCount = 0
        for _ in 0..<16 where !links.isHittable {
            app.scrollViews.firstMatch.swipeUp()
            scrollCount += 1
        }
        let scrolls = XCTAttachment(string: "Disclosure scroll gestures: \(scrollCount)")
        scrolls.name = name + " scroll count"; scrolls.lifetime = .keepAlways; add(scrolls)
        if requiresScroll { XCTAssertGreaterThan(scrollCount, 0, "Largest-text acceptance must exercise actual scrolling") }
        XCTAssertTrue(links.isHittable, "The disclosure's final links must remain reachable")
        XCTAssertTrue(allow.isHittable)
        XCTAssertTrue(cancel.isHittable)
        XCTAssertEqual(allow.frame.minY, initialAllowY, accuracy: 0.5)
        captureAppScreen(name + " disclosure end")
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons[returnButton].waitForExistence(timeout: 5))
    }

    func testSettingsLabelsAtLargestText() {
        launch("first", largeText: true, interfaceScale: 2)
        app.buttons["Settings"].tap()
        let scope = app.buttons["ui-test.readingScope.settings"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        XCTAssertEqual(scope.label, "scale 2; reading largest; controls accessibility5")
        scope.tap()
        XCTAssertTrue(scope.waitForNonExistence(timeout: 5))
        let icon = app.images["settings.icon.general"]
        let title = app.staticTexts["settings.title.general"]
        let subtitle = app.staticTexts["settings.subtitle.general"]
        XCTAssertTrue(icon.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(title.exists)
        XCTAssertTrue(subtitle.exists)
        captureAppScreen("Settings labels at largest text without probe")
        XCTAssertFalse(icon.frame.intersects(title.frame))
        XCTAssertFalse(icon.frame.intersects(subtitle.frame))
        title.tap()
        let slider = app.sliders["Interface scale"]
        for _ in 0..<8 where !slider.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(slider.isHittable)
        let heading = app.staticTexts["settings.scale.title"]
        let value = app.staticTexts["settings.scale.value"]
        XCTAssertTrue(heading.exists)
        XCTAssertTrue(value.exists)
        // Two whole words may use two lines; the old three-line Inter-/face/scale must fail.
        XCTAssertLessThanOrEqual(heading.frame.height, value.frame.height * 2 + 1)
        let captions = (0...2).map { app.staticTexts["settings.scale.caption.\($0)"] }
        for caption in captions {
            for _ in 0..<6 where !caption.isHittable { app.collectionViews.firstMatch.swipeUp() }
            XCTAssertTrue(caption.isHittable)
        }
        // The single-word value uses a larger body font, independently bounding each caption.
        for caption in captions { XCTAssertLessThanOrEqual(caption.frame.height, value.frame.height + 1) }
        captureAppScreen("Interface scale captions at largest text without probe")
    }

    func testHomeAndGeneralSettingsAtNormalTextAcrossInterfaceScales() {
        assertHomeAndGeneralSettingsAcrossInterfaceScales(largeText: false)
    }

    func testHomeAndGeneralSettingsAtLargestTextAcrossInterfaceScales() {
        assertHomeAndGeneralSettingsAcrossInterfaceScales(largeText: true)
    }

    private func assertHomeAndGeneralSettingsAcrossInterfaceScales(largeText: Bool) {
        executionTimeAllowance = 300
        for scale in 0...2 {
            if scale > 0 { resetAccountMatrixFixture() }
            app?.terminate()
            launch("calendar", largeText: largeText, interfaceScale: scale)
            let category = largeText ? "largest" : "normal"
            let probe = app.staticTexts["ui-test.readingMetrics"]
            XCTAssertTrue(probe.waitForExistence(timeout: 5))
            XCTAssertEqual(probe.label, "Reading scale \(scale), text \(category)")
            let account = app.buttons["account.continueAnonymous"]
            XCTAssertTrue(account.waitForExistence(timeout: 5))
            for _ in 0..<8 where !account.isHittable { app.scrollViews.firstMatch.swipeUp() }
            XCTAssertTrue(account.isHittable)
            account.tap()
            XCTAssertTrue(account.waitForNonExistence(timeout: 10))
            XCTAssertTrue(app.buttons["calendar.section.tomorrow"].waitForExistence(timeout: 5))
            assertHomeFooterGeometry()
            let footer = ["setup.reopen", "home.calendar.toggle", "home.feedback"].map { app.buttons[$0].frame }.sorted { $0.minX < $1.minX }
            for pair in zip(footer, footer.dropFirst()) {
                XCTAssertLessThanOrEqual(pair.0.maxX, pair.1.minX + 0.001)
            }
            XCTAssertTrue(app.buttons["home.start"].isHittable)
            captureAppScreen("Home \(category) text, interface scale \(scale)")
            app.buttons["setup.reopen"].tap()
            assertHomeFooterGeometry()
            captureAppScreen("Home setup \(category) text, interface scale \(scale)")
            let settings = app.buttons["Settings"]
            XCTAssertTrue(settings.isHittable)
            settings.tap()
            let general = app.staticTexts["General"].firstMatch
            XCTAssertTrue(general.waitForExistence(timeout: 5))
            for _ in 0..<4 where !general.isHittable { app.collectionViews.firstMatch.swipeDown() }
            XCTAssertTrue(general.isHittable)
            let settingsScope = app.buttons["ui-test.readingScope.settings"]
            XCTAssertTrue(settingsScope.waitForExistence(timeout: 5))
            XCTAssertEqual(settingsScope.label, "scale \(scale); reading \(category); controls \(largeText ? "accessibility5" : ["large", "xLarge", "xxLarge"][scale])")
            settingsScope.tap()
            XCTAssertTrue(settingsScope.waitForNonExistence(timeout: 5))
            captureAppScreen("Settings list \(category) text, interface scale \(scale)")
            general.tap()
            XCTAssertTrue(app.navigationBars["General"].waitForExistence(timeout: 5))
            let slider = app.sliders["Interface scale"]
            for _ in 0..<8 where !slider.isHittable { app.swipeUp() }
            XCTAssertTrue(slider.isHittable)
            XCTAssertEqual(slider.value as? String, ["Compact", "Standard", "Large"][scale])
            captureAppScreen("General Settings \(category) text, interface scale \(scale)")
            app.navigationBars["General"].buttons["Settings"].tap()
            let done = app.buttons["Done"]
            XCTAssertTrue(done.waitForExistence(timeout: 5))
            XCTAssertTrue(done.isHittable)
            done.tap()
            XCTAssertTrue(app.buttons["home.start"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["home.start"].isHittable)
        }
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

    func testSaveRecoveryKeyAtNormalText() {
        assertSaveRecoveryKeyReading(largeText: false)
    }

    func testSaveRecoveryKeyAtLargestText() {
        assertSaveRecoveryKeyReading(largeText: true)
    }

    private func assertSaveRecoveryKeyReading(largeText: Bool) {
        executionTimeAllowance = 180
        launch("setup", largeText: largeText, interfaceScale: 2)
        let hideStatus = app.buttons["ui-test.hideStatus"]
        if hideStatus.exists { hideStatus.tap() }
        let account = app.buttons["account.continueAnonymous"]
        for _ in 0..<8 {
            if account.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(account.isHittable)
        account.tap()
        XCTAssertTrue(account.waitForNonExistence(timeout: 10))
        let home = app.scrollViews.firstMatch
        let step = app.buttons["setup.step.account"]
        for _ in 0..<12 {
            if step.isHittable && step.frame.maxY < home.frame.maxY { break }
            home.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(step.isHittable)
        let open = app.buttons["setup.account.recovery"]
        if !open.exists { step.tap() }
        for _ in 0..<12 {
            if open.isHittable && open.frame.maxY < home.frame.maxY { break }
            home.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(open.isHittable)
        open.tap()
        let probe = app.buttons["ui-test.readingScope.saveRecovery"]
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        XCTAssertTrue(probe.label.contains(largeText ? "reading largest" : "reading normal"))
        XCTAssertTrue(probe.label.contains("scale 2;"))
        probe.tap()
        XCTAssertTrue(probe.waitForNonExistence(timeout: 5))
        let heading = app.staticTexts["account.recoveryKey.heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        captureAppScreen("Save recovery key heading")
        if largeText { XCTAssertGreaterThanOrEqual(heading.frame.height, 30.5) }
        let next = app.buttons["account.recoveryKey.continue"]
        XCTAssertFalse(next.isEnabled)
        XCTAssertTrue(next.isHittable)
        XCTAssertGreaterThanOrEqual(next.frame.height, 44 - 0.001)
        let scroll = app.scrollViews["account.recoveryKey.scroll"]
        let key = app.staticTexts["account.recoveryKey.value"]
        XCTAssertTrue(key.waitForExistence(timeout: 5), "The save sheet must show the selected fixture key")
        XCTAssertGreaterThan(key.frame.height, 24, "Key content must extend beyond its vertical padding")
        var keyPositions = ""
        for _ in 0..<12 {
            keyPositions += "key=\(key.frame); viewport=\(scroll.frame)\n"
            if key.isHittable && key.frame.minY >= scroll.frame.minY && key.frame.maxY <= scroll.frame.maxY { break }
            // Small measured drags can reverse an overshoot. A full upward swipe
            // can skip the whole key at large text, then keep moving away from it.
            let delta = key.frame.minY < scroll.frame.minY
                ? min(150, scroll.frame.minY - key.frame.minY + 8)
                : -min(150, key.frame.maxY - scroll.frame.maxY + 8)
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: delta)))
        }
        let positions = XCTAttachment(string: keyPositions)
        positions.name = "Key viewport scroll positions"; positions.lifetime = .keepAlways; add(positions)
        XCTAssertTrue(key.isHittable)
        XCTAssertGreaterThanOrEqual(key.frame.minY, scroll.frame.minY - 1)
        XCTAssertLessThanOrEqual(key.frame.maxY, scroll.frame.maxY + 1)
        captureAppScreen("Synthetic recovery key fits the reading viewport")
        let copy = app.buttons["account.recoveryKey.copy"]
        let saved = app.switches["account.recoveryKey.saved"]
        for _ in 0..<12 {
            if saved.isHittable && saved.frame.minY >= scroll.frame.minY && saved.frame.maxY <= scroll.frame.maxY { break }
            let delta = saved.frame.minY < scroll.frame.minY
                ? min(120, scroll.frame.minY - saved.frame.minY + 8)
                : -min(120, saved.frame.maxY - scroll.frame.maxY + 8)
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: delta)))
        }
        // Copy was visible with the key. A tall acknowledgment can require a
        // separate scroll position; partial-label hittability is insufficient.
        XCTAssertGreaterThanOrEqual(copy.frame.height, 44 - 0.001)
        XCTAssertTrue(saved.isHittable)
        XCTAssertGreaterThanOrEqual(saved.frame.minY, scroll.frame.minY - 1)
        XCTAssertLessThanOrEqual(saved.frame.maxY, scroll.frame.maxY + 1)
        XCTAssertFalse(next.isEnabled)
        let toggleFrames = XCTAttachment(string: "saved=\(saved.frame); viewport=\(scroll.frame); value=\(String(describing: saved.value))")
        toggleFrames.name = "Acknowledgment before tap"; toggleFrames.lifetime = .keepAlways; add(toggleFrames)
        captureAppScreen("Complete acknowledgment before tap")
        saved.tap()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: next)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        XCTAssertTrue(next.isHittable)
        let frames = XCTAttachment(string: "key=\(key.frame); scroll=\(scroll.frame); copy=\(copy.frame); saved=\(saved.frame); continue=\(next.frame)")
        frames.name = "Save recovery key action frames"; frames.lifetime = .keepAlways; add(frames)
        captureAppScreen("Recovery key acknowledgment enables Continue")
        // This key belongs only to FixtureCredentials. Never tap Copy or use a real account.
        next.tap()
        XCTAssertTrue(heading.waitForNonExistence(timeout: 5))
        XCTAssertTrue(open.exists)
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
