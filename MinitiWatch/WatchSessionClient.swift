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
        let alreadyQueued = session.outstandingFileTransfers.contains { transfer in
            transfer.file.fileURL.lastPathComponent == segment.filename
                && (transfer.file.metadata?["recording_id"] as? String) == manifest.id.uuidString
        }
        guard !alreadyQueued else { return }
        let meta = WatchSegmentTransfer(
            recordingID: manifest.id, index: segment.index, offset: segment.offset,
            duration: segment.duration, startedAt: manifest.startedAt, language: manifest.language, isManifest: false
        )
        session.transferFile(url, metadata: meta.dictionary)
    }

    func sendManifest(_ manifest: WatchRecordingManifest) {
        guard let session, session.activationState == .activated else { return }
        let url = store.manifestURL(for: manifest.id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let alreadyQueued = session.outstandingFileTransfers.contains { transfer in
            (transfer.file.metadata?["manifest"] as? Bool) == true
                && (transfer.file.metadata?["recording_id"] as? String) == manifest.id.uuidString
        }
        guard !alreadyQueued else { return }
        let meta = WatchSegmentTransfer(
            recordingID: manifest.id, index: -1, offset: 0, duration: manifest.duration,
            startedAt: manifest.startedAt, language: manifest.language, isManifest: true
        )
        session.transferFile(url, metadata: meta.dictionary)
    }

    /// Queues every undelivered file of every stopped recording. Safe to call often.
    func resendPending() {
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
        Task { @MainActor in isReachable = reachable }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let context = WatchContext(dictionary: applicationContext) else { return }
        Task { @MainActor in apply(context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let receipt = WatchReceipt(dictionary: userInfo) else { return }
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
        store.deleteSegmentFiles(recordingID: receipt.recordingID, indexes: receipt.receivedIndexes)
        if receipt.status == .ready {
            store.delete(receipt.recordingID)
        }
    }
}
