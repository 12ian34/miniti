import Foundation
import SwiftData
import XCTest
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

/// Roadmap P2.1: a person's own templates use the built-in shape, validate against the same
/// limits, survive export/import, and never break a meeting that used them.
@MainActor
final class CustomInsightTemplateTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "CustomInsightTemplateTests"
    /// `AppState` persists template selection through `@AppStorage` on the shared defaults,
    /// which the test host shares with the installed app: snapshot and restore every key.
    private let sharedKeys = ["templateInsightsEnabled", "insightTemplateID", CustomInsightTemplates.storageKey]
    private var sharedSnapshot: [String: Any?] = [:]

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        sharedSnapshot = Dictionary(uniqueKeysWithValues: sharedKeys.map { ($0, UserDefaults.standard.object(forKey: $0)) })
        sharedKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        for (key, value) in sharedSnapshot {
            if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        super.tearDown()
    }

    private func draft(name: String = "Customer QBR", sections: [(String, String)] = [("health", "adoption and sentiment"), ("next steps", "owners and dates")]) -> InsightTemplateDraft {
        InsightTemplateDraft(name: name, summary: "Quarterly review", sections: sections.map { .init(title: $0.0, guidance: $0.1) })
    }

    // MARK: Draft validation and keys

    func testValidDraftBuildsACustomTemplateWithDerivedKeysAndShortName() throws {
        let template = try XCTUnwrap(draft().build(id: InsightTemplate.newCustomID()))
        XCTAssertTrue(template.isCustom)
        XCTAssertFalse(template.isBuiltIn)
        XCTAssertEqual(template.name, "Customer QBR")
        XCTAssertEqual(template.shortName, "Customer QBR")
        XCTAssertEqual(template.sections.map(\.key), ["health", "next_steps"])
        XCTAssertEqual(template.sections.map(\.title), ["health", "next steps"])
        XCTAssertEqual(template.systemImage, InsightTemplate.customSystemImage)
        XCTAssertTrue(template.id.hasPrefix(InsightTemplate.customIDPrefix))
    }

    func testDraftProblemsCoverEveryLimit() {
        XCTAssertEqual(draft(name: "").problems, ["give the template a name"])
        XCTAssertTrue(draft(name: String(repeating: "x", count: 61)).problems.contains { $0.contains("over 60") })
        XCTAssertEqual(draft(sections: [("", "")]).problems, ["add at least one section with a title"])
        XCTAssertTrue(draft(sections: Array(repeating: ("a", ""), count: 9)).problems.contains("at most 8 sections"))
        XCTAssertTrue(draft(sections: [(String(repeating: "t", count: 61), "")]).problems.contains { $0.contains("title is over 60") })
        XCTAssertTrue(draft(sections: [("t", String(repeating: "g", count: 301))]).problems.contains { $0.contains("guidance is over 300") })
        XCTAssertTrue(draft(sections: [("Next steps", ""), ("next-steps", "")]).problems.contains("two sections have the same title"))
        XCTAssertTrue(draft().isValid)
        XCTAssertNil(draft(name: "").build(id: "custom_x"))
    }

    func testUntitledSectionsAreDroppedOnBuild() throws {
        let template = try XCTUnwrap(draft(sections: [("kept", "yes"), ("   ", "dropped"), ("also kept", "")]).build(id: "custom_abc"))
        XCTAssertEqual(template.sections.map(\.key), ["kept", "also_kept"])
    }

    func testSectionKeysAreLowercaseUniqueAndBounded() {
        XCTAssertEqual(CustomInsightTemplates.sectionKeys(for: ["Next Steps", "next steps!", "Budget & Timeline", "123 go", ""]),
                       ["next_steps", "next_steps_2", "budget_timeline", "section_123_go", "section"])
        let long = CustomInsightTemplates.sectionKeys(for: [String(repeating: "abcdefghij", count: 5)])
        XCTAssertEqual(long[0].count, InsightTemplate.maxKeyLength)
        let pattern = try! NSRegularExpression(pattern: "^[a-z][a-z0-9_]{0,31}$")
        for key in CustomInsightTemplates.sectionKeys(for: ["Ünïcode títle", "emoji 🎉 time", "_leading_"]) {
            XCTAssertNotNil(pattern.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)), key)
        }
    }

    func testDerivedShortNameIsTwoWordsOrSixteenCharacters() {
        XCTAssertEqual(InsightTemplate.derivedShortName(from: "Customer QBR review"), "Customer QBR")
        XCTAssertEqual(InsightTemplate.derivedShortName(from: "Extraordinarilylongname here"), "Extraordinarilyl")
        XCTAssertEqual(InsightTemplate.derivedShortName(from: "   "), "Template")
    }

    // MARK: Store, export, import, duplicate

    func testStoreRoundTripsCustomTemplatesOnly() throws {
        let custom = try XCTUnwrap(draft().build(id: InsightTemplate.newCustomID()))
        CustomInsightTemplates.save([InsightTemplate.builtIn[0], custom], defaults: defaults)
        let loaded = CustomInsightTemplates.load(defaults: defaults)
        XCTAssertEqual(loaded, [custom], "built-ins are never persisted")

        CustomInsightTemplates.save([], defaults: defaults)
        XCTAssertNil(defaults.data(forKey: CustomInsightTemplates.storageKey))
        XCTAssertEqual(CustomInsightTemplates.load(defaults: defaults), [])
    }

    func testExportThenImportKeepsSectionsAndAssignsANewID() throws {
        let original = try XCTUnwrap(draft().build(id: InsightTemplate.newCustomID()))
        let data = try XCTUnwrap(original.exportData)
        let imported = try CustomInsightTemplates.importTemplate(from: data)
        XCTAssertNotEqual(imported.id, original.id)
        XCTAssertTrue(imported.isCustom)
        XCTAssertEqual(imported.name, original.name)
        XCTAssertEqual(imported.sections.map(\.title), original.sections.map(\.title))
        XCTAssertEqual(imported.sections.map(\.guidance), original.sections.map(\.guidance))
    }

    func testImportRejectsGarbageAndInvalidTemplates() throws {
        XCTAssertThrowsError(try CustomInsightTemplates.importTemplate(from: Data("nope".utf8)))
        let tooMany = InsightTemplate(id: "x", name: "Too many", shortName: "Too", summary: "", systemImage: "doc",
                                      sections: (0..<9).map { InsightTemplateSection(key: "k\($0)", title: "t\($0)", guidance: "") })
        XCTAssertThrowsError(try CustomInsightTemplates.importTemplate(from: try JSONEncoder().encode(tooMany))) { error in
            XCTAssertTrue("\(error.localizedDescription)".contains("at most 8 sections"))
        }
    }

    func testImportedBuiltInBecomesACustomCopy() throws {
        let bant = try XCTUnwrap(InsightTemplate.builtIn(id: "bant"))
        let imported = try CustomInsightTemplates.importTemplate(from: try XCTUnwrap(bant.exportData))
        XCTAssertTrue(imported.isCustom)
        XCTAssertEqual(imported.sections.map(\.key), bant.sections.map(\.key))
    }

    func testDuplicateOfABuiltInIsValidAndPrefixed() throws {
        let copy = CustomInsightTemplates.duplicate(try XCTUnwrap(InsightTemplate.builtIn(id: "interview")))
        XCTAssertTrue(copy.isCustom)
        XCTAssertEqual(copy.name, "Copy of Interview scorecard")
        XCTAssertLessThanOrEqual(copy.name.count, InsightTemplate.maxNameLength)
        XCTAssertEqual(copy.sections.count, 6)
        XCTAssertTrue(InsightTemplateDraft(template: copy).isValid)
    }

    // MARK: AppState resolution

    func testAppStateResolvesCustomTemplatesAfterBuiltIns() throws {
        let state = AppState()
        let custom = try XCTUnwrap(draft().build(id: InsightTemplate.newCustomID()))
        state.saveCustomInsightTemplate(custom)

        XCTAssertEqual(state.insightTemplate(id: custom.id), custom)
        XCTAssertEqual(state.insightTemplate(id: "bant")?.id, "bant")
        XCTAssertNil(state.insightTemplate(id: "missing"))
        XCTAssertEqual(state.availableInsightTemplates.suffix(1).map(\.id), [custom.id])
        XCTAssertEqual(state.availableInsightTemplates.prefix(InsightTemplate.builtIn.count).map(\.id), InsightTemplate.builtIn.map(\.id))

        state.selectInsightTemplate(custom.id)
        XCTAssertEqual(state.liveTemplate.id, custom.id)
        XCTAssertEqual(state.selectedInsightTemplate.id, custom.id)

        state.saveCustomInsightTemplate(InsightTemplate.builtIn[0])
        XCTAssertFalse(state.customInsightTemplates.contains { $0.id == "bant" }, "built-ins cannot be saved as custom")
    }

    func testDeletingACustomTemplateFallsBackAndMeetingsKeepTheirCopy() throws {
        let state = AppState()
        let custom = try XCTUnwrap(draft().build(id: InsightTemplate.newCustomID()))
        state.saveCustomInsightTemplate(custom)
        state.selectInsightTemplate(custom.id)

        let container = try TestSupport.makeInMemoryContainer()
        let meeting = Meeting(title: "review")
        meeting.applyInsightTemplate(custom)
        meeting.templateSections = ["health": "strong adoption", "next_steps": "renewal call"]
        container.mainContext.insert(meeting)
        try container.mainContext.save()

        state.deleteCustomInsightTemplate(id: custom.id)

        XCTAssertNil(state.insightTemplate(id: custom.id))
        XCTAssertEqual(state.insightTemplateID, InsightTemplate.defaultID)
        XCTAssertNil(state.liveTemplateID)
        let reloaded = try XCTUnwrap(try ModelContext(container).fetch(FetchDescriptor<Meeting>()).first)
        XCTAssertEqual(reloaded.insightTemplate?.name, "Customer QBR", "the meeting keeps rendering from its own copy")
        XCTAssertTrue(reloaded.hasTemplateInsights)
        XCTAssertTrue(reloaded.fullMeetingAsMarkdown().contains("Customer QBR"))
    }

    func testBuiltInTemplateIsNotSnapshottedOnTheMeeting() throws {
        let meeting = Meeting(title: "call")
        meeting.applyInsightTemplate(try XCTUnwrap(InsightTemplate.builtIn(id: "spin")))
        XCTAssertEqual(meeting.insightTemplateID, "spin")
        XCTAssertNil(meeting.templateDefinitionJSON)
        XCTAssertEqual(meeting.insightTemplate?.id, "spin")
    }

    func testCRMPayloadCarriesFilledTemplateSectionsInOrder() throws {
        let custom = try XCTUnwrap(draft().build(id: InsightTemplate.newCustomID()))
        let meeting = Meeting(title: "review")
        meeting.applyInsightTemplate(custom)
        meeting.templateSections = ["next_steps": "renewal call", "health": "strong adoption"]

        let payload = AttioMeetingPayload.from(meeting: meeting)
        let template = try XCTUnwrap(payload.template)
        XCTAssertEqual(template.name, "Customer QBR")
        XCTAssertEqual(template.sections.map(\.title), ["health", "next steps"])
        let dictionary = try XCTUnwrap(payload.dictionary["template"] as? [String: Any])
        XCTAssertEqual(dictionary["name"] as? String, "Customer QBR")
        XCTAssertEqual((dictionary["sections"] as? [[String: String]])?.map { $0["value"] }, ["strong adoption", "renewal call"])

        let bare = AttioMeetingPayload.from(meeting: Meeting(title: "no template"))
        XCTAssertNil(bare.template)
        XCTAssertNil(bare.dictionary["template"])
    }

    func testSettingsExposesTheTemplatesDestinationOnBothPlatforms() {
        XCTAssertTrue(SettingsDestination.available(on: .macOS).contains(.templates))
        XCTAssertTrue(SettingsDestination.available(on: .iOS).contains(.templates))
        XCTAssertEqual(SettingsDestination.fromLegacyID("templates"), .templates)
        XCTAssertTrue(SettingsSearchCatalog.availableItems(on: .iOS, appMode: .managed).contains { $0.id == "templates.custom" })
    }
}
