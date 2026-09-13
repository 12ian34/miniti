import Foundation
import SwiftData
import XCTest
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

/// One `URLProtocol` for every network test. Two ways to drive it:
/// - `handler`: the original one-shot `(status, body)` reply used by `ClientAuthTests`.
/// - `script`: richer, per-request responses with headers, or `throw` a `URLError` to
///   simulate timeout, offline, or connection loss. `delay` holds the reply back so a
///   caller can cancel mid-flight.
final class StubURLProtocol: URLProtocol {
    typealias Reply = (status: Int, body: Data, headers: [String: String])

    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var script: ((URLRequest) throws -> Reply)?
    nonisolated(unsafe) static var delay: TimeInterval = 0
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func reset() {
        handler = nil
        script = nil
        delay = 0
        lastRequest = nil
        requests = []
    }

    static func json(_ status: Int, _ body: String) -> Reply {
        (status, Data(body.utf8), ["Content-Type": "application/json"])
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        Self.requests.append(request)
        let work = { [self] in
            if let script = Self.script {
                do {
                    let reply = try script(self.request)
                    self.respond(reply)
                } catch {
                    self.client?.urlProtocol(self, didFailWithError: error)
                }
                return
            }
            let (status, body) = Self.handler?(self.request) ?? (500, Data())
            self.respond((status, body, ["Content-Type": "application/json"]))
        }
        if Self.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.delay, execute: work)
        } else {
            work()
        }
    }

    override func stopLoading() {}

    private func respond(_ reply: Reply) {
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

enum TestSupport {
    /// Ephemeral session routed entirely through `StubURLProtocol`.
    static func stubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.timeoutIntervalForRequest = 5
        return URLSession(configuration: config)
    }

    /// The in-memory SwiftData container every persistence-adjacent test used to build by hand.
    static func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Meeting.self, TranscriptSegment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
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
