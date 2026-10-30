import XCTest
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

@MainActor
final class PurchaseReturnTests: XCTestCase {
    private let id = UUID()
    private func url(_ id: UUID) -> URL { URL(string: "miniti-billing://return?checkout_id=\(id.uuidString)")! }

    func testReturnRejectsExtraParametersAndForeignRoutes() {
        XCTAssertEqual(PurchaseReturnController.checkoutID(from: url(id)), id)
        for value in ["https://return?checkout_id=\(id)", "miniti-billing://return/else?checkout_id=\(id)",
                      "miniti-billing://return?checkout_id=\(id)&account=other", "miniti-billing://return?checkout_id=bad"] {
            XCTAssertNil(PurchaseReturnController.checkoutID(from: URL(string: value)!))
        }
    }

    func testDuplicateReturnCoalescesAndOldAccountAnswerCannotBecomeReady() async {
        let controller = PurchaseReturnController()
        var owner: String? = "a:1"
        controller.authority = { owner }
        var held: CheckedContinuation<String, Error>?
        var calls = 0
        controller.check = { _ in calls += 1; return try await withCheckedThrowingContinuation { held = $0 } }
        var applied = 0
        controller.refreshEntitlement = { _ in applied += 1 }
        controller.receive(url(id))
        while held == nil { await Task.yield() }
        controller.receive(url(id))
        XCTAssertEqual(calls, 1)
        owner = "b:2"
        controller.cancelForIdentityChange()
        held?.resume(returning: "ready")
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(controller.state, .signIn)
        XCTAssertEqual(applied, 0)
    }

    func testReadyRequiresEntitlementRefreshAndThrottleWaitIsRespected() async {
        let controller = PurchaseReturnController()
        controller.authority = { "a:1" }
        var calls = 0
        var clock = Date()
        controller.now = { clock }
        controller.check = { _ in calls += 1; throw PurchaseConfirmationError.throttled(60) }
        controller.receive(url(id))
        while controller.state == .checking { await Task.yield() }
        controller.retry()
        XCTAssertEqual(calls, 1)
        clock.addTimeInterval(61)
        var refreshed = false
        controller.check = { _ in calls += 1; return "ready" }
        controller.refreshEntitlement = { owner in XCTAssertEqual(owner, "a:1"); refreshed = true }
        controller.retry()
        while controller.state == .checking { await Task.yield() }
        XCTAssertEqual(controller.state, .ready)
        XCTAssertTrue(refreshed)
        XCTAssertEqual(calls, 2)
    }

    func testTimeoutDoesNotApplyALateReadyAnswer() async {
        let controller = PurchaseReturnController()
        controller.authority = { "a:1" }
        controller.maximumWait = 0.02
        var held: CheckedContinuation<String, Error>?
        controller.check = { _ in try await withCheckedThrowingContinuation { held = $0 } }
        var applied = false
        controller.refreshEntitlement = { _ in applied = true }
        controller.receive(url(id))
        while controller.state == .checking { await Task.yield() }
        guard case .retry = controller.state else { return XCTFail("Expected bounded timeout") }
        held?.resume(returning: "ready")
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(applied)
    }
}
