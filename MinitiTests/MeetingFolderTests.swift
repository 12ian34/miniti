import XCTest
import SwiftData
import Combine
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

@MainActor
final class MeetingFolderTests: XCTestCase {
    func testUpgradingLegacyFolderExtrasRebasesCleanRowsButPreservesDirtyEdits() throws {
        let container = try TestSupport.makeInMemoryContainer()
        for folder in ["null", "\"\(UUID().uuidString.lowercased())\""] {
            for dirty in [false, true] {
                let meeting = Meeting(title: "Synced on 3.7", endTime: Date())
                meeting.syncExtraJSON = "{\"folder_id\":\(folder),\"folder_manual\":false}"
                meeting.cloudRevision = 9
                meeting.updatedAt = Date(timeIntervalSince1970: 100)
                meeting.syncFingerprint = MeetingSyncDocument.fingerprint(of: meeting)
                meeting.localFingerprint = meeting.syncFingerprint
                if dirty { meeting.notes = "Offline edit on 3.7" }
                container.mainContext.insert(meeting)
                try container.mainContext.save()
                let oldSync = meeting.syncFingerprint
                let fetched = try container.mainContext.fetch(FetchDescriptor<Meeting>(predicate: #Predicate { $0.syncExtraJSON != nil }))
                XCTAssertTrue(fetched.contains { $0.id == meeting.id }, "Legacy row must be eligible for launch migration")
                let state = AppState(); state.modelContext = container.mainContext
                let after = MeetingSyncDocument.fingerprint(of: meeting)
                XCTAssertEqual(meeting.syncFingerprint == after, !dirty)
                XCTAssertEqual(meeting.localFingerprint == after, !dirty)
                if dirty { XCTAssertEqual(meeting.syncFingerprint, oldSync) }
                XCTAssertEqual(meeting.updatedAt, Date(timeIntervalSince1970: 100))
                XCTAssertNil(meeting.syncExtraJSON)
                state.modelContext = container.mainContext
                XCTAssertEqual(MeetingSyncDocument.fingerprint(of: meeting), after, "Reopening is idempotent")
                XCTAssertEqual(meeting.cloudRevision, 9)
            }
        }
    }

    func testOngoingOvernightCalendarEventStaysUnderToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1793923800)
        let start = calendar.startOfDay(for: now).addingTimeInterval(-1800)
        let end = now.addingTimeInterval(1800)
        XCTAssertTrue(UpcomingCalendarDay.today.contains(start, end: end, now: now, calendar: calendar))
        XCTAssertFalse(UpcomingCalendarDay.later.contains(start, end: end, now: now, calendar: calendar))
    }

    func testGenericNameMentionInSummaryDoesNotFileMeeting() {
        let folder = MeetingFolder(id: UUID(), name: "Team")
        XCTAssertNil(FolderMatcher.match(title: "Pricing discussion", summary: "The team discussed pricing", folders: [folder]))
        XCTAssertEqual(FolderMatcher.match(title: "Team catch-up", summary: nil, folders: [folder]), folder.id)
    }

    func testConcurrentAdditionsAtCapacityRemainRecoverableConflicts() {
        let store = MeetingFolderStore(url: nil)
        let local = MeetingFolder(id: UUID(), name: "My addition")
        XCTAssertTrue(store.edit(local))
        let remote = (0..<200).map { MeetingFolder(id: UUID(), name: "Remote \($0)") }
        XCTAssertTrue(store.merge(.init(revision: 1, folders: remote)))
        XCTAssertEqual(store.active.count, 200)
        XCTAssertEqual(store.scope.conflicts, [local])
        store.resolveConflict(local.id, keepMine: true)
        XCTAssertEqual(store.active.count, 200)
        XCTAssertEqual(store.scope.conflicts, [local])
        var removed = remote[0]; removed.deleted = true
        XCTAssertTrue(store.edit(removed))
        store.resolveConflict(local.id, keepMine: true)
        XCTAssertEqual(store.folder(local.id), local, "Capacity recovery must retain membership IDs")
        XCTAssertTrue(store.scope.conflicts.isEmpty)
    }

    func testIdenticalCatalogPollDoesNotPublishOrWriteAgain() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = MeetingFolderStore(url: url)
        let catalog = FolderCatalog(revision: 1, folders: [.init(id: UUID(), name: "Team")])
        XCTAssertTrue(store.merge(catalog))
        let before = try Data(contentsOf: url)
        var publications = 0
        let subscription = store.objectWillChange.sink { publications += 1 }
        defer { subscription.cancel() }
        for _ in 0..<10 { XCTAssertTrue(store.merge(catalog)) }
        XCTAssertEqual(publications, 0)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testRenamedBroadFolderStillUsesTitleEvidenceRatherThanSummaryWords() {
        let state = AppState(); state.automaticFolderCreation = false
        var folder = FolderMatcher.Category.team.folder(owner: state.meetingFolders.owner, localOnly: false)
        folder.name = "Our people"
        XCTAssertTrue(state.meetingFolders.edit(folder))
        let unrelated = Meeting(title: "Budget review", endTime: Date(), summaryText: "The team discussed our people and standups.")
        let actual = Meeting(title: "Team sync", endTime: Date())
        let result = state.folderProposals(meetings: [unrelated, actual])
        XCTAssertEqual(result.map { $0.meeting.id }, [actual.id])
        XCTAssertEqual(result.first?.folder.id, folder.id)
    }

    func testUnicodeNameUsesTheSameLengthBoundAsTheBackend() {
        let store = MeetingFolderStore(url: nil)
        XCTAssertTrue(store.edit(.init(id: UUID(), name: String(repeating: "😀", count: 40))))
        XCTAssertFalse(store.edit(.init(id: UUID(), name: String(repeating: "😀", count: 41))))
        XCTAssertEqual(store.active.count, 1)
    }

    func testRecreatingADeletedConflictCannotBypassTheActiveFolderLimit() {
        let store = MeetingFolderStore(url: nil)
        let original = MeetingFolder(id: UUID(), name: "Original")
        XCTAssertTrue(store.merge(.init(revision: 1, folders: [original])))
        var mine = original; mine.name = "My edit"
        XCTAssertTrue(store.edit(mine))
        var deleted = original; deleted.deleted = true
        let others = (0..<200).map { MeetingFolder(id: UUID(), name: "Folder \($0)") }
        XCTAssertTrue(store.merge(.init(revision: 2, folders: others + [deleted])))
        store.resolveConflict(original.id, keepMine: true)
        XCTAssertEqual(store.active.count, 200)
        XCTAssertEqual(store.scope.conflicts, [mine])
        XCTAssertNotNil(store.issue)
    }

    func testCanonicalCatalogFixtureDecodes() throws {
        let catalog = try JSONDecoder().decode(FolderCatalog.self, from: Data(ContractFixtures.folders.utf8))
        XCTAssertEqual(catalog.folders.count, 1)
        XCTAssertEqual(catalog.folders.first?.name, "Aurora project")
        XCTAssertEqual(catalog.folders.first?.localOnly, false)
    }

    func testCatalogPersistsRenamesAndTombstonesWithoutCrossingAccounts() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("folders.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = MeetingFolderStore(url: url)
        store.selectOwner("ExactAccount")
        var folder = MeetingFolder(id: UUID(), name: "Project Aurora", description: "Launch design")
        XCTAssertTrue(store.edit(folder))
        folder.name = "Aurora launch"
        XCTAssertTrue(store.edit(folder))
        let reopened = MeetingFolderStore(url: url)
        reopened.selectOwner("ExactAccount")
        XCTAssertEqual(reopened.active, [folder])
        reopened.selectOwner("exactaccount")
        XCTAssertTrue(reopened.active.isEmpty)
        reopened.selectOwner("ExactAccount")
        folder.deleted = true
        XCTAssertTrue(reopened.edit(folder))
        XCTAssertNil(reopened.folder(folder.id))
        XCTAssertEqual(reopened.scope.folders.first?.description, "")
        XCTAssertEqual(reopened.scope.folders.first?.name, "Deleted folder")
        folder.deleted = false
        XCTAssertFalse(reopened.edit(folder), "An old local writer cannot resurrect a tombstone")
    }

    func testUnreadableCatalogIsNeverOverwritten() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bytes = Data("unreadable original".utf8)
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = MeetingFolderStore(url: url)
        XCTAssertFalse(store.edit(.init(id: UUID(), name: "New")))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testDifferentEditsMergeSameFolderConflictsAndDeletionWins() {
        let store = MeetingFolderStore(url: nil)
        store.selectOwner("account")
        let a = MeetingFolder(id: UUID(), name: "Aurora")
        let b = MeetingFolder(id: UUID(), name: "Borealis")
        XCTAssertTrue(store.merge(.init(revision: 1, folders: [a, b])))
        var local = a; local.description = "My edit"
        XCTAssertTrue(store.edit(local))
        var remote = b; remote.name = "Cloud edit"
        XCTAssertTrue(store.merge(.init(revision: 2, folders: [a, remote])))
        XCTAssertEqual(store.folder(a.id), local)
        XCTAssertEqual(store.folder(b.id), remote)
        var deleted = a; deleted.deleted = true
        XCTAssertTrue(store.merge(.init(revision: 3, folders: [deleted, remote])))
        XCTAssertNil(store.folder(a.id))
        XCTAssertEqual(store.scope.conflicts, [local])
        store.resolveConflict(a.id, keepMine: true)
        XCTAssertNil(store.folder(a.id))
        XCTAssertTrue(store.active.contains { $0.name == local.name && $0.id != a.id })
    }

    func testLocalOnlyCatalogNeverEntersCloudAndHeldSyncCannotCrossOwner() async {
        let store = MeetingFolderStore(url: nil)
        store.selectOwner("a")
        let local = MeetingFolder(id: UUID(), name: "Private title", localOnly: true)
        XCTAssertTrue(store.edit(local))
        var writes = 0
        await store.sync(allowed: { true }, read: { .init() }, write: { value in writes += 1; return value })
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(store.folder(local.id), local)
        XCTAssertTrue(store.edit(.init(id: UUID(), name: "Shared")))
        await store.sync(allowed: { true }, read: {
            store.selectOwner("b")
            return .init(revision: 3, folders: [.init(id: UUID(), name: "Account A")])
        }, write: { value in writes += 1; return value })
        XCTAssertTrue(store.active.isEmpty)
        XCTAssertEqual(writes, 0)
    }

    func testPurgedCloudCopyKeepsLocalFoldersAndQueuesThemAgain() {
        let store = MeetingFolderStore(url: nil); store.selectOwner("a")
        let folder = MeetingFolder(id: UUID(), name: "Retained locally")
        XCTAssertTrue(store.merge(.init(revision: 1, folders: [folder])))
        XCTAssertTrue(store.merge(.init()))
        XCTAssertEqual(store.folder(folder.id), folder)
        XCTAssertTrue(store.scope.dirty.contains(folder.id))
    }

    func testLocalEditDuringAcceptedWriteRemainsDirty() async {
        let store = MeetingFolderStore(url: nil); store.selectOwner("a")
        var folder = MeetingFolder(id: UUID(), name: "First")
        XCTAssertTrue(store.edit(folder))
        await store.sync(allowed: { true }, read: { .init() }, write: { sent in
            folder.name = "Edited during write"; XCTAssertTrue(store.edit(folder))
            return .init(revision: 1, folders: sent.folders)
        })
        XCTAssertEqual(store.folder(folder.id)?.name, "Edited during write")
        XCTAssertTrue(store.scope.dirty.contains(folder.id))
        XCTAssertEqual(store.scope.base.revision, 1)
    }

    func testBusyAndConcurrentFolderWritesRetryWithFreshCatalog() async {
        let store = MeetingFolderStore(url: nil); store.selectOwner("a")
        let folder = MeetingFolder(id: UUID(), name: "Customers")
        XCTAssertTrue(store.edit(folder))
        var reads = 0, writes = 0, waits = 0
        store.sleep = { _ in waits += 1 }
        await store.sync(allowed: { true }, read: {
            reads += 1
            return .init(revision: reads)
        }, write: { sent in
            writes += 1
            if writes == 1 { throw CloudSyncError.busy(retryAfter: 2) }
            if writes == 2 { throw CloudSyncError.server(code: "folder_conflict", status: 409) }
            return .init(revision: sent.revision + 1, folders: sent.folders)
        })
        XCTAssertEqual(reads, 3); XCTAssertEqual(writes, 3); XCTAssertEqual(waits, 2)
        XCTAssertTrue(store.scope.dirty.isEmpty)
        XCTAssertNil(store.issue)
    }

    func testMatchingRulesDescriptionsAmbiguityAndNoSummary() {
        let a = MeetingFolder(id: UUID(), name: "Aurora", description: "Migration roadmap")
        let b = MeetingFolder(id: UUID(), name: "Borealis", description: "Migration roadmap")
        XCTAssertEqual(FolderMatcher.match(title: "Aurora planning", summary: nil, folders: [a, b]), a.id)
        XCTAssertNil(FolderMatcher.match(title: "Migration roadmap", summary: nil, folders: [a, b]))
        XCTAssertEqual(FolderMatcher.match(title: "Unrelated", summary: "Migration roadmap", folders: [a]), a.id)
        XCTAssertNil(FolderMatcher.match(title: "Notes", summary: nil, folders: [a]))
        var rule = b; rule.titleRule = "Client 42"
        XCTAssertEqual(FolderMatcher.match(title: "Client 42 sync", summary: nil, folders: [a, rule]), b.id)
    }

    func testAutomaticFilingOnlyChangesNewMeetingUntilHistoryPreviewIsApplied() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let state = AppState(); state.modelContext = container.mainContext
        state.automaticFolderCreation = true; state.automaticFolderFiling = true
        let old = Meeting(title: "Acme customer review", startTime: Date().addingTimeInterval(-86400), endTime: Date().addingTimeInterval(-86000))
        let new = Meeting(title: "Borealis sales demo", endTime: Date())
        [old, new].forEach { container.mainContext.insert($0) }
        try container.mainContext.save()
        state.automaticallyFileMeeting(new)
        XCTAssertNotNil(new.folderID)
        XCTAssertNil(old.folderID, "History provides matching evidence without being reorganised")
        let preview = state.folderProposals(meetings: [old])
        XCTAssertFalse(preview.isEmpty)
        XCTAssertNil(old.folderID, "Preview is read-only")
        _ = state.applyFolderProposals(preview)
        XCTAssertEqual(old.folderID, new.folderID)
    }

    func testPreviewIsReadOnlyManualOverrideDeleteKeepsMeetingsAndBulkUndo() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let state = AppState(); state.modelContext = container.mainContext
        state.automaticFolderCreation = true
        let a = Meeting(title: "Product planning", endTime: Date())
        let b = Meeting(title: "Product planning", endTime: Date())
        let manual = Meeting(title: "Product planning", endTime: Date()); manual.folderManual = true
        [a, b, manual].forEach { container.mainContext.insert($0) }
        try container.mainContext.save()
        let preview = state.folderProposals(meetings: [a, b, manual])
        XCTAssertEqual(preview.count, 2)
        XCTAssertTrue(state.meetingFolders.active.isEmpty)
        XCTAssertNil(a.folderID)
        let undo = state.applyFolderProposals(preview)
        XCTAssertEqual(undo.count, 2)
        XCTAssertEqual(a.folderID, b.folderID)
        XCTAssertNil(manual.folderID)
        state.undoFolderMoves(undo)
        XCTAssertNil(a.folderID); XCTAssertNil(b.folderID)
        _ = state.applyFolderProposals(state.folderProposals(meetings: [a, b]))
        var folder = try XCTUnwrap(state.meetingFolders.folder(a.folderID)); folder.deleted = true
        XCTAssertTrue(state.meetingFolders.edit(folder))
        state.showUnfiledMeetings = true
        XCTAssertTrue(state.folderIncludes(a))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Meeting>()), 3)
    }

    func testRenamedAutomaticFolderKeepsMatchingItsOriginalTitle() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let state = AppState(); state.modelContext = container.mainContext; state.automaticFolderCreation = true
        let meetings = [Meeting(title: "Customer review", endTime: Date()), Meeting(title: "Customer review", endTime: Date())]
        meetings.forEach { container.mainContext.insert($0) }; try container.mainContext.save()
        _ = state.applyFolderProposals(state.folderProposals(meetings: meetings))
        var folder = try XCTUnwrap(state.meetingFolders.folder(meetings[0].folderID))
        folder.name = "Customer work"; XCTAssertTrue(state.meetingFolders.edit(folder))
        let next = Meeting(title: "Customer review", endTime: Date()); container.mainContext.insert(next)
        let proposals = state.folderProposals(meetings: meetings + [next])
        XCTAssertEqual(proposals.first { $0.meeting.id == next.id }?.folder.id, folder.id)
        XCTAssertEqual(state.meetingFolders.active.count, 1)
    }

    func testPrivateGeneratedFolderAndMembershipStayLocalAcrossWireRoundTrip() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let state = AppState(); state.modelContext = container.mainContext
        state.automaticFolderCreation = true
        let a = Meeting(title: "Private customer", endTime: Date()); a.syncExcluded = true
        let b = Meeting(title: "Private customer", endTime: Date()); b.syncExcluded = true
        [a, b].forEach { container.mainContext.insert($0) }
        try container.mainContext.save()
        _ = state.applyFolderProposals(state.folderProposals(meetings: [a, b]))
        XCTAssertTrue(try XCTUnwrap(state.meetingFolders.folder(a.folderID)).localOnly)
        let document = MeetingSyncDocument.encode(a, segments: [])
        XCTAssertNil(document["folder_id"])
        XCTAssertNil(document["folder_manual"])
        let shared = Meeting(title: "Shared", endTime: Date()); shared.folderID = UUID(); shared.folderManual = true
        let encoded = MeetingSyncDocument.encode(shared, segments: [])
        let decoded = try XCTUnwrap(MeetingSyncDocument.decode(encoded))
        let copy = Meeting(title: "Copy"); container.mainContext.insert(copy)
        MeetingSyncDocument.apply(decoded, to: copy, in: container.mainContext, replaceSegments: false)
        XCTAssertEqual(copy.folderID, shared.folderID); XCTAssertEqual(copy.folderManual, true)
    }

    func testDifferentMeetingTitlesShareBroadFoldersAndUnknownTitlesStayUnfiled() {
        let state = AppState(); state.automaticFolderCreation = true
        let meetings = ["Acme customer review", "Borealis sales demo", "Monday standup", "Friday team sync", "Aurora catch-up", "Aurora catch-up"]
            .map { Meeting(title: $0, endTime: Date()) }
        let result = state.folderProposals(meetings: meetings)
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(Set(result.map { $0.folder.name }), ["Customers", "Team"])
        XCTAssertEqual(result.filter { $0.folder.name == "Customers" }.count, 2)
        XCTAssertTrue(result.allSatisfy { !$0.folder.description.isEmpty })
        XCTAssertTrue(state.meetingFolders.active.isEmpty, "Preview must not create the catalog")
    }

    func testBroadCategoriesUseWholeTitlePhrasesAndLeaveAmbiguityAlone() {
        XCTAssertEqual(FolderMatcher.Category.matching(title: "Sprint planning"), .product)
        XCTAssertEqual(FolderMatcher.Category.matching(title: "Sam / Ian 1:1"), .team)
        XCTAssertEqual(FolderMatcher.Category.matching(title: "ACME customer check-in"), .customers)
        XCTAssertNil(FolderMatcher.Category.matching(title: "Product hiring interview"))
        XCTAssertNil(FolderMatcher.Category.matching(title: "Demonstration of partnershipless words"))
        let state = AppState(); state.automaticFolderCreation = true
        let meetings = (0..<2).map { _ in
            let meeting = Meeting(title: "Notes", endTime: Date())
            meeting.summaryText = "Product roadmap, customer sales and team planning"
            return meeting
        }
        XCTAssertTrue(state.folderProposals(meetings: meetings).isEmpty)
    }

    func testCustomFolderWinsAndEditedBroadDescriptionMatchesNewTitles() {
        let state = AppState(); state.automaticFolderCreation = true
        let custom = MeetingFolder(id: UUID(), name: "Acme", titleRule: "Acme")
        XCTAssertTrue(state.meetingFolders.edit(custom))
        let meetings = ["Acme customer review", "Borealis customer review"].map { Meeting(title: $0, endTime: Date()) }
        let proposals = state.folderProposals(meetings: meetings)
        XCTAssertEqual(proposals.first { $0.meeting.id == meetings[0].id }?.folder.id, custom.id)
        XCTAssertEqual(proposals.first { $0.meeting.id == meetings[1].id }?.folder.name, "Customers")
        var broad = FolderMatcher.Category.team.folder(owner: state.meetingFolders.owner, localOnly: false)
        broad.description = "Internal release coordination"
        XCTAssertTrue(state.meetingFolders.edit(broad))
        let next = Meeting(title: "Release coordination", endTime: Date())
        XCTAssertEqual(state.folderProposals(meetings: [next]).first?.folder.id, broad.id)
    }

    func testDeletedBroadFolderIsNotRegeneratedAndCreationOffStillFilesExistingFolders() {
        let state = AppState(); state.automaticFolderCreation = false
        let meetings = ["Team sync", "Monday standup"].map { Meeting(title: $0, endTime: Date()) }
        XCTAssertTrue(state.folderProposals(meetings: meetings).isEmpty)
        var folder = FolderMatcher.Category.team.folder(owner: state.meetingFolders.owner, localOnly: false)
        XCTAssertTrue(state.meetingFolders.edit(folder))
        XCTAssertEqual(state.folderProposals(meetings: meetings).count, 2)
        folder.deleted = true; XCTAssertTrue(state.meetingFolders.edit(folder))
        state.automaticFolderCreation = true
        XCTAssertTrue(state.folderProposals(meetings: meetings).isEmpty)
    }

    func testAmbiguousCustomRulesDoNotFallThroughToABroadSuggestion() {
        let state = AppState(); state.automaticFolderCreation = true
        XCTAssertTrue(state.meetingFolders.edit(.init(id: UUID(), name: "Acme", titleRule: "customer")))
        XCTAssertTrue(state.meetingFolders.edit(.init(id: UUID(), name: "Borealis", titleRule: "customer")))
        let meetings = ["Customer review", "Customer check-in"].map { Meeting(title: $0, endTime: Date()) }
        XCTAssertTrue(state.folderProposals(meetings: meetings).isEmpty)
    }

    func testThousandMeetingPreviewHasBoundedWork() throws {
        let state = AppState(); state.automaticFolderCreation = true
        for index in 0..<50 {
            XCTAssertTrue(state.meetingFolders.edit(.init(id: UUID(), name: "Project \(index)", description: "Planning and execution of the specialised project \(index)")))
        }
        let meetings = (0..<1500).map { Meeting(title: "Customer \($0 % 100) review", endTime: Date(), summaryText: String(repeating: "Progress and next actions. ", count: 150)) }
        let result = state.folderProposals(meetings: meetings)
        XCTAssertLessThanOrEqual(result.count, 1000)
        XCTAssertEqual(Set(result.map(\.id)).count, result.count)
    }
}
