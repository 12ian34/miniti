import Foundation
import XCTest
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

/// Roadmap P0.6: every failure class of the managed API path, driven through a stubbed
/// `URLSession` so nothing touches the network. Covers `send()`'s auth handling (bearer,
/// one silent refresh, revocation) and `validateResponse()`'s status mapping.
final class MinitiAPIServiceTransportTests: XCTestCase {
    private var session: URLSession!
    private var auth: ClientAuthManager!
    private var api: MinitiAPIService!
    private let deviceID = TestSupport.testDeviceID

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        session = TestSupport.stubbedSession()
        auth = TestSupport.enrolledAuthManager(session: session)
        api = MinitiAPIService(session: session, auth: auth)
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private static let usageBody = """
    {"minutes_used": 12.5, "minutes_limit": 500, "resets_at": "2026-10-01T00:00:00Z", "tier": "free", "entitlement_via_account": false}
    """

    private func path(_ request: URLRequest) -> String {
        request.url?.path ?? ""
    }

    func testV2StartRenewAndFinishUseTheSharedWireFixture() async throws {
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(ContractFixtures.managedAccounting.utf8)) as? [String: Any])
        let recording = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!
        let startData = try JSONSerialization.data(withJSONObject: fixture["start_response"]!)
        let finishData = try JSONSerialization.data(withJSONObject: fixture["finish_response"]!)
        StubURLProtocol.handler = { request in
            (200, request.url?.path.hasSuffix("/session/end") == true ? finishData : startData)
        }
        let start = try await api.requestSession(deviceId: deviceID, model: "nova-3", recordingID: recording)
        XCTAssertEqual(start.accountingVersion, 2)
        XCTAssertNotNil(start.sessionStartedAt)
        let renewed = try await api.requestSession(deviceId: deviceID, model: "nova-3", recordingID: recording, renewalSessionID: start.sessionId)
        XCTAssertEqual(renewed.sessionId, start.sessionId)
        let finish = try await api.endSession(deviceId: deviceID, sessionId: start.sessionId, durationMinutes: 74, recordingID: recording, durationMS: 4_440_000)
        XCTAssertEqual(finish.minutesUsed, 74)
        for (request, key) in zip(StubURLProtocol.requests, ["start", "renew", "finish"]) {
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: TestSupport.bodyData(of: request)) as? NSDictionary)
            XCTAssertEqual(body, fixture[key] as? NSDictionary)
        }
    }

    func testCloudBusy503IsRetryableRatherThanAConflictOrFailure() async throws {
        StubURLProtocol.script = { _ in
            StubURLProtocol.json(503, #"{"error":"busy"}"#)
        }
        do {
            _ = try await api.manifest()
            XCTFail("expected transient contention")
        } catch let error as CloudSyncError {
            XCTAssertEqual(error, .busy(retryAfter: 2))
        }
    }

    // MARK: Happy path and auth headers

    func testUsageDecodesAndCarriesBearerAndIdentityHeaders() async throws {
        StubURLProtocol.script = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Device-ID"), TestSupport.testDeviceID)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-App-Mode"), "managed")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Platform"), MinitiAPIService.platformHeader)
            return StubURLProtocol.json(200, Self.usageBody)
        }
        let usage = try await api.checkUsage(deviceId: deviceID)
        XCTAssertEqual(usage.minutesUsed, 12.5)
        XCTAssertEqual(usage.tier, "free")
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }

    func testVersionCheckWorksWithoutEnrollmentAndSendsNoBearer() async throws {
        api = MinitiAPIService(session: session, auth: TestSupport.unenrolledAuthManager(session: session))
        StubURLProtocol.script = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return StubURLProtocol.json(200, #"{"latest_version": "2.9.0", "download_url": "https://miniti.app/download"}"#)
        }
        let info = try await api.checkVersion()
        XCTAssertEqual(info.latestVersion, "2.9.0")
    }

    func testBillableRouteWithoutEnrollmentThrowsBeforeAnyRequest() async {
        api = MinitiAPIService(session: session, auth: TestSupport.unenrolledAuthManager(session: session))
        do {
            _ = try await api.checkUsage(deviceId: deviceID)
            XCTFail("expected notEnrolled")
        } catch MinitiAPIService.ServiceError.notEnrolled {
            XCTAssertTrue(StubURLProtocol.requests.isEmpty, "no request may leave the app without an account")
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    // MARK: Status mapping

    func testPaymentRequiredMapsToLimitReachedWithFields() async {
        StubURLProtocol.script = { _ in
            StubURLProtocol.json(402, #"{"error": "limit_reached", "message": "Monthly limit", "minutes_used": 512.5, "resets_at": "2026-10-01T00:00:00Z"}"#)
        }
        do {
            _ = try await api.requestSession(deviceId: deviceID, model: "nova-3")
            XCTFail("expected limitReached")
        } catch MinitiAPIService.ServiceError.limitReached(let used, let resets) {
            XCTAssertEqual(used, 512.5)
            XCTAssertNotNil(resets)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testForbiddenMapsToDeviceDisabledOrAccessDenied() async {
        StubURLProtocol.script = { _ in StubURLProtocol.json(403, #"{"error": "device_disabled", "message": "disabled"}"#) }
        do {
            _ = try await api.checkUsage(deviceId: deviceID)
            XCTFail("expected deviceDisabled")
        } catch MinitiAPIService.ServiceError.deviceDisabled {
        } catch {
            XCTFail("unexpected \(error)")
        }

        StubURLProtocol.script = { _ in StubURLProtocol.json(403, #"{"error": "forbidden"}"#) }
        do {
            _ = try await api.checkUsage(deviceId: deviceID)
            XCTFail("expected serverError")
        } catch MinitiAPIService.ServiceError.serverError(let message) {
            XCTAssertEqual(message, "Access denied")
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testTooManyRequestsMapsToRateLimited() async {
        StubURLProtocol.script = { _ in (429, Data(), ["Retry-After": "7"]) }
        do {
            _ = try await api.checkUsage(deviceId: deviceID)
            XCTFail("expected rateLimited")
        } catch MinitiAPIService.ServiceError.rateLimited {
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testServerErrorsCarryTheBackendMessageOrTheStatus() async {
        StubURLProtocol.script = { _ in StubURLProtocol.json(500, #"{"error": "internal_error", "message": "Deepgram grant failed"}"#) }
        do {
            _ = try await api.requestSession(deviceId: deviceID, model: "nova-3")
            XCTFail("expected serverError")
        } catch MinitiAPIService.ServiceError.serverError(let message) {
            XCTAssertEqual(message, "Deepgram grant failed")
        } catch {
            XCTFail("unexpected \(error)")
        }

        StubURLProtocol.script = { _ in (502, Data("<html>bad gateway</html>".utf8), ["Content-Type": "text/html"]) }
        do {
            _ = try await api.checkUsage(deviceId: deviceID)
            XCTFail("expected serverError")
        } catch MinitiAPIService.ServiceError.serverError(let message) {
            XCTAssertEqual(message, "HTTP 502")
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testMalformedSuccessBodyMapsToInvalidResponse() async {
        // `UsageInfo` tolerates odd field types on purpose; a body that is not JSON at all
        // and a session reply missing its required token are the real malformed cases.
        StubURLProtocol.script = { _ in (200, Data("<html>not json</html>".utf8), ["Content-Type": "text/html"]) }
        do {
            _ = try await api.checkUsage(deviceId: deviceID)
            XCTFail("expected invalidResponse")
        } catch MinitiAPIService.ServiceError.invalidResponse {
        } catch {
            XCTFail("unexpected \(error)")
        }

        // A JSON object without the expected fields is reported through the error envelope
        // decoder, which defaults the code to `unknown_error` rather than hiding the body.
        StubURLProtocol.script = { _ in StubURLProtocol.json(200, #"{"unexpected": true}"#) }
        do {
            _ = try await api.requestSession(deviceId: deviceID, model: "nova-3")
            XCTFail("expected serverError")
        } catch MinitiAPIService.ServiceError.serverError(let message) {
            XCTAssertEqual(message, "unknown_error")
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    // MARK: Token lifecycle

    func testExpiredTokenIsRefreshedOnceAndTheRequestRetried() async throws {
        var usageCalls = 0
        StubURLProtocol.script = { request in
            switch request.url?.path ?? "" {
            case "/api/usage":
                usageCalls += 1
                if usageCalls == 1 {
                    return StubURLProtocol.json(401, #"{"error": "token_expired", "message": "expired"}"#)
                }
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok2", "the retry carries the refreshed token")
                return StubURLProtocol.json(200, Self.usageBody)
            case "/api/auth/token":
                let body = try JSONSerialization.jsonObject(with: TestSupport.bodyData(of: request)) as? [String: Any]
                XCTAssertEqual(body?["grant_type"] as? String, "refresh")
                XCTAssertEqual(body?["refresh_token"] as? String, "mrt_x")
                return StubURLProtocol.json(200, #"{"token_type": "Bearer", "access_token": "tok2", "expires_in": 3600, "refresh_token": "mrt_y"}"#)
            default:
                XCTFail("unexpected request \(request.url?.path ?? "")")
                return StubURLProtocol.json(500, "{}")
            }
        }

        let usage = try await api.checkUsage(deviceId: deviceID)
        XCTAssertEqual(usage.minutesUsed, 12.5)
        XCTAssertEqual(StubURLProtocol.requests.map { $0.url?.path ?? "" }, ["/api/usage", "/api/auth/token", "/api/usage"])
        XCTAssertTrue(auth.isEnrolled)
    }

    func testSecondUnauthorizedAfterRefreshSurfacesAsServerError() async {
        StubURLProtocol.script = { request in
            if request.url?.path == "/api/auth/token" {
                return StubURLProtocol.json(200, #"{"token_type": "Bearer", "access_token": "tok2", "expires_in": 3600}"#)
            }
            return StubURLProtocol.json(401, #"{"error": "token_expired", "message": "still expired"}"#)
        }
        do {
            _ = try await api.checkUsage(deviceId: deviceID)
            XCTFail("expected serverError")
        } catch MinitiAPIService.ServiceError.serverError(let message) {
            XCTAssertEqual(message, "still expired")
            XCTAssertEqual(StubURLProtocol.requests.filter { $0.url?.path == "/api/usage" }.count, 2, "exactly one silent retry")
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testRevokedInstallationClearsLocalCredentials() async {
        StubURLProtocol.script = { _ in StubURLProtocol.json(401, #"{"error": "installation_revoked", "message": "revoked"}"#) }
        do {
            _ = try await api.checkUsage(deviceId: deviceID)
            XCTFail("expected authRevoked")
        } catch MinitiAPIService.ServiceError.authRevoked {
            XCTAssertFalse(auth.isEnrolled, "a revoked device signs out locally")
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    // MARK: Transport failures

    func testTimeoutAndOfflineErrorsPropagateAsURLErrors() async {
        for code in [URLError.timedOut, URLError.notConnectedToInternet, URLError.networkConnectionLost, URLError.cannotConnectToHost] {
            StubURLProtocol.script = { _ in throw URLError(code) }
            do {
                _ = try await api.checkUsage(deviceId: deviceID)
                XCTFail("expected \(code)")
            } catch let error as URLError {
                XCTAssertEqual(error.code, code)
            } catch {
                XCTFail("unexpected \(error) for \(code)")
            }
        }
    }

    func testTransientClassificationMatchesTheInsightsRetryPolicy() {
        for code in [URLError.timedOut, URLError.networkConnectionLost, URLError.cannotConnectToHost, URLError.cannotFindHost] {
            XCTAssertTrue(AppState.isTransientInsightsError(URLError(code)), "\(code) should retry")
        }
        XCTAssertTrue(AppState.isTransientInsightsError(MinitiAPIService.ServiceError.serverError("HTTP 504")))
        XCTAssertFalse(AppState.isTransientInsightsError(MinitiAPIService.ServiceError.rateLimited))
        XCTAssertFalse(AppState.isTransientInsightsError(MinitiAPIService.ServiceError.limitReached(minutesUsed: 500, resetsAt: nil)))
    }

    func testCancellationMidFlightThrowsCancelled() async {
        StubURLProtocol.delay = 2
        StubURLProtocol.script = { _ in StubURLProtocol.json(200, Self.usageBody) }
        let api = self.api!
        let task = Task { try await api.checkUsage(deviceId: TestSupport.testDeviceID) }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cancelled)
        } catch is CancellationError {
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    // MARK: Calendar and CRM through the same transport

    func testGoogleEventsDecodeTheBackendWireFormat() async throws {
        StubURLProtocol.script = { request in
            XCTAssertEqual(request.url?.path, "/api/google/events")
            XCTAssertTrue(request.url?.query?.contains("include_filtered=true") == true)
            return StubURLProtocol.json(200, CalendarEventDecodingTests.wirePayload)
        }
        let events = try await api.googleEvents(deviceId: deviceID, includeFiltered: true)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].meetLink, "https://meet.google.com/abc-defg-hij")
        XCTAssertEqual(events[0].attendees.map(\.displayName), ["Sam Lee", nil])
        XCTAssertEqual(events[1].skipReason, "out_of_office")
    }

    func testCRMStatusUsesTheInjectedSessionAndWritesCarryAProof() async throws {
        StubURLProtocol.script = { request in
            switch request.url?.path ?? "" {
            case "/api/attio/status":
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertNil(request.value(forHTTPHeaderField: "X-Request-Proof"), "reads carry no proof")
                return StubURLProtocol.json(200, #"{"connected": true, "account_label": "Acme"}"#)
            case "/api/twenty/status":
                return StubURLProtocol.json(200, #"{"connected": false}"#)
            case "/api/session/end":
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertNotNil(request.value(forHTTPHeaderField: "X-Request-Proof"), "writes carry a proof")
                return StubURLProtocol.json(200, #"{"success": true, "minutes_used": 13.0}"#)
            default:
                return StubURLProtocol.json(500, "{}")
            }
        }
        let attio = try await api.attioStatus(deviceId: deviceID)
        XCTAssertTrue(attio.connected)
        XCTAssertEqual(attio.accountLabel, "Acme")
        let twenty = try await api.twentyStatus(deviceId: deviceID)
        XCTAssertFalse(twenty.connected)
        _ = try await api.endSession(deviceId: deviceID, sessionId: "sess_1", durationMinutes: 0.5)
        XCTAssertEqual(StubURLProtocol.requests.count, 3)
    }
}

extension MinitiAPIServiceTransportTests {
    func testAIHTTP200DecodeFailureCarriesOnlyBoundedCorrelationAndStatus() async throws {
        let context = AIRequestObservation(accountID: auth.status.accountID, credentialGeneration: auth.credentialGeneration, stage: "final")
        StubURLProtocol.script = { _ in StubURLProtocol.json(200, "not valid JSON, private response") }
        await AIRequestDiagnostics.$current.withValue(context) {
            do {
                _ = try await api.generateInsights(deviceId: deviceID, transcript: "synthetic transcript", existingSummary: nil,
                    existingTitle: nil, mode: "standard", model: OpenAIModel.gpt6Luna.rawValue)
                XCTFail("malformed successful response must fail decoding")
            } catch {
                let fields = context.fields(mode: "standard", error: error)
                XCTAssertEqual(fields["failure_category"], "decode")
                XCTAssertEqual(fields["status"], "200")
                XCTAssertEqual(fields["ai_stage"], "final")
                XCTAssertEqual(fields["request_id"], StubURLProtocol.requests.last?.value(forHTTPHeaderField: "X-Client-Request-ID"))
                XCTAssertNotNil(fields["request_id"].flatMap(UUID.init(uuidString:)))
                XCTAssertFalse(fields.values.contains { $0.contains("private") || $0.contains("transcript") })
            }
        }
        XCTAssertNil(AIRequestDiagnostics.current)
    }

    func testAITransportCancellationAndAdmissionKeepDistinctCategoriesWithoutChangingErrors() async throws {
        for (code, category) in [(URLError.timedOut, "timeout"), (.networkConnectionLost, "transport"), (.cancelled, "cancelled")] {
            let context = AIRequestObservation(accountID: nil, credentialGeneration: 0, stage: "live")
            StubURLProtocol.script = { _ in throw URLError(code) }
            await AIRequestDiagnostics.$current.withValue(context) {
                do {
                    _ = try await api.generateInsights(deviceId: deviceID, transcript: "fixture", existingSummary: nil, existingTitle: nil, mode: "standard", model: "fixture")
                    XCTFail("expected transport error")
                } catch {
                    XCTAssertEqual((error as? URLError)?.code, code, "Diagnostic context must not wrap or change existing retry errors")
                    XCTAssertEqual(context.fields(mode: "standard", error: error)["failure_category"], category)
                    XCTAssertNil(context.fields(mode: "standard", error: error)["status"])
                }
            }
        }
        XCTAssertEqual(AIRequestDiagnostics.category(MinitiAPIService.ServiceError.rateLimited, status: 429), "admission")
        XCTAssertEqual(AIRequestDiagnostics.category(MinitiAPIService.ServiceError.authRevoked), "auth")
        XCTAssertEqual(AIRequestDiagnostics.category(MinitiAPIService.ServiceError.serverError("private provider message")), "unknown")
    }

    func testNoCorrelationOutsideAnObservedAIRequestAndContextsDoNotLeakAcrossModes() async throws {
        StubURLProtocol.script = { _ in StubURLProtocol.json(200, Self.usageBody) }
        _ = try await api.checkUsage(deviceId: deviceID)
        XCTAssertNil(StubURLProtocol.requests.last?.value(forHTTPHeaderField: "X-Client-Request-ID"))
        let context = AIRequestObservation(accountID: nil, credentialGeneration: 0, stage: "saved")
        let old = context.start(mode: "standard")
        let current = context.start(mode: "questions")
        context.received(status: 503, requestID: old)
        XCTAssertNil(context.fields(mode: "questions", error: CancellationError())["status"])
        context.received(status: 200, requestID: current)
        XCTAssertNil(context.fields(mode: "standard", error: CancellationError())["request_id"])
        XCTAssertEqual(context.fields(mode: "questions", error: CancellationError())["status"], "200")
    }
}
