import Foundation
import WatchConnectivity

/// Moves segment files to the iPhone and listens for receipts. Transfers are queued by the
/// system and survive the app being suspended; the watch resends anything undelivered on launch.
@MainActor
final class WatchSessionClient: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var isReachable = false
    @Published private(set) var isCompanionInstalled = false
    @Published private(set) var language = "en"
    @Published private(set) var phoneName = "iPhone"
    /// Latest receipt per recording, for the queue view.
    @Published private(set) var receipts: [UUID: WatchReceipt] = [:]

    private let store: WatchRecordingStore
    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    init(store: WatchRecordingStore = .shared) {
        self.store = store
        super.init()
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
        if let context = WatchContext(dictionary: session.receivedApplicationContext) { apply(context) }
    }

    // MARK: - Sending

    func send(segment: WatchRecordingSegment, of manifest: WatchRecordingManifest) {
        guard let session, session.activationState == .activated else { return }
        let url = store.segmentURL(recordingID: manifest.id, filename: segment.filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard !isQueued(session: session, recordingID: manifest.id, where: { ($0["index"] as? Int) == segment.index && ($0["manifest"] as? Bool) != true }) else { return }
        let meta = WatchSegmentTransfer(
            recordingID: manifest.id, index: segment.index, offset: segment.offset,
            duration: segment.duration, startedAt: manifest.startedAt, language: manifest.language, isManifest: false
        )
        transfer(url, meta: meta, session: session)
    }

    /// `transferFile` is the real path. The simulator never delivers files (Apple documents this),
    /// so a simulator build chunks the file through `transferUserInfo`, which does arrive.
    private func transfer(_ url: URL, meta: WatchSegmentTransfer, session: WCSession) {
        #if targetEnvironment(simulator)
        // Only the small protobuf-backed payloads cross the simulator bridge, so the chunks go
        // as interactive messages while the phone app is reachable. Unsent chunks are retried on
        // the next launch because the manifest keeps `delivered` false until a receipt arrives.
        guard session.isReachable, let data = try? Data(contentsOf: url) else { return }
        let chunkSize = 48 * 1024
        let total = max(1, (data.count + chunkSize - 1) / chunkSize)
        simulatorInFlight.insert(meta.isManifest ? "\(meta.recordingID)/manifest" : "\(meta.recordingID)/\(meta.index)")
        for i in 0..<total {
            let slice = data.subdata(in: i * chunkSize ..< min(data.count, (i + 1) * chunkSize))
            var dict = meta.dictionary
            dict["chunk"] = i
            dict["chunks"] = total
            dict["bytes"] = slice
            guard let payload = try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0) else { continue }
            session.sendMessageData(payload, replyHandler: nil) { error in
                print("[watch] simulator chunk failed: \(error.localizedDescription)")
            }
        }
        #else
        session.transferFile(url, metadata: meta.dictionary)
        #endif
    }

    #if targetEnvironment(simulator)
    private var simulatorInFlight: Set<String> = []
    #endif

    private func isQueued(session: WCSession, recordingID: UUID, where match: ([String: Any]) -> Bool) -> Bool {
        #if targetEnvironment(simulator)
        let key = match(["manifest": true]) ? "\(recordingID)/manifest" : nil
        if let key { return simulatorInFlight.contains(key) }
        return (0..<10_000).contains { match(["index": $0, "manifest": false]) && simulatorInFlight.contains("\(recordingID)/\($0)") }
        #else
        return session.outstandingFileTransfers.contains { t in
            guard let meta = t.file.metadata, (meta["recording_id"] as? String) == recordingID.uuidString else { return false }
            return match(meta)
        }
        #endif
    }

    func sendManifest(_ manifest: WatchRecordingManifest) {
        guard let session, session.activationState == .activated else { return }
        let url = store.manifestURL(for: manifest.id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard !isQueued(session: session, recordingID: manifest.id, where: { ($0["manifest"] as? Bool) == true }) else { return }
        let meta = WatchSegmentTransfer(
            recordingID: manifest.id, index: -1, offset: 0, duration: manifest.duration,
            startedAt: manifest.startedAt, language: manifest.language, isManifest: true
        )
        transfer(url, meta: meta, session: session)
    }

    /// Queues every undelivered file of every stopped recording. Safe to call often.
    /// `force` (the Send again button) retries files a previous attempt still counts as in flight.
    func resendPending(force: Bool = false) {
        #if targetEnvironment(simulator)
        if force { simulatorInFlight.removeAll() }
        #endif
        for manifest in store.loadAll() where manifest.state != .recording {
            for segment in manifest.segments where !segment.delivered {
                send(segment: segment, of: manifest)
            }
            if let receipt = receipts[manifest.id], receipt.status == .ready || receipt.status == .transcribing {
                continue
            }
            sendManifest(manifest)
        }
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let reachable = session.isReachable
        let installed = session.isCompanionAppInstalled
        let context = WatchContext(dictionary: session.receivedApplicationContext)
        Task { @MainActor in
            isReachable = reachable
            isCompanionInstalled = installed
            if let context { apply(context) }
            resendPending()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            isReachable = reachable
            // The phone app just came within reach: anything still waiting goes now. On a
            // device the queued transfers dedupe; on the simulator this is the only retry.
            if reachable { resendPending() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let context = WatchContext(dictionary: applicationContext) else { return }
        Task { @MainActor in apply(context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let receipt = WatchReceipt(dictionary: userInfo) else { return }
        Task { @MainActor in apply(receipt) }
    }

    /// Receipts also arrive as live messages (the simulator's only working channel).
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let receipt = WatchReceipt(dictionary: message) else { return }
        Task { @MainActor in apply(receipt) }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        // Delivery alone is not proof the phone kept the file; the receipt is. Nothing to do here
        // except log failures, which the resend on next activation covers.
        if let error {
            print("[watch] transfer failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func apply(_ context: WatchContext) {
        language = context.language
        phoneName = context.phoneName
    }

    private func apply(_ receipt: WatchReceipt) {
        receipts[receipt.recordingID] = receipt
        #if targetEnvironment(simulator)
        simulatorInFlight = simulatorInFlight.filter { !$0.hasPrefix("\(receipt.recordingID)/") }
        #endif
        store.deleteSegmentFiles(recordingID: receipt.recordingID, indexes: receipt.receivedIndexes)
        if receipt.status == .ready {
            store.delete(receipt.recordingID)
        }
    }
}
