import Foundation
import SwiftData
import XCTest
import AVFoundation
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

/// A session retains its script context, so reset cannot redirect an older request to
/// another test. Every request snapshots its response script and delay before scheduling.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Reply = (status: Int, body: Data, headers: [String: String])

    final class Context: @unchecked Sendable {
        let id = UUID().uuidString
        private let lock = NSLock()
        private var storedHandler: ((URLRequest) -> (Int, Data))?
        private var storedScript: ((URLRequest) throws -> Reply)?
        private var storedDelay: TimeInterval = 0
        private var captured: [URLRequest] = []
        private var capturedLast: URLRequest?
        private var storedGate: ResponseGate?
        var gate: ResponseGate? {
            get { lock.withLock { storedGate } }
            set { lock.withLock { storedGate = newValue } }
        }
        var lastRequest: URLRequest? {
            get { lock.withLock { capturedLast } }
            set { lock.withLock { capturedLast = newValue } }
        }

        var handler: ((URLRequest) -> (Int, Data))? {
            get { lock.withLock { storedHandler } }
            set { lock.withLock { storedHandler = newValue } }
        }
        var script: ((URLRequest) throws -> Reply)? {
            get { lock.withLock { storedScript } }
            set { lock.withLock { storedScript = newValue } }
        }
        var delay: TimeInterval {
            get { lock.withLock { storedDelay } }
            set { lock.withLock { storedDelay = newValue } }
        }
        var requests: [URLRequest] {
            get { lock.withLock { captured } }
            set { lock.withLock { captured = newValue } }
        }

        fileprivate func capture(_ request: URLRequest) -> (TimeInterval, () throws -> Reply) {
            lock.withLock {
                captured.append(request)
                capturedLast = request
                let script = storedScript
                let handler = storedHandler
                return (storedDelay, {
                    if let script { return try script(request) }
                    let (status, body) = handler?(request) ?? (500, Data())
                    return (status, body, ["Content-Type": "application/json"])
                })
            }
        }
    }

    /// Explicit response suspension for cancellation and authority-race fixtures.
    final class ResponseGate: @unchecked Sendable {
        private let lock = NSLock()
        private var pending: [DispatchWorkItem] = []
        private var released = false
        var pendingCount: Int { lock.withLock { pending.count } }
        fileprivate func hold(_ work: DispatchWorkItem) {
            let run = lock.withLock {
                if released { return true }
                pending.append(work)
                return false
            }
            if run { DispatchQueue.global().async(execute: work) }
        }
        func release() {
            let work = lock.withLock {
                released = true
                let work = pending
                pending.removeAll()
                return work
            }
            for item in work { DispatchQueue.global().async(execute: item) }
        }
    }

    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var active = Context()
    nonisolated(unsafe) private static var contexts: [String: Context] = [:]
    static var context: Context { registryLock.withLock { active } }
    static var handler: ((URLRequest) -> (Int, Data))? {
        get { context.handler }
        set { context.handler = newValue }
    }
    static var script: ((URLRequest) throws -> Reply)? {
        get { context.script }
        set { context.script = newValue }
    }
    static var delay: TimeInterval {
        get { context.delay }
        set { context.delay = newValue }
    }
    static var requests: [URLRequest] {
        get { context.requests }
        set { context.requests = newValue }
    }
    static var lastRequest: URLRequest? {
        get { context.lastRequest }
        set { context.lastRequest = newValue }
    }

    static func reset() { registryLock.withLock { active = Context() } }
    static func configure(_ config: URLSessionConfiguration, context: Context) {
        registryLock.withLock { contexts[context.id] = context }
        config.protocolClasses = [StubURLProtocol.self]
        config.httpAdditionalHeaders = ["X-Miniti-Test-Context": context.id]
    }

    static func json(_ status: Int, _ body: String) -> Reply {
        (status, Data(body.utf8), ["Content-Type": "application/json"])
    }

    private let deliveryLock = NSRecursiveLock()
    private var stopped = false
    private var work: DispatchWorkItem?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: "X-Miniti-Test-Context"),
              let context = Self.registryLock.withLock({ Self.contexts[id] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let (delay, reply) = context.capture(request)
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.deliveryLock.lock(); defer { self.deliveryLock.unlock() }
            guard !self.stopped else { return }
            do { self.respond(try reply()) }
            catch { self.client?.urlProtocol(self, didFailWithError: error) }
            self.work = nil
        }
        deliveryLock.lock()
        if stopped { item.cancel() }
        else { work = item }
        deliveryLock.unlock()
        if let gate = context.gate { gate.hold(item) }
        else { DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: item) }
    }

    override func stopLoading() {
        deliveryLock.lock(); defer { deliveryLock.unlock() }
        stopped = true
        work?.cancel()
        work = nil
    }

    private func respond(_ reply: Reply) {
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        guard !stopped else { return }
        client?.urlProtocol(self, didLoad: reply.body)
        guard !stopped else { return }
        client?.urlProtocolDidFinishLoading(self)
    }
}

enum TestSupport {
    /// Test-only blocking gates run on a GCD worker, never the cooperative executor.
    static func waitForSignal(_ signal: DispatchSemaphore) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: signal.wait(timeout: .now() + 3) == .success)
            }
        }
    }

    /// Ephemeral session routed entirely through `StubURLProtocol`.
    static func stubbedSession(context: StubURLProtocol.Context = StubURLProtocol.context) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        StubURLProtocol.configure(config, context: context)
        config.timeoutIntervalForRequest = 5
        return URLSession(configuration: config)
    }

    /// The in-memory SwiftData container every persistence-adjacent test used to build by hand.
    static func makeInMemoryContainer() throws -> ModelContainer {
        retain(try ModelContainer(
            for: Meeting.self, TranscriptSegment.self, MeetingTombstone.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        ))
    }

    /// Test containers live for the whole process. Work a finished test left behind (the
    /// end-of-meeting naming pass, a delayed save) can still hold a model from its container;
    /// once that container is released, SwiftData aborts the host with "destroyed by calling
    /// ModelContext.reset" and the bundle reports a partial count with 0 failures (CI runs on
    /// 2026-10-19, 10-22 and 10-27, never seen locally). Keeping the container alive turns that
    /// straggler into a harmless write to a store nobody reads.
    nonisolated(unsafe) private static var retainedContainers: [ModelContainer] = []
    private static let retainLock = NSLock()
    @discardableResult
    static func retain(_ container: ModelContainer) -> ModelContainer {
        retainLock.lock()
        retainedContainers.append(container)
        retainLock.unlock()
        return container
    }

    /// Stored credentials for an already-enrolled installation (no Secure Enclave in tests).
    static func enrolledCredentials(accessToken: String = "tok", refreshToken: String = "mrt_x", acknowledged: Bool = true) -> ClientAuthCredentials {
        ClientAuthCredentials(
            installationKey: InstallationKey.generate(preferSecureEnclave: false).stored,
            recoveryKey: ClientAuthCrypto.generateRecoveryKey(),
            accountID: "acct_test",
            accessToken: accessToken,
            accessExpiresAt: Int64(Date().timeIntervalSince1970) + 3600,
            refreshToken: refreshToken,
            deviceCap: 5,
            enrolledAt: "2026-09-06T00:00:00Z",
            enrollmentPath: "migrate",
            recoveryKeyAcknowledged: acknowledged
        )
    }

    static let testDeviceID = "550e8400-e29b-41d4-a716-446655440000"

    /// An enrolled manager whose every request goes through the stub.
    static func enrolledAuthManager(session: URLSession, credentials: ClientAuthCredentials? = nil) -> ClientAuthManager {
        ClientAuthManager(
            store: InMemoryClientAuthStore(credentials ?? enrolledCredentials()),
            baseURL: MinitiAPIService.baseURL,
            session: session,
            deviceIDProvider: { testDeviceID }
        )
    }

    /// A manager with no account at all.
    static func unenrolledAuthManager(session: URLSession) -> ClientAuthManager {
        ClientAuthManager(
            store: InMemoryClientAuthStore(nil),
            baseURL: MinitiAPIService.baseURL,
            session: session,
            deviceIDProvider: { testDeviceID }
        )
    }

    /// Body bytes of a request whether it carried `httpBody` or a stream (proof-bearing writes).
    static func bodyData(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }

    /// Poll on the main actor until `condition` holds or `timeout` elapses.
    @MainActor
    static func waitUntil(timeout: TimeInterval = 5, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("timed out after \(timeout)s waiting for condition")
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

/// Facts about the process the tests run in. GitHub's runner never grants the host the
/// microphone, and that does not show up as an environment variable inside the host (xcodebuild
/// does not pass the shell's `CI` through), so the tests ask the system.
enum TestHost {
    /// True only when the host may actually read the microphone. The runner has a default
    /// input device that delivers nothing, so the device list alone is not enough.
    static var microphoneIsAuthorized: Bool {
        ProcessInfo.processInfo.environment["MINITI_HARDWARE_TESTS"] == "1"
            && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
}
