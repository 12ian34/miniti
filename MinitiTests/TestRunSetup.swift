import XCTest

/// Principal class of both test bundles. The test host is the real app and shares its
/// defaults with the install on this Mac, so a person's own engine choices (private mode,
/// transcription or speakers on this device) would otherwise leak into every test that
/// starts a recording. Those keys are cleared for the whole run and put back afterwards.
/// Tests that need them on set them explicitly and restore them themselves.
final class TestRunSetup: NSObject, XCTestObservation {
    static let volatileKeys = [
        "privateMode", "privateMode.restore",
        "onDeviceTranscription", "onDeviceTranscriptionCloudFallback", "onDeviceSpeakerSeparation",
    ]
    private var saved: [String: Any] = [:]

    override init() {
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    func testBundleWillStart(_ testBundle: Bundle) {
        let defaults = UserDefaults.standard
        for key in Self.volatileKeys {
            if let value = defaults.object(forKey: key) { saved[key] = value }
            defaults.removeObject(forKey: key)
        }
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        let defaults = UserDefaults.standard
        for key in Self.volatileKeys {
            if let value = saved[key] { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }
}
