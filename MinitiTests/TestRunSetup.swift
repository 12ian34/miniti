import XCTest

#if !MINITI_TEST_HOST
#error("Build hosted test bundles with the Testing configuration to protect installed app data")
#endif

/// The Testing configuration owns a separate sandbox/defaults domain, process-local
/// credentials and an in-memory launch store. A crash needs no live-state restoration.
final class TestRunSetup: NSObject, XCTestObservation {
    private var domain: String {
        guard let domain = Bundle.main.bundleIdentifier,
              ["com.miniti.app.testhost", "com.miniti.mobile.testhost"].contains(domain) else {
            preconditionFailure("Hosted tests require the Testing configuration")
        }
        return domain
    }

    override init() {
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    func testBundleWillStart(_ testBundle: Bundle) {
        UserDefaults.standard.removePersistentDomain(forName: domain)
    }

    func testCaseWillStart(_ testCase: XCTestCase) {
        // Previous runs and failed tests cannot supply engine choices or API keys.
        UserDefaults.standard.removePersistentDomain(forName: domain)
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        UserDefaults.standard.removePersistentDomain(forName: domain)
    }
}
