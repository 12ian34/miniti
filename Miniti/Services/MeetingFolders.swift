import Foundation
import CryptoKit
import Combine

/// Content, never diagnostic metadata. The catalog is separate from meetings so empty
/// custom folders sync too. Deleted IDs remain tombstones; membership resolves to Unfiled.
struct MeetingFolder: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var description: String = ""
    var titleRule: String = ""
    var deleted: Bool = false
    var localOnly: Bool = false
}

struct FolderCatalog: Codable, Equatable {
    var revision: Int = 0
    var folders: [MeetingFolder] = []
}

@MainActor
final class MeetingFolderStore: ObservableObject {
    struct Scope: Codable, Equatable {
        var base = FolderCatalog()
        var folders: [MeetingFolder] = []
        var dirty: Set<UUID> = []
        var conflicts: [MeetingFolder] = []
    }
    @Published private(set) var scope = Scope()
    @Published private(set) var issue: String?
    private var scopes: [String: Scope] = [:]
    private(set) var owner = "local"
    private let url: URL?
    private var readable = true
    private var syncing = false
    private var generation = UUID()
    var active: [MeetingFolder] { scope.folders.filter { !$0.deleted }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }

    init(url: URL?) {
        self.url = url
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        do { scopes = try JSONDecoder().decode([String: Scope].self, from: Data(contentsOf: url)) }
        catch { readable = false; issue = "Folders could not be read. The saved file has been kept." }
        scope = scopes[owner] ?? Scope()
    }

    func selectOwner(_ accountID: String?) {
        let next = accountID.map { "account:" + $0 } ?? "local"
        guard next != owner else { return }
        generation = UUID(); owner = next
        scope = scopes[next] ?? Scope()
        if readable { issue = nil }
    }

    func removeOwner(_ accountID: String) -> Bool {
        guard readable else { return false }
        let key = "account:" + accountID
        var all = scopes; all.removeValue(forKey: key)
        do {
            if let url { try JSONEncoder().encode(all).write(to: url, options: .atomic) }
            scopes = all
            if owner == key { generation = UUID(); scope = Scope() }
            return true
        } catch { issue = "The account was deleted, but its local folder catalog could not be removed."; return false }
    }

    func folder(_ id: UUID?) -> MeetingFolder? {
        guard let id else { return nil }
        return scope.folders.first { $0.id == id && !$0.deleted }
    }

    @discardableResult
    func edit(_ folder: MeetingFolder) -> Bool {
        guard readable else { return false }
        let name = folder.name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Match JavaScript's wire length limits, including emoji and combined characters.
        guard !name.isEmpty, name.utf16.count <= 80, folder.description.utf16.count <= 500, folder.titleRule.utf16.count <= 120 else {
            issue = "Use a name of 1 to 80 characters, a description up to 500 and a title rule up to 120."; return false
        }
        guard !scope.folders.contains(where: { $0.id == folder.id && $0.deleted }) else {
            issue = "This folder was deleted. Create a new folder to use it again."; return false
        }
        guard scope.folders.contains(where: { $0.id == folder.id }) || (active.count < 200 && scope.folders.count < 1000) else {
            issue = "The folder limit has been reached."; return false
        }
        var next = scope
        var folder = folder; folder.name = name
        if folder.deleted { folder.name = "Deleted folder"; folder.description = ""; folder.titleRule = "" }
        next.folders.removeAll { $0.id == folder.id }; next.folders.append(folder)
        next.dirty.insert(folder.id)
        return save(next)
    }

    func resolveConflict(_ id: UUID, keepMine: Bool) {
        guard let mine = scope.conflicts.first(where: { $0.id == id }) else { return }
        var next = scope; next.conflicts.removeAll { $0.id == id }
        if keepMine {
            // A remote deletion cannot be undone by replay. A deliberate new folder gets a new ID.
            var copy = mine
            if !next.folders.contains(where: { $0.id == id && !$0.deleted }) {
                guard active.count < 200, next.folders.count < 1000 else {
                    issue = "The folder limit has been reached. Your version has been kept for later."
                    return
                }
                if next.folders.contains(where: { $0.id == id && $0.deleted }) {
                    copy.id = UUID()
                }
            }
            next.folders.removeAll { $0.id == copy.id }; next.folders.append(copy); next.dirty.insert(copy.id)
        }
        _ = save(next)
    }

    @discardableResult
    private func save(_ next: Scope) -> Bool {
        guard readable else { return false }
        guard next != scope else {
            if issue != nil { issue = nil }
            return true
        }
        var all = scopes; all[owner] = next
        do {
            if let url {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(all).write(to: url, options: .atomic)
            }
            scopes = all; scope = next; issue = nil; return true
        } catch { issue = "Folders could not be saved. Try again."; return false }
    }

    /// Three-way merge, per folder. Different folders merge; conflicting edits stay visible
    /// until the user chooses. No timestamps or device clocks decide ownership.
    func merge(_ remote: FolderCatalog) -> Bool {
        guard remote.folders.count <= 1000, Set(remote.folders.map(\.id)).count == remote.folders.count else { return false }
        var next = scope
        let base = Dictionary(uniqueKeysWithValues: next.base.folders.map { ($0.id, $0) })
        let local = Dictionary(uniqueKeysWithValues: next.folders.map { ($0.id, $0) })
        var result = Dictionary(uniqueKeysWithValues: remote.folders.map { ($0.id, $0) })
        let remoteIDs = Set(remote.folders.map(\.id))
        for folder in next.folders {
            if folder.localOnly { result[folder.id] = folder }
            else if !remoteIDs.contains(folder.id) {
                // Absence is not deletion. A purged cloud copy must not erase local folders.
                result[folder.id] = folder; next.dirty.insert(folder.id)
            }
        }
        for id in next.dirty {
            guard let mine = local[id], !mine.localOnly else { continue }
            if !remoteIDs.contains(id) { result[id] = mine; continue }
            if result[id] == mine { next.dirty.remove(id) }
            else if result[id] == base[id] { result[id] = mine }
            else {
                next.conflicts.removeAll { $0.id == id }; next.conflicts.append(mine)
                next.dirty.remove(id)
            }
        }
        // Concurrent additions must not leave a permanently unuploadable catalog.
        // Keep remote history, and retain excess local additions for explicit resolution.
        var sharedCount = remote.folders.count
        var activeSharedCount = remote.folders.filter { !$0.deleted }.count
        for folder in result.values.sorted(by: { $0.id.uuidString < $1.id.uuidString })
            where !folder.localOnly && !remoteIDs.contains(folder.id) {
            if sharedCount >= 1000 || (!folder.deleted && activeSharedCount >= 200) {
                next.conflicts.removeAll { $0.id == folder.id }
                next.conflicts.append(folder)
                result.removeValue(forKey: folder.id)
                next.dirty.remove(folder.id)
            } else {
                sharedCount += 1
                if !folder.deleted { activeSharedCount += 1 }
            }
        }
        next.base = remote
        next.folders = result.values.sorted { $0.id.uuidString < $1.id.uuidString }
        return save(next)
    }

    var sleep: (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }

    func sync(allowed: () -> Bool, read: () async throws -> FolderCatalog,
              write: (FolderCatalog) async throws -> FolderCatalog) async {
        guard readable, !syncing, owner != "local", allowed() else { return }
        syncing = true; defer { syncing = false }
        let token = generation
        for attempt in 0..<3 {
            do {
                let remote = try await read()
                guard generation == token, allowed(), merge(remote), scope.folders.contains(where: { scope.dirty.contains($0.id) && !$0.localOnly }) else { return }
                let sent = FolderCatalog(revision: scope.base.revision, folders: scope.folders.filter { !$0.localOnly })
                let accepted = try await write(sent)
                guard generation == token, allowed() else { return }
                // Treat edits made while PUT was in flight as a new dirty generation.
                var next = scope
                for folder in sent.folders where next.folders.first(where: { $0.id == folder.id }) == folder {
                    next.dirty.remove(folder.id)
                }
                next.base = accepted
                _ = save(next)
                return
            } catch {
                guard generation == token, allowed() else { return }
                let retryable: Bool
                switch error {
                case CloudSyncError.busy, CloudSyncError.server(code: "folder_conflict", status: 409): retryable = true
                default: retryable = false
                }
                if retryable {
                    guard attempt < 2 else { return } // next foreground/sync pass retries quietly
                    do { try await sleep(Double(attempt + 1)) } catch { return }
                    guard generation == token, allowed() else { return }
                } else {
                    issue = "Folder sync is waiting. Your local folders are saved. Retry from History."
                    return
                }
            }
        }
    }
}

/// Bounded local matching. No transcript scan, network request or new model permission.
/// Exact title rules outrank word evidence. A tie stays Unfiled.
enum FolderMatcher {
    /// Broad purposes, rather than one folder per recurring title. Only title evidence
    /// selects a built-in group; incidental summary vocabulary cannot create one.
    enum Category: String, CaseIterable {
        case team, customers, product, hiring, planning, partnerships, learning

        var name: String {
            switch self {
            case .team: "Team"
            case .customers: "Customers"
            case .product: "Product & engineering"
            case .hiring: "Hiring"
            case .planning: "Business planning"
            case .partnerships: "Partners & suppliers"
            case .learning: "Learning"
            }
        }
        var description: String {
            switch self {
            case .team: "Team catch-ups, standups and one-to-ones."
            case .customers: "Customer conversations, sales calls and demos."
            case .product: "Product, design and engineering work."
            case .hiring: "Interviews, recruitment and hiring decisions."
            case .planning: "Strategy, budgets and business planning."
            case .partnerships: "Work with partners, vendors and suppliers."
            case .learning: "Training, workshops and shared learning."
            }
        }
        private var phrases: [String] {
            switch self {
            case .team: ["standup", "standups", "stand up", "team sync", "team meeting", "team catch up", "all hands", "one to one", "one on one", "1 1", "1on1",
                         "offsite", "town hall"]
            case .customers: ["customer", "customers", "client", "clients", "prospect", "prospects", "sales", "demo", "discovery",
                              "renewal", "account review", "pilot"]
            case .product: ["product", "engineering", "design", "sprint", "roadmap", "bug triage",
                            "spec", "architecture", "ux", "user research", "backlog"]
            case .hiring: ["interview", "interviews", "recruiting", "recruitment", "hiring", "candidate", "candidates", "screening"]
            case .planning: ["strategy", "planning", "budget", "finance", "operations", "leadership", "board",
                             "okr", "okrs", "forecast", "investor", "investors", "fundraising"]
            case .partnerships: ["partner", "partners", "partnership", "partnerships", "vendor", "vendors", "supplier", "suppliers", "agency", "procurement"]
            case .learning: ["training", "workshop", "webinar", "learning", "lunch and learn", "meetup"]
            }
        }
        func id(owner: String, localOnly: Bool) -> UUID {
            FolderMatcher.automaticID(title: "category-v1:" + rawValue, owner: owner + (localOnly ? ":local" : ""))
        }
        func folder(owner: String, localOnly: Bool) -> MeetingFolder {
            .init(id: id(owner: owner, localOnly: localOnly), name: name, description: description, localOnly: localOnly)
        }
        static func matching(title: String) -> Self? {
            let normalized = " " + title.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ") + " "
            let matches = allCases.filter { category in
                category.phrases.contains { normalized.contains(" " + $0 + " ") }
            }
            // Planning is a fallback: "sprint planning" belongs with product work.
            let specific = matches.filter { $0 != .planning }
            return specific.count == 1 ? specific[0] : (specific.isEmpty && matches.contains(.planning) ? .planning : nil)
        }
        /// Summary evidence for a broad group: at least three different terms of one
        /// category (singular and plural count once), two clear of any other category.
        /// Callers use this only for folders that already exist, so summary vocabulary
        /// can never create a folder.
        static func matching(summary: String?) -> Self? {
            guard let summary, !summary.isEmpty else { return nil }
            let normalized = " " + String(summary.prefix(4000)).lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ") + " "
            let scores = allCases.map { category -> (Self, Int) in
                let stems = Set(category.phrases.filter { normalized.contains(" " + $0 + " ") }.map { phrase in
                    phrase.hasSuffix("s") && phrase.count > 3 ? String(phrase.dropLast()) : phrase
                })
                return (category, stems.count)
            }.sorted { $0.1 > $1.1 }
            guard let best = scores.first, best.1 >= 3, best.1 >= (scores.dropFirst().first?.1 ?? 0) + 2 else { return nil }
            return best.0
        }
        static func identifying(_ folder: MeetingFolder, owner: String) -> Self? {
            allCases.first { $0.id(owner: owner, localOnly: folder.localOnly) == folder.id }
        }
    }

    static func words(_ text: String) -> Set<String> {
        let ignored: Set<String> = ["the", "and", "with", "meeting", "weekly", "monthly", "call", "notes", "review", "sync", "for", "our", "your", "this", "that"]
        return Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
            .filter { $0.count >= 3 && !ignored.contains($0) })
    }
    enum Match {
        case none, folder(UUID), ambiguous
    }
    static func match(title: String, summary: String?, folders: [MeetingFolder]) -> UUID? {
        if case .folder(let id) = resolve(title: title, summary: summary, folders: folders) { return id }
        return nil
    }
    struct Prepared {
        struct Entry {
            let id: UUID
            let rule: String
            let name: Set<String>
            let words: Set<String>
        }
        let entries: [Entry]
        init(_ folders: [MeetingFolder]) {
            entries = folders.prefix(200).filter { !$0.deleted }.map {
                Entry(id: $0.id, rule: $0.titleRule, name: FolderMatcher.words($0.name),
                      words: FolderMatcher.words($0.name + " " + $0.description))
            }
        }
        func resolve(title: String, summary: String?) -> Match {
            let evidence = FolderMatcher.words(title + " " + String((summary ?? "").prefix(4000)))
            let scores = entries.compactMap { folder -> (UUID, Int)? in
                if !folder.rule.isEmpty, title.range(of: folder.rule, options: [.caseInsensitive, .literal]) != nil { return (folder.id, 100) }
                let shared = evidence.intersection(folder.words).count
                let completeName = !folder.name.isEmpty && folder.name.isSubset(of: FolderMatcher.words(title))
                let score = shared >= 2 || completeName ? shared + (completeName ? 3 : 0) : 0
                return score > 0 ? (folder.id, score) : nil
            }.sorted { $0.1 > $1.1 }
            guard let best = scores.first else { return .none }
            guard scores.count == 1 || best.1 >= scores[1].1 + 2 else { return .ambiguous }
            return .folder(best.0)
        }
    }
    static func resolve(title: String, summary: String?, folders: [MeetingFolder]) -> Match {
        Prepared(folders).resolve(title: title, summary: summary)
    }
    /// Keys that identify the same recurring meeting: its calendar series and its title
    /// with dates and numbers removed. Used so a meeting follows the folder of earlier
    /// meetings in the same series, including folders chosen by hand.
    static func seriesKeys(calendarEventID: String?, title: String) -> [String] {
        var keys: [String] = []
        if let id = calendarEventID?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            // Google recurring instances are "<series>_<start>".
            let series = id.split(separator: "_", maxSplits: 1).first.map(String.init) ?? id
            keys.append("event:" + series)
        }
        let months: Set<String> = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec",
                                   "january", "february", "march", "april", "june", "july", "august", "september", "october", "november", "december"]
        let tokens = title.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
            .filter { token in !token.allSatisfy(\.isNumber) && !months.contains(token) }
        let generic: Set<String> = ["meeting", "meetings", "call", "untitled", "new", "recording", "notes", "chat", "watch",
                                    "intro", "demo", "catch", "interview", "weekly", "monthly", "daily", "sync", "standup",
                                    "check", "quick", "follow", "the", "and", "with", "team", "review", "update", "discussion"]
        if tokens.contains(where: { $0.count >= 3 && !generic.contains($0) }) {
            keys.append("title:" + tokens.joined(separator: " "))
        }
        return keys
    }
    static func automaticID(title: String, owner: String) -> UUID {
        let digest = SHA256.hash(data: Data((owner + ":" + title.lowercased()).utf8))
        let hex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        let chars = Array(hex)
        let formatted = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(chars[$0]) }.joined(separator: "-")
        return UUID(uuidString: formatted)!
    }
}
