import Combine
import Foundation

/// Ties the recorder and the phone link together for the views.
@MainActor
final class WatchModel: ObservableObject {
    let recorder = WatchRecorder()
    let link = WatchSessionClient()
    @Published private(set) var recordings: [WatchRecordingManifest] = []
    @Published var permissionDenied = false

    private var cancellables: Set<AnyCancellable> = []
    private let store = WatchRecordingStore.shared

    init() {
        recorder.onSegmentClosed = { [weak self] manifest, segment in
            self?.link.send(segment: segment, of: manifest)
            self?.reload()
        }
        recorder.onStopped = { [weak self] _ in
            // Undelivered segments first, then the manifest, in one pass.
            self?.link.resendPending()
            self?.reload()
        }
        link.$receipts.sink { [weak self] _ in self?.reload() }.store(in: &cancellables)
        link.activate()
        recoverInterrupted()
        reload()
    }

    func toggleRecording() {
        if recorder.isRecording {
            recorder.stop()
        } else {
            Task {
                guard await recorder.requestPermission() else {
                    permissionDenied = true
                    return
                }
                await recorder.start(language: link.language)
            }
        }
    }

    func resend() {
        link.resendPending()
    }

    /// The system woke the app for Watch Connectivity (a receipt from the phone). Activation
    /// already happened in `init`; give the session a moment to deliver, then resend leftovers.
    func handleConnectivityWake() async {
        try? await Task.sleep(for: .seconds(2))
        link.resendPending()
        reload()
    }

    func discard(_ id: UUID) {
        store.delete(id)
        reload()
    }

    func status(for manifest: WatchRecordingManifest) -> String {
        if manifest.state == .recording { return "recording" }
        if let receipt = link.receipts[manifest.id] {
            switch receipt.status {
            case .received: return "on \(link.phoneName)"
            case .transcribing: return "transcribing"
            case .waitingForMinutes: return "waiting for minutes"
            case .ready: return "ready"
            case .failed: return receipt.message ?? "failed"
            }
        }
        let delivered = manifest.segments.filter(\.delivered).count
        if delivered == manifest.segments.count, !manifest.segments.isEmpty { return "sent" }
        return link.isCompanionInstalled ? "sending \(delivered)/\(manifest.segments.count)" : "waiting for iPhone"
    }

    private func reload() {
        recordings = store.loadAll()
    }

    /// A manifest still marked recording at launch means the app died mid-meeting. Keep every
    /// file, mark it interrupted, and send what exists.
    private func recoverInterrupted() {
        for var manifest in store.loadAll() where manifest.state == .recording {
            manifest.state = .interrupted
            manifest.endedAt = manifest.endedAt ?? Date()
            for i in manifest.segments.indices where manifest.segments[i].duration == 0 {
                manifest.segments[i].byteCount = store.fileSize(recordingID: manifest.id, filename: manifest.segments[i].filename)
                manifest.segments[i].duration = WatchRecorder.measuredDuration(
                    of: store.segmentURL(recordingID: manifest.id, filename: manifest.segments[i].filename)
                )
            }
            // The file that was open when the app died has no index atom and cannot be read by
            // anything; sending it would only make the phone fail. The earlier files are intact.
            let unreadable = manifest.segments.filter { $0.duration == 0 }
            for segment in unreadable {
                try? FileManager.default.removeItem(at: store.segmentURL(recordingID: manifest.id, filename: segment.filename))
            }
            manifest.segments.removeAll { $0.duration == 0 }
            if manifest.segments.isEmpty {
                store.delete(manifest.id)
                continue
            }
            store.save(manifest)
        }
        link.resendPending()
    }
}
