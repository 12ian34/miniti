import XCTest

/// Principal class of both test bundles. The test host is the real app and shares its
/// defaults with the install on this Mac (the Debug host is sandboxed too, so it is the same
/// container), so every setting a test writes through a real `AppState` lands in the person's
/// live settings. Two things happen here:
///
/// - the whole defaults domain is captured before the first test and put back after the last
///   one, so nothing a test writes survives the run (2026-10-21: `CloudSyncAppStateTests` ends
///   with the cloud switch off and the person's Mac stayed that way);
/// - the person's own engine choices (private mode, transcription or speakers on this device)
///   are cleared for the run so they do not leak into every test that starts a recording.
///   Tests that need them on set them explicitly.
///
/// A run that crashes restores nothing, as before.
final class TestRunSetup: NSObject, XCTestObservation {
    static let volatileKeys = [
        "privateMode", "privateMode.restore",
        "onDeviceTranscription", "onDeviceTranscriptionCloudFallback", "onDeviceSpeakerSeparation",
    ]
    private var savedDomain: [String: Any]?
    private var domain: String { Bundle.main.bundleIdentifier ?? "com.miniti.app" }

    override init() {
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    func testBundleWillStart(_ testBundle: Bundle) {
        let defaults = UserDefaults.standard
        savedDomain = defaults.persistentDomain(forName: domain) ?? [:]
        for key in Self.volatileKeys {
            defaults.removeObject(forKey: key)
        }
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        guard let savedDomain else { return }
        UserDefaults.standard.setPersistentDomain(savedDomain, forName: domain)
        UserDefaults.standard.synchronize()
    }
}
