import Foundation
import WatchConnectivity

/// The iPhone end of Watch Connectivity. Files from the watch are moved into the durable inbox
/// the moment they arrive (the system deletes them when the callback returns), then handed to
/// `WatchImportService`. Receipts go back as queued user info so the watch can clean up.
@MainActor
final class WatchSessionBridge: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSessionBridge()

    @Published private(set) var isPaired = false
    @Published private(set) var isWatchAppInstalled = false
    @Published private(set) var isActivated = false

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }
    private var lastContext: [String: Any] = [:]

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Settings the watch needs at record time. Cheap to call again; only changes are sent.
    func publishContext(language: String) {
        guard let session, session.activationState == .activated else { return }
        let context = WatchContext(language: language, phoneName: Self.phoneName).dictionary
        if NSDictionary(dictionary: context).isEqual(to: lastContext) { return }
        do {
            try session.updateApplicationContext(context)
            lastContext = context
        } catch {
            DebugLogger.shared.log(.app, "Watch context update failed: \(error.localizedDescription)")
        }
    }

    func send(_ receipt: WatchReceipt) {
        guard let session, session.activationState == .activated, session.isPaired else { return }
        session.transferUserInfo(receipt.dictionary)
    }

    private static var phoneName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "iPhone"
        #endif
    }

    private func refreshFlags(paired: Bool, installed: Bool, activated: Bool) {
        isPaired = paired
        isWatchAppInstalled = installed
        isActivated = activated
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            DebugLogger.shared.log(.app, "Watch session activation failed: \(error.localizedDescription)")
        }
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        let activated = activationState == .activated
        Task { @MainActor in
            refreshFlags(paired: paired, installed: installed, activated: activated)
            WatchImportService.shared.sessionActivated()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // A new watch was paired: activate again for it.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        let activated = session.activationState == .activated
        Task { @MainActor in refreshFlags(paired: paired, installed: installed, activated: activated) }
    }

    #if targetEnvironment(simulator)
    /// Simulator only: the watch sends files as chunked user info because the simulator never
    /// delivers `transferFile`. Chunks are written to the inbox and joined when the last one lands.
    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        guard let userInfo = (try? PropertyListSerialization.propertyList(from: messageData, format: nil)) as? [String: Any] else { return }
        storeSimulatorChunk(userInfo)
    }

    nonisolated private func storeSimulatorChunk(_ userInfo: [String: Any]) {
        guard let transfer = WatchSegmentTransfer(dictionary: userInfo),
              let chunk = userInfo["chunk"] as? Int, let chunks = userInfo["chunks"] as? Int,
              let bytes = userInfo["bytes"] as? Data else { return }
        let inbox = WatchImportService.inboxDirectory(for: transfer.recordingID)
        let name = transfer.isManifest ? "manifest.json" : String(format: "segment-%03d.m4a", transfer.index)
        let parts = inbox.appendingPathComponent("chunks-\(name)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: parts, withIntermediateDirectories: true)
            try bytes.write(to: parts.appendingPathComponent(String(format: "%05d", chunk)), options: .atomic)
            let have = try FileManager.default.contentsOfDirectory(atPath: parts.path).count
            guard have >= chunks else { return }
            var joined = Data()
            for i in 0..<chunks {
                joined.append(try Data(contentsOf: parts.appendingPathComponent(String(format: "%05d", i))))
            }
            let destination = inbox.appendingPathComponent(name)
            try joined.write(to: destination, options: .atomic)
            try? FileManager.default.removeItem(at: parts)
            Task { @MainActor in
                WatchImportService.shared.noteArrival(transfer, at: destination)
            }
        } catch {
            DebugLogger.shared.log(.app, "Watch chunk could not be stored: \(error.localizedDescription)")
        }
    }
    #endif

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // Must move the file before returning: the system removes it afterwards.
        guard let transfer = WatchSegmentTransfer(dictionary: file.metadata) else {
            DebugLogger.shared.log(.app, "Watch file ignored: unknown metadata \(file.metadata ?? [:])")
            return
        }
        let inbox = WatchImportService.inboxDirectory(for: transfer.recordingID)
        let destination = transfer.isManifest
            ? inbox.appendingPathComponent("manifest.json")
            : inbox.appendingPathComponent(String(format: "segment-%03d.m4a", transfer.index))
        do {
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: file.fileURL, to: destination)
        } catch {
            DebugLogger.shared.log(.app, "Watch file could not be stored: \(error.localizedDescription)")
            return
        }
        Task { @MainActor in
            WatchImportService.shared.noteArrival(transfer, at: destination)
        }
    }
}

#if canImport(UIKit)
import UIKit
#endif
