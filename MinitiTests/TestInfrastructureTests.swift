import Foundation
import XCTest
import SwiftData
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

final class TestInfrastructureTests: XCTestCase {
    func testHostUsesIsolatedBundleBeforeTestsStart() {
        #if IOS_TEST_TARGET
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.miniti.mobile.testhost")
        #else
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.miniti.app.testhost")
        #endif
        XCTAssertTrue(AppState.isRunningUnderXCTest)
    }

    @MainActor
    func testLaunchStoreIsEmptyAndIndependentOnEachOpen() throws {
        let first = try XCTUnwrap(PersistentStore.open().container)
        let context = first.mainContext
        context.insert(Meeting(title: "isolated host"))
        try context.save()
        let second = try XCTUnwrap(PersistentStore.open().container)
        XCTAssertEqual(try second.mainContext.fetchCount(FetchDescriptor<Meeting>()), 0)
    }

    @MainActor
    func testResponseUsesCapturedScriptAfterContextReset() async throws {
        StubURLProtocol.reset()
        let oldContext = StubURLProtocol.context
        let gate = StubURLProtocol.ResponseGate()
        oldContext.gate = gate
        oldContext.script = { _ in StubURLProtocol.json(200, "original") }
        let oldSession = TestSupport.stubbedSession(context: oldContext)
        defer { oldSession.invalidateAndCancel() }
        let url = URL(string: "https://fixture.invalid/test")!
        let oldRequest = Task { try await oldSession.data(from: url) }
        try await TestSupport.waitUntil { gate.pendingCount == 1 }

        oldContext.script = { _ in XCTFail("must use the captured script"); return StubURLProtocol.json(500, "changed") }
        StubURLProtocol.reset()
        StubURLProtocol.script = { _ in StubURLProtocol.json(200, "new test") }
        let newSession = TestSupport.stubbedSession()
        defer { newSession.invalidateAndCancel() }
        let (newData, _) = try await newSession.data(from: url)
        gate.release()
        let (oldData, _) = try await oldRequest.value
        XCTAssertEqual(String(data: oldData, encoding: .utf8), "original")
        XCTAssertEqual(String(data: newData, encoding: .utf8), "new test")
        XCTAssertEqual(oldContext.requests.count, 1)
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }

    @MainActor
    func testCancellationDiscardsSuspendedReply() async throws {
        let context = StubURLProtocol.Context()
        let gate = StubURLProtocol.ResponseGate()
        context.gate = gate
        context.script = { _ in
            XCTFail("cancelled protocol must not execute a deferred response")
            return StubURLProtocol.json(200, "late")
        }
        let session = TestSupport.stubbedSession(context: context)
        defer { session.invalidateAndCancel() }
        let request = Task { try await session.data(from: URL(string: "https://fixture.invalid/cancel")!) }
        try await TestSupport.waitUntil { gate.pendingCount == 1 }
        request.cancel()
        do {
            _ = try await request.value
            XCTFail("cancelled request must fail")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .cancelled)
        }
        gate.release()
        XCTAssertEqual(context.requests.count, 1)
    }
}
