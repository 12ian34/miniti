import CoreData
import Foundation
import SwiftData
import SwiftUI

/// Why the on-disk meeting store could not be opened. Content-free by construction: it
/// carries error domains, codes, and the framework's own reason text, never meeting data,
/// so it is safe to log and to send as a diagnostics event.
struct PersistentStoreOpenFailure: Error, Equatable {
    enum Category: String, CaseIterable {
        case migration
        case corruption
        case io
        case unknown

        /// One plain sentence for the recovery screen. Lowercase, in Ian's voice.
        var userDescription: String {
            switch self {
            case .migration:
                return "your meetings database was written by a different version of miniti and this version can't read it. nothing has been changed"
            case .corruption:
                return "the meetings database file is damaged. your file has not been touched, so a backup or a repair can still recover it"
            case .io:
                return "miniti can't read or write its data folder. check free disk space and folder permissions, then try again"
            case .unknown:
                return "miniti couldn't open your meetings database. nothing has been changed"
            }
        }
    }

    let category: Category
    let domain: String
    let code: Int
    /// Innermost framework reason, home directory redacted, capped in length.
    let reason: String

    /// One log line: `category=… domain=… code=… reason=…`.
    var summary: String {
        "category=\(category.rawValue) domain=\(domain) code=\(code) reason=\(reason)"
    }

    private static let migrationCodes: Set<Int> = [
        NSPersistentStoreIncompatibleVersionHashError,
        NSMigrationError,
        NSMigrationConstraintViolationError,
        NSMigrationCancelledError,
        NSMigrationMissingSourceModelError,
        NSMigrationMissingMappingModelError,
        NSMigrationManagerSourceStoreError,
        NSMigrationManagerDestinationStoreError,
        NSPersistentStoreIncompatibleSchemaError,
    ]

    private static let corruptionCodes: Set<Int> = [
        NSFileReadCorruptFileError,
        NSFileReadUnknownError,
    ]

    private static let ioCodes: Set<Int> = [
        NSFileNoSuchFileError,
        NSFileReadNoPermissionError,
        NSFileReadNoSuchFileError,
        NSFileWriteNoPermissionError,
        NSFileWriteOutOfSpaceError,
        NSFileWriteVolumeReadOnlyError,
        NSFileLockingError,
    ]

    /// Walk the error and its underlying chain, outermost first.
    static func errorChain(_ error: Error) -> [NSError] {
        var chain: [NSError] = []
        var seen = Set<ObjectIdentifier>()
        var queue: [NSError] = [error as NSError]
        while let next = queue.first {
            queue.removeFirst()
            guard seen.insert(ObjectIdentifier(next)).inserted else { continue }
            chain.append(next)
            if let underlying = next.userInfo[NSUnderlyingErrorKey] as? NSError {
                queue.append(underlying)
            }
            if let multiple = next.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] {
                queue.append(contentsOf: multiple)
            }
            for nested in next.underlyingErrors {
                queue.append(nested as NSError)
            }
        }
        return chain
    }

    /// Classify an open failure. `storeURL` enables the SQLite header preflight, which is the
    /// only deterministic corruption signal when SwiftData hides the underlying CoreData error.
    static func classify(_ error: Error, storeURL: URL? = nil) -> PersistentStoreOpenFailure {
        let chain = errorChain(error)
        let innermost = chain.last ?? (error as NSError)
        let text = chain
            .flatMap { [$0.domain, "\($0.code)", $0.localizedDescription, $0.userInfo[NSLocalizedFailureReasonErrorKey] as? String ?? "", "\($0)"] }
            .joined(separator: " ")
            .lowercased()

        let category: Category
        if chain.contains(where: { $0.domain == NSCocoaErrorDomain && migrationCodes.contains($0.code) })
            || text.contains("migrat") || text.contains("version hash") || text.contains("incompatible") {
            category = .migration
        } else if let storeURL, fileHasForeignHeader(at: storeURL) {
            category = .corruption
        } else if let storeURL, storeIsInaccessible(at: storeURL) {
            category = .io
        } else if chain.contains(where: { $0.domain == "NSSQLiteErrorDomain" })
            || chain.contains(where: { $0.domain == NSCocoaErrorDomain && corruptionCodes.contains($0.code) })
            || text.contains("corrupt") || text.contains("malformed") || text.contains("not a database") || text.contains("database disk image") {
            category = .corruption
        } else if chain.contains(where: { $0.domain == NSPOSIXErrorDomain })
            || chain.contains(where: { $0.domain == NSCocoaErrorDomain && ioCodes.contains($0.code) })
            || text.contains("permission") || text.contains("no space") || text.contains("read-only") || text.contains("read only") || text.contains("disk full") {
            category = .io
        } else {
            category = .unknown
        }

        return PersistentStoreOpenFailure(
            category: category,
            domain: innermost.domain,
            code: innermost.code,
            reason: redactedReason(innermost)
        )
    }

    /// True when the store exists but cannot be read, or does not exist and its folder cannot
    /// be written. This is what a sandbox denial or a read-only volume looks like; SwiftData
    /// reports both as an opaque `SwiftDataError`, so the file system is asked directly.
    static func storeIsInaccessible(at url: URL) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            return !fm.isReadableFile(atPath: url.path)
        }
        return !fm.isWritableFile(atPath: url.deletingLastPathComponent().path)
    }

    /// True when the file exists, is non-empty, and does not start with the SQLite magic.
    static func fileHasForeignHeader(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 16), !head.isEmpty else { return false }
        let magic = Data("SQLite format 3\0".utf8)
        return head.count < magic.count || head.prefix(magic.count) != magic
    }

    static func redactedReason(_ error: NSError) -> String {
        var reason = (error.userInfo[NSLocalizedFailureReasonErrorKey] as? String) ?? error.localizedDescription
        if reason.isEmpty { reason = "\(error.domain) \(error.code)" }
        reason = reason.replacingOccurrences(of: #"/Users/[^/\s]+"#, with: "~", options: .regularExpression)
        reason = reason.replacingOccurrences(of: #"/var/mobile/Containers/Data/Application/[^/\s]+"#, with: "~", options: .regularExpression)
        reason = reason.replacingOccurrences(of: "\n", with: " ")
        if reason.count > 200 {
            reason = String(reason.prefix(200)) + "…"
        }
        return reason
    }
}

/// Outcome of opening the meeting store at launch.
enum PersistentStoreState {
    case ready(ModelContainer)
    /// The read-write open failed. `readOnly` is a best-effort second open that lets the
    /// recovery screen export whatever can still be read; it is nil when that failed too.
    case failed(PersistentStoreOpenFailure, readOnly: ModelContainer?)

    var container: ModelContainer? {
        if case .ready(let container) = self { return container }
        return nil
    }

    var failure: PersistentStoreOpenFailure? {
        if case .failed(let failure, _) = self { return failure }
        return nil
    }

    var readOnlyContainer: ModelContainer? {
        if case .failed(_, let readOnly) = self { return readOnly }
        return nil
    }
}

/// Opens the SwiftData store without ever deleting, moving, or recreating it.
///
/// Roadmap P0.2: both app targets used to `fatalError` here, which made miniti unlaunchable
/// exactly when a user needed to export. Now the entry points render `StoreRecoveryView`
/// on failure and keep every byte of the store intact.
enum PersistentStore {
    static let schema = Schema([
        Meeting.self,
        TranscriptSegment.self,
    ])

    /// Default on-disk location SwiftData uses for the unnamed configuration.
    static var defaultStoreURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("default.store")
    }

    /// Debug-only `-MinitiStoreURL <path>` launch argument so the recovery screen and the
    /// manual drill in `docs/testing.md` can run against a scratch file instead of the real
    /// store. Ignored in Release builds.
    static var storeURLOverride: URL? {
        #if DEBUG
        if let path = UserDefaults.standard.string(forKey: "MinitiStoreURL"), !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        #endif
        return nil
    }

    /// The launch-time open used by both app entry points.
    static func open() -> PersistentStoreState {
        if let seeded = ScreenshotMode.makeSeededContainer(schema: schema) {
            if ScreenshotMode.current == .storeRecovery {
                return .failed(ScreenshotMode.syntheticStoreFailure, readOnly: seeded)
            }
            return .ready(seeded)
        }
        return open(schema: schema, url: storeURLOverride)
    }

    /// Open the store at `url` (nil = SwiftData's default location). On failure, try a
    /// read-only open so meetings can still be exported.
    static func open(schema: Schema, url: URL?) -> PersistentStoreState {
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration(schema: schema, url: url, allowsSave: true)])
            return .ready(container)
        } catch {
            let failure = PersistentStoreOpenFailure.classify(error, storeURL: url ?? defaultStoreURL)
            DebugLogger.shared.log(.app, "Persistent store open FAILED: \(failure.summary)", level: .error)
            let readOnly = try? ModelContainer(for: schema, configurations: [configuration(schema: schema, url: url, allowsSave: false)])
            DebugLogger.shared.log(
                .app,
                readOnly == nil ? "Persistent store read-only open also failed" : "Persistent store opened read-only for export",
                level: .recovery
            )
            return .failed(failure, readOnly: readOnly)
        }
    }

    /// In-memory container for scenes that need a `modelContext` while the real store is
    /// unavailable (macOS Settings). Nothing written to it is kept.
    static func makeInMemoryFallback() -> ModelContainer? {
        try? ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    private static func configuration(schema: Schema, url: URL?, allowsSave: Bool) -> ModelConfiguration {
        if let url {
            return ModelConfiguration(schema: schema, url: url, allowsSave: allowsSave)
        }
        return ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, allowsSave: allowsSave)
    }
}

/// Attaches a model container when one exists. In the recovery state there may be none at
/// all (both the real store and the in-memory fallback failed); the recovery screen itself
/// never reads `modelContext`, so the view tree still renders.
struct OptionalModelContainer: ViewModifier {
    let container: ModelContainer?

    func body(content: Content) -> some View {
        if let container {
            content.modelContainer(container)
        } else {
            content
        }
    }
}
