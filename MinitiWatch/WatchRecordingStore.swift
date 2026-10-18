import Foundation

/// Recordings live under Documents/recordings/<id>/ as one manifest.json plus the audio
/// segments. Nothing is deleted until the phone says it has the files.
final class WatchRecordingStore: @unchecked Sendable {
    static let shared = WatchRecordingStore()

    private let root: URL
    private let lock = NSLock()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(root: URL? = nil) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.root = root ?? documents.appendingPathComponent("recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    func directory(for id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func segmentURL(recordingID: UUID, filename: String) -> URL {
        directory(for: recordingID).appendingPathComponent(filename)
    }

    func manifestURL(for id: UUID) -> URL {
        directory(for: id).appendingPathComponent("manifest.json")
    }

    func save(_ manifest: WatchRecordingManifest) {
        lock.lock(); defer { lock.unlock() }
        let dir = directory(for: manifest.id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(manifest) else { return }
        try? data.write(to: manifestURL(for: manifest.id), options: .atomic)
    }

    func load(_ id: UUID) -> WatchRecordingManifest? {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: manifestURL(for: id)) else { return nil }
        return try? decoder.decode(WatchRecordingManifest.self, from: data)
    }

    func loadAll() -> [WatchRecordingManifest] {
        lock.lock(); defer { lock.unlock() }
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { dir -> WatchRecordingManifest? in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")) else { return nil }
            return try? decoder.decode(WatchRecordingManifest.self, from: data)
        }
        .sorted { $0.startedAt > $1.startedAt }
    }

    func deleteSegmentFiles(recordingID: UUID, indexes: [Int]) {
        guard var manifest = load(recordingID) else { return }
        for index in indexes {
            guard let i = manifest.segments.firstIndex(where: { $0.index == index }) else { continue }
            try? FileManager.default.removeItem(at: segmentURL(recordingID: recordingID, filename: manifest.segments[i].filename))
            manifest.segments[i].delivered = true
        }
        save(manifest)
    }

    func delete(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: directory(for: id))
    }

    func fileSize(recordingID: UUID, filename: String) -> Int {
        let url = segmentURL(recordingID: recordingID, filename: filename)
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.intValue ?? 0
    }
}
