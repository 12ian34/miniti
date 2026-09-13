import CoreData
import Foundation
import SwiftData
import XCTest
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

/// Roadmap P0.2: the store open never crashes, never touches the file, and classifies
/// failures without leaking content.
final class PersistentStoreTests: XCTestCase {
    private var scratchDirectory: URL!

    override func setUpWithError() throws {
        scratchDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("miniti-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratchDirectory)
    }

    private var storeURL: URL { scratchDirectory.appendingPathComponent("scratch.store") }

    // MARK: Opening

    func testFreshTemporaryStoreOpensReady() throws {
        let state = PersistentStore.open(schema: PersistentStore.schema, url: storeURL)
        guard case .ready = state else {
            return XCTFail("expected ready, got \(state)")
        }
        XCTAssertNotNil(state.container)
        XCTAssertNil(state.failure)
        XCTAssertNil(state.readOnlyContainer)
    }

    @MainActor
    func testExistingStoreReopensWithItsMeetings() throws {
        let first = PersistentStore.open(schema: PersistentStore.schema, url: storeURL)
        guard case .ready(let container) = first else {
            return XCTFail("expected ready on first open")
        }
        let meeting = Meeting(title: "Reopen me")
        meeting.endTime = Date()
        container.mainContext.insert(meeting)
        try container.mainContext.save()

        let second = PersistentStore.open(schema: PersistentStore.schema, url: storeURL)
        guard case .ready(let reopened) = second else {
            return XCTFail("expected ready on second open")
        }
        let count = try reopened.mainContext.fetchCount(FetchDescriptor<Meeting>())
        XCTAssertEqual(count, 1)
    }

    func testGarbageFileFailsAndIsLeftByteForByteIntact() throws {
        var garbage = Data(count: 4096)
        for i in 0..<garbage.count { garbage[i] = UInt8((i * 31 + 7) & 0xFF) }
        try garbage.write(to: storeURL)

        let state = PersistentStore.open(schema: PersistentStore.schema, url: storeURL)
        guard case .failed(let failure, _) = state else {
            return XCTFail("expected failure opening a non-database file, got ready")
        }
        XCTAssertEqual(failure.category, .corruption, failure.summary)
        XCTAssertEqual(try Data(contentsOf: storeURL), garbage, "the store file must never be modified")
        XCTAssertFalse(failure.summary.contains(NSHomeDirectory()), "log summary must not carry the home path")
    }

    // MARK: Header preflight

    func testForeignHeaderDetection() throws {
        try Data("definitely not sqlite".utf8).write(to: storeURL)
        XCTAssertTrue(PersistentStoreOpenFailure.fileHasForeignHeader(at: storeURL))

        try Data("SQLite format 3\0trailing bytes".utf8).write(to: storeURL)
        XCTAssertFalse(PersistentStoreOpenFailure.fileHasForeignHeader(at: storeURL))

        try Data().write(to: storeURL)
        XCTAssertFalse(PersistentStoreOpenFailure.fileHasForeignHeader(at: storeURL), "an empty file is not evidence of corruption")

        XCTAssertFalse(PersistentStoreOpenFailure.fileHasForeignHeader(at: scratchDirectory.appendingPathComponent("missing.store")))
    }

    // MARK: Classification

    func testMigrationCodesClassifyAsMigration() {
        for code in [NSPersistentStoreIncompatibleVersionHashError, NSMigrationMissingMappingModelError, NSPersistentStoreIncompatibleSchemaError] {
            let error = NSError(domain: NSCocoaErrorDomain, code: code, userInfo: nil)
            let failure = PersistentStoreOpenFailure.classify(error)
            XCTAssertEqual(failure.category, .migration, "code \(code)")
            XCTAssertEqual(failure.code, code)
            XCTAssertEqual(failure.domain, NSCocoaErrorDomain)
        }
    }

    func testMigrationIsDetectedThroughAnUnderlyingError() {
        let underlying = NSError(domain: NSCocoaErrorDomain, code: NSMigrationError, userInfo: [NSLocalizedFailureReasonErrorKey: "Cannot migrate store in-place"])
        let wrapper = NSError(domain: "SwiftData.SwiftDataError", code: 1, userInfo: [NSUnderlyingErrorKey: underlying])
        let failure = PersistentStoreOpenFailure.classify(wrapper)
        XCTAssertEqual(failure.category, .migration)
        XCTAssertEqual(failure.domain, NSCocoaErrorDomain)
        XCTAssertEqual(failure.reason, "Cannot migrate store in-place")
    }

    func testSQLiteDomainAndCorruptTextClassifyAsCorruption() {
        let sqlite = NSError(domain: "NSSQLiteErrorDomain", code: 26, userInfo: [NSLocalizedDescriptionKey: "file is not a database"])
        XCTAssertEqual(PersistentStoreOpenFailure.classify(sqlite).category, .corruption)

        let corrupt = NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError, userInfo: nil)
        XCTAssertEqual(PersistentStoreOpenFailure.classify(corrupt).category, .corruption)

        let textual = NSError(domain: "Custom", code: 9, userInfo: [NSLocalizedDescriptionKey: "database disk image is malformed"])
        XCTAssertEqual(PersistentStoreOpenFailure.classify(textual).category, .corruption)
    }

    func testPosixAndFileErrorsClassifyAsIO() {
        let posix = NSError(domain: NSPOSIXErrorDomain, code: 13, userInfo: nil)
        XCTAssertEqual(PersistentStoreOpenFailure.classify(posix).category, .io)

        let space = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError, userInfo: nil)
        XCTAssertEqual(PersistentStoreOpenFailure.classify(space).category, .io)

        let textual = NSError(domain: "Custom", code: 1, userInfo: [NSLocalizedDescriptionKey: "You don't have permission to save the file"])
        XCTAssertEqual(PersistentStoreOpenFailure.classify(textual).category, .io)
    }

    func testUnrecognisedErrorsClassifyAsUnknown() {
        let error = NSError(domain: "Custom", code: 42, userInfo: [NSLocalizedDescriptionKey: "something else happened"])
        let failure = PersistentStoreOpenFailure.classify(error)
        XCTAssertEqual(failure.category, .unknown)
        XCTAssertEqual(failure.reason, "something else happened")
    }

    func testHeaderPreflightWinsOverAnOpaqueError() throws {
        try Data("not sqlite at all".utf8).write(to: storeURL)
        let opaque = NSError(domain: "SwiftData.SwiftDataError", code: 1, userInfo: nil)
        XCTAssertEqual(PersistentStoreOpenFailure.classify(opaque, storeURL: storeURL).category, .corruption)
        XCTAssertEqual(PersistentStoreOpenFailure.classify(opaque).category, .unknown)
    }

    func testUnreadableStoreOrUnwritableFolderClassifiesAsIO() throws {
        let opaque = NSError(domain: "SwiftData.SwiftDataError", code: 1, userInfo: nil)

        // Existing store the process cannot read.
        try Data("SQLite format 3\0".utf8).write(to: storeURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: storeURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: storeURL.path) }
        XCTAssertTrue(PersistentStoreOpenFailure.storeIsInaccessible(at: storeURL))
        XCTAssertEqual(PersistentStoreOpenFailure.classify(opaque, storeURL: storeURL).category, .io)

        // Missing store in a folder the process cannot write (a sandbox denial looks like this).
        let lockedDirectory = scratchDirectory.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: lockedDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: lockedDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedDirectory.path) }
        let missing = lockedDirectory.appendingPathComponent("missing.store")
        XCTAssertTrue(PersistentStoreOpenFailure.storeIsInaccessible(at: missing))
        XCTAssertEqual(PersistentStoreOpenFailure.classify(opaque, storeURL: missing).category, .io)

        // A missing store in a writable folder is not an access problem.
        XCTAssertFalse(PersistentStoreOpenFailure.storeIsInaccessible(at: scratchDirectory.appendingPathComponent("new.store")))
        XCTAssertEqual(PersistentStoreOpenFailure.classify(opaque, storeURL: scratchDirectory.appendingPathComponent("new.store")).category, .unknown)
    }

    func testReasonRedactsHomeDirectoryAndCapsLength() {
        let path = "/Users/someone/Library/Application Support/default.store"
        let error = NSError(domain: "Custom", code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "cannot open \(path)\nsecond line"])
        let reason = PersistentStoreOpenFailure.redactedReason(error)
        XCTAssertFalse(reason.contains("/Users/someone"))
        XCTAssertTrue(reason.contains("~/Library/Application Support/default.store"))
        XCTAssertFalse(reason.contains("\n"))

        let long = NSError(domain: "Custom", code: 1, userInfo: [NSLocalizedDescriptionKey: String(repeating: "x", count: 500)])
        XCTAssertEqual(PersistentStoreOpenFailure.redactedReason(long).count, 201)
    }

    func testEveryCategoryHasUserCopy() {
        for category in PersistentStoreOpenFailure.Category.allCases {
            XCTAssertFalse(category.userDescription.isEmpty)
            XCTAssertEqual(category.userDescription, category.userDescription.lowercased(), "recovery copy is lowercase like every other gate screen")
        }
    }

    // MARK: AppState integration

    @MainActor
    func testNotePersistentStorePublishesFailureAndClearsOnReady() throws {
        let appState = AppState()
        let failure = PersistentStoreOpenFailure(category: .corruption, domain: "NSSQLiteErrorDomain", code: 26, reason: "file is not a database")
        appState.notePersistentStore(.failed(failure, readOnly: nil))
        XCTAssertEqual(appState.persistentStoreFailure, failure)

        // Same failure twice is idempotent.
        appState.notePersistentStore(.failed(failure, readOnly: nil))
        XCTAssertEqual(appState.persistentStoreFailure, failure)

        let container = try ModelContainer(for: Meeting.self, TranscriptSegment.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        appState.notePersistentStore(.ready(container))
        XCTAssertNil(appState.persistentStoreFailure)
    }
}
