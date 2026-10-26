import XCTest
import CryptoKit
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

/// Device-bound authorization primitives, verified against the cross-language vectors
/// shared with miniti-api (test/fixtures/client-auth-vectors.json) and the Linux client.
final class ClientAuthTests: XCTestCase {

    // MARK: - Recovery keys (vectors)

    private func bytes(hex: String) -> [UInt8] {
        stride(from: 0, to: hex.count, by: 2).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 2)
            return UInt8(hex[start..<end], radix: 16)!
        }
    }

    func testRecoveryKeyVectorsMatchBackend() {
        let vectors: [(random: String, canonical: String, formatted: String)] = [
            ("000102030405060708090a0b0c0d0e0f", "M1000G40R40M30E209185GR38E1WETS870", "M1-000G-40R4-0M30-E209-185G-R38E-1WET-S870"),
            ("ffeeddccbbaa99887766554433221100", "M1ZZQDVK5VNACRGXV6AN2368GH02HFWS9H", "M1-ZZQD-VK5V-NACR-GXV6-AN23-68GH-02HF-WS9H"),
        ]
        for vector in vectors {
            let key = ClientAuthCrypto.recoveryKey(fromRandom: bytes(hex: vector.random))
            XCTAssertEqual(key, vector.canonical)
            XCTAssertEqual(ClientAuthCrypto.formatRecoveryKey(key), vector.formatted)
            XCTAssertEqual(ClientAuthCrypto.parseRecoveryKey(vector.formatted), key)
        }
    }

    func testRecoveryKeyNormalizationVectors() {
        let canonical = "M1000G40R40M30E209185GR38E1WETS870"
        for input in [
            "m1-000g-40r4-0m30-e209-185g-r38e-1wet-s870",
            "000G40R40M30E209185GR38E1WETS870",
            "M1 000G 40R4 0M30 E209 185G R38E 1WET S870",
        ] {
            XCTAssertEqual(ClientAuthCrypto.normalizeRecoveryKey(input), canonical, input)
            XCTAssertEqual(ClientAuthCrypto.parseRecoveryKey(input), canonical, input)
        }
    }

    func testRecoveryKeyChecksumAndConfusables() {
        let canonical = "M1000G40R40M30E209185GR38E1WETS870"
        // O → 0 and I/L → 1 normalize back to the canonical alphabet.
        let confused = canonical.replacingOccurrences(of: "0", with: "O").replacingOccurrences(of: "1", with: "I")
        XCTAssertEqual(ClientAuthCrypto.parseRecoveryKey(confused), canonical)
        // One flipped character fails the checksum.
        var chars = Array(canonical)
        chars[10] = chars[10] == "A" ? "B" : "A"
        XCTAssertNil(ClientAuthCrypto.parseRecoveryKey(String(chars)))
        XCTAssertNil(ClientAuthCrypto.parseRecoveryKey("short"))
        XCTAssertNil(ClientAuthCrypto.parseRecoveryKey(""))
        let generated = ClientAuthCrypto.generateRecoveryKey()
        XCTAssertEqual(generated.count, 34)
        XCTAssertEqual(ClientAuthCrypto.parseRecoveryKey(generated), generated)
        XCTAssertNotEqual(ClientAuthCrypto.generateRecoveryKey(), generated)
    }

    // MARK: - Hashes and thumbprints (vectors)

    func testThumbprintAndHashVectorsMatchBackend() {
        XCTAssertEqual(
            ClientAuthCrypto.jwkThumbprint(x: "f83OJ3D2xF1Bg8vub9tLe1gHMzV76e8Tus9uPHvRVEU", y: "x_FEzRu9m36HLN_tue659LNpXW6pCyStikYjKIWI5a0"),
            "oKIywvGUpTVTyxMQ3bwIIeQUudfr_CkLMjCE19ECD-U"
        )
        XCTAssertEqual(ClientAuthCrypto.hashB64(Data()), "47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU")
        XCTAssertEqual(ClientAuthCrypto.hashB64(Data("{\"model\":\"nova-3\",\"language\":\"en\"}".utf8)), "b1cuiGe8JT4NZ96j7kSDmFkjwVNYevNNF53my6KsDZg")
        XCTAssertEqual(ClientAuthCrypto.hashB64(Data("a.b.c".utf8)), "hF4wRIgJ4ryJWOsCW_x5UjXROwd6U9DDq70jhRcNybg")
    }

    func testBase64URLRoundTrip() throws {
        let data = Data(ClientAuthCrypto.randomBytes(33))
        let encoded = ClientAuthCrypto.b64url(data)
        XCTAssertFalse(encoded.contains("="))
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertEqual(ClientAuthCrypto.b64urlDecode(encoded), data)
    }

    // MARK: - Installation key + proofs

    private func decodePayload(_ jws: String) throws -> [String: Any] {
        let parts = jws.split(separator: ".")
        XCTAssertEqual(parts.count, 3)
        let data = try XCTUnwrap(ClientAuthCrypto.b64urlDecode(String(parts[1])))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testInstallationKeyRoundTripsAndSignsVerifiableProofs() throws {
        let key = InstallationKey.generate(preferSecureEnclave: false)
        XCTAssertFalse(key.isHardwareBacked)
        let restored = try XCTUnwrap(InstallationKey(stored: key.stored))
        XCTAssertEqual(restored.thumbprint, key.thumbprint)

        let jwk = key.publicJWK
        XCTAssertEqual(jwk["kty"], "EC")
        XCTAssertEqual(jwk["crv"], "P-256")
        XCTAssertEqual(try XCTUnwrap(ClientAuthCrypto.b64urlDecode(jwk["x"]!)).count, 32)
        XCTAssertEqual(ClientAuthCrypto.jwkThumbprint(x: jwk["x"]!, y: jwk["y"]!), key.thumbprint)

        let body = Data("{\"model\":\"nova-3\",\"language\":\"en\"}".utf8)
        let proof = try key.requestProof(accessToken: "a.b.c", method: "post", target: "/api/session", body: body, now: 1_700_000_000, jti: "req-1")
        let parts = proof.split(separator: ".").map(String.init)
        XCTAssertEqual(parts.count, 3)
        let header = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(ClientAuthCrypto.b64urlDecode(parts[0]))) as? [String: String])
        XCTAssertEqual(header, ["alg": "ES256", "typ": "miniti-proof+jwt"])
        let payload = try decodePayload(proof)
        XCTAssertEqual(payload["htm"] as? String, "POST")
        XCTAssertEqual(payload["htu"] as? String, "/api/session")
        XCTAssertEqual(payload["ath"] as? String, "hF4wRIgJ4ryJWOsCW_x5UjXROwd6U9DDq70jhRcNybg")
        XCTAssertEqual(payload["bh"] as? String, "b1cuiGe8JT4NZ96j7kSDmFkjwVNYevNNF53my6KsDZg")
        XCTAssertEqual(payload["jti"] as? String, "req-1")
        XCTAssertEqual(payload["iat"] as? Int, 1_700_000_000)

        // Raw r‖s signature, exactly 64 bytes, verifies against the public key over header.payload.
        let signature = try XCTUnwrap(ClientAuthCrypto.b64urlDecode(parts[2]))
        XCTAssertEqual(signature.count, 64)
        let ecdsa = try P256.Signing.ECDSASignature(rawRepresentation: signature)
        XCTAssertTrue(key.publicKey.isValidSignature(ecdsa, for: Data("\(parts[0]).\(parts[1])".utf8)))

        let challenge = try key.challengeProof(nonce: "n0nce", purpose: "enroll", deviceID: "550e8400-e29b-41d4-a716-446655440000", now: 1)
        let challengePayload = try decodePayload(challenge)
        XCTAssertEqual(challengePayload["purpose"] as? String, "enroll")
        XCTAssertEqual(challengePayload["nonce"] as? String, "n0nce")
        XCTAssertEqual(challengePayload["jkt"] as? String, key.thumbprint)
    }

    func testRequestTargetKeepsQuery() throws {
        XCTAssertEqual(ClientAuthCrypto.requestTarget(try XCTUnwrap(URL(string: "https://api.miniti.app/api/google/events?days=7"))), "/api/google/events?days=7")
        XCTAssertEqual(ClientAuthCrypto.requestTarget(try XCTUnwrap(URL(string: "https://api.miniti.app/api/session"))), "/api/session")
    }

    // MARK: - Manager state (no network)

    private func credentials(acknowledged: Bool = false) -> ClientAuthCredentials {
        ClientAuthCredentials(
            installationKey: InstallationKey.generate(preferSecureEnclave: false).stored,
            recoveryKey: ClientAuthCrypto.generateRecoveryKey(),
            accountID: "acct_test",
            accessToken: "tok",
            accessExpiresAt: Int64(Date().timeIntervalSince1970) + 3600,
            refreshToken: "mrt_x",
            deviceCap: 5,
            enrolledAt: "2026-09-06T00:00:00Z",
            enrollmentPath: "migrate",
            recoveryKeyAcknowledged: acknowledged
        )
    }

    func testManagerStatusRevealAndProofReflectStoredCredentials() async throws {
        let stored = credentials()
        let manager = ClientAuthManager(store: InMemoryClientAuthStore(stored), deviceIDProvider: { "550e8400-e29b-41d4-a716-446655440000" })
        XCTAssertTrue(manager.isEnrolled)
        let status = manager.status
        XCTAssertEqual(status.accountID, "acct_test")
        XCTAssertEqual(status.enrollmentPath, "migrate")
        XCTAssertFalse(status.recoveryKeyAcknowledged)
        XCTAssertFalse(status.isHardwareBacked)
        XCTAssertEqual(manager.revealRecoveryKey(), ClientAuthCrypto.formatRecoveryKey(stored.recoveryKey))

        // A fresh token is used as-is; no network is touched.
        let token = try await manager.accessToken()
        XCTAssertEqual(token, "tok")
        var request = URLRequest(url: try XCTUnwrap(URL(string: "https://api.miniti.app/api/session?x=1")))
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        try await manager.authorize(&request)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        let proof = try XCTUnwrap(request.value(forHTTPHeaderField: "X-Request-Proof"))
        XCTAssertEqual((try decodePayload(proof))["htu"] as? String, "/api/session?x=1")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-API-Key"), "no shared secret is ever sent")

        var get = URLRequest(url: try XCTUnwrap(URL(string: "https://api.miniti.app/api/usage")))
        get.httpMethod = "GET"
        try await manager.authorize(&get)
        XCTAssertNil(get.value(forHTTPHeaderField: "X-Request-Proof"), "GET routes carry no proof")

        manager.markRecoveryKeyAcknowledged()
        XCTAssertTrue(manager.status.recoveryKeyAcknowledged)
        manager.clearLocal()
        XCTAssertFalse(manager.isEnrolled)
        XCTAssertEqual(manager.status, .notEnrolled)
    }

    // `StubURLProtocol` and the stubbed session live in TestSupport.swift, shared with the
    // transport and journey tests.
    private func stubbedSession() -> URLSession {
        TestSupport.stubbedSession()
    }

    func testAttachMovesTheInstallationAndReplacesAccountKeyAndTokens() async throws {
        let stored = credentials(acknowledged: false)
        let store = InMemoryClientAuthStore(stored)
        let manager = ClientAuthManager(
            store: store,
            baseURL: "https://api.test/api",
            session: stubbedSession(),
            deviceIDProvider: { "550e8400-e29b-41d4-a716-446655440000" }
        )
        let destinationKey = ClientAuthCrypto.generateRecoveryKey()
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/auth/account/attach")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "X-Request-Proof"), "attach is a proof-bearing write")
            let body = (request.httpBody ?? request.httpBodyStream.map { stream -> Data in
                stream.open(); defer { stream.close() }
                var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(buffer, count: n) }
                return data
            }) ?? Data()
            let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            XCTAssertEqual(json?["recovery_key"] as? String, destinationKey)
            let reply = """
            {"token_type":"Bearer","access_token":"tok2","expires_in":3600,"refresh_token":"mrt_y","refresh_expires_in":7776000,"account_id":"acct_dest","device_id":"550e8400-e29b-41d4-a716-446655440000","device_cap":5,"moved":true}
            """
            return (200, Data(reply.utf8))
        }
        defer { StubURLProtocol.handler = nil }

        let moved = try await manager.attachToAccount(recoveryKeyInput: ClientAuthCrypto.formatRecoveryKey(destinationKey))
        XCTAssertTrue(moved)
        XCTAssertTrue(manager.isEnrolled, "a move never signs the device out")
        XCTAssertEqual(manager.status.accountID, "acct_dest")
        XCTAssertEqual(manager.status.enrollmentPath, "migrate", "the enrollment path is history, not membership")
        XCTAssertTrue(manager.status.recoveryKeyAcknowledged)
        XCTAssertEqual(manager.revealRecoveryKey(), ClientAuthCrypto.formatRecoveryKey(destinationKey))
        let token = try await manager.accessToken()
        XCTAssertEqual(token, "tok2")
        XCTAssertEqual(store.load()?.refreshToken, "mrt_y")
    }

    private func requestBody(_ request: URLRequest) -> [String: Any] {
        let data = request.httpBody ?? request.httpBodyStream.map { stream -> Data in
            stream.open(); defer { stream.close() }
            var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(buffer, count: n) }
            return data
        } ?? Data()
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func expiredCredentials() -> ClientAuthCredentials {
        var stored = credentials()
        stored.accessExpiresAt = Int64(Date().timeIntervalSince1970) - 10
        return stored
    }

    /// The server holds a different key for this device id (a backup restored onto a device
    /// that kept its UUID). The challenge grant answers `invalid_proof`; the manager re-binds
    /// through the restore route with the stored recovery key and the current key, and keeps
    /// everything else it knew.
    func testTokenRefreshRebindsWhenServerRejectsTheKey() async throws {
        let stored = expiredCredentials()
        let store = InMemoryClientAuthStore(stored)
        let storedKey = try XCTUnwrap(InstallationKey(stored: stored.installationKey))
        let manager = ClientAuthManager(
            store: store,
            baseURL: "https://api.test/api",
            session: stubbedSession(),
            deviceIDProvider: { "550e8400-e29b-41d4-a716-446655440000" },
            deviceLabelProvider: { "Test device" }
        )
        nonisolated(unsafe) var paths: [String] = []
        nonisolated(unsafe) var challengePurposes: [String] = []
        StubURLProtocol.handler = { [self] request in
            let path = request.url?.path ?? ""
            paths.append(path)
            let body = requestBody(request)
            switch path {
            case "/api/auth/token":
                if body["grant_type"] as? String == "refresh" {
                    return (401, Data(#"{"error":"invalid_refresh_token","message":"Refresh token rejected"}"#.utf8))
                }
                return (401, Data(#"{"error":"invalid_proof","message":"Proof of possession failed"}"#.utf8))
            case "/api/auth/challenge":
                challengePurposes.append(body["purpose"] as? String ?? "")
                return (200, Data(#"{"challenge_id":"c1","nonce":"n1","expires_in":120}"#.utf8))
            case "/api/auth/account/restore":
                XCTAssertEqual(body["recovery_key"] as? String, stored.recoveryKey, "the stored recovery key proves the account")
                XCTAssertEqual(body["label"] as? String, "Test device")
                XCTAssertNotNil(body["proof"] as? String)
                let jwk = body["public_key_jwk"] as? [String: String] ?? [:]
                XCTAssertEqual(jwk, storedKey.publicJWK, "the current key is re-bound, not a fresh one")
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"), "restore is a public route")
                let reply = """
                {"token_type":"Bearer","access_token":"tok2","expires_in":3600,"refresh_token":"mrt_y","refresh_expires_in":7776000,"account_id":"acct_test","device_id":"550e8400-e29b-41d4-a716-446655440000","device_cap":5}
                """
                return (200, Data(reply.utf8))
            default:
                XCTFail("unexpected request \(path)")
                return (500, Data())
            }
        }
        defer { StubURLProtocol.handler = nil }

        let token = try await manager.accessToken()
        XCTAssertEqual(token, "tok2")
        XCTAssertEqual(paths, ["/api/auth/token", "/api/auth/challenge", "/api/auth/token", "/api/auth/challenge", "/api/auth/account/restore"])
        XCTAssertEqual(challengePurposes, ["token", "enroll"])
        let after = try XCTUnwrap(store.load())
        XCTAssertEqual(after.refreshToken, "mrt_y")
        XCTAssertEqual(after.accountID, "acct_test")
        XCTAssertEqual(after.recoveryKey, stored.recoveryKey)
        XCTAssertEqual(after.installationKey, stored.installationKey, "re-binding never rotates the key")
        XCTAssertEqual(after.enrollmentPath, stored.enrollmentPath, "the enrollment path is history, not membership")
        XCTAssertTrue(manager.isEnrolled)

        // The new token is cached; a second call touches nothing.
        paths = []
        let cached = try await manager.accessToken()
        XCTAssertEqual(cached, "tok2")
        XCTAssertEqual(paths, [])
    }

    /// When the re-bind is refused too, the device is stuck unless sign-out works without a
    /// token. It clears local credentials and does not throw.
    func testSignOutClearsLocallyWhenTheKeyIsRejectedAndRebindRefused() async throws {
        let store = InMemoryClientAuthStore(expiredCredentials())
        let manager = ClientAuthManager(store: store, baseURL: "https://api.test/api", session: stubbedSession(), deviceIDProvider: { "550e8400-e29b-41d4-a716-446655440000" })
        StubURLProtocol.handler = { request in
            switch request.url?.path ?? "" {
            case "/api/auth/challenge": return (200, Data(#"{"challenge_id":"c1","nonce":"n1","expires_in":120}"#.utf8))
            case "/api/auth/account/restore": return (409, Data(#"{"error":"device_already_enrolled","message":"x"}"#.utf8))
            default: return (401, Data(#"{"error":"invalid_proof","message":"Proof of possession failed"}"#.utf8))
            }
        }
        defer { StubURLProtocol.handler = nil }

        try await manager.signOut()
        XCTAssertFalse(manager.isEnrolled)
        XCTAssertNil(store.load())
    }

    /// A network failure during sign-out keeps the credentials: the person can retry.
    func testSignOutKeepsCredentialsOnNetworkFailure() async {
        let store = InMemoryClientAuthStore(credentials())
        let manager = ClientAuthManager(store: store, baseURL: "https://api.test/api", session: stubbedSession(), deviceIDProvider: { "550e8400-e29b-41d4-a716-446655440000" })
        StubURLProtocol.handler = { _ in (503, Data(#"{"error":"client_auth_unavailable","message":"x"}"#.utf8)) }
        defer { StubURLProtocol.handler = nil }
        do {
            try await manager.signOut()
            XCTFail("expected unavailable")
        } catch {
            XCTAssertEqual(error as? ClientAuthError, .unavailable)
        }
        XCTAssertTrue(manager.isEnrolled)
    }

    /// A create that the server refuses leaves a draft behind (so a lost response cannot lose
    /// the recovery key). The draft is not an enrollment: nothing signs with its key, status is
    /// `.notEnrolled`, the key is not shown, and the next create resumes the same draft.
    func testDraftAfterRefusedCreateIsNotAnEnrollment() async throws {
        let store = InMemoryClientAuthStore()
        let manager = ClientAuthManager(store: store, baseURL: "https://api.test/api", session: stubbedSession(), deviceIDProvider: { "550e8400-e29b-41d4-a716-446655440000" })
        StubURLProtocol.handler = { request in
            switch request.url?.path ?? "" {
            case "/api/auth/challenge": return (200, Data(#"{"challenge_id":"c1","nonce":"n1","expires_in":120}"#.utf8))
            default: return (503, Data(#"{"error":"client_auth_unavailable","message":"x"}"#.utf8))
            }
        }
        defer { StubURLProtocol.handler = nil }
        do {
            _ = try await manager.createAccount()
            XCTFail("expected unavailable")
        } catch {
            XCTAssertEqual(error as? ClientAuthError, .unavailable)
        }
        let draft = try XCTUnwrap(store.load(), "the draft survives for the retry")
        XCTAssertEqual(draft.accountID, "")
        XCTAssertFalse(manager.isEnrolled)
        XCTAssertEqual(manager.status, .notEnrolled)
        XCTAssertNil(manager.revealRecoveryKey())

        StubURLProtocol.lastRequest = nil
        do {
            _ = try await manager.accessToken()
            XCTFail("expected notEnrolled")
        } catch {
            XCTAssertEqual(error as? ClientAuthError, .notEnrolled)
        }
        XCTAssertNil(StubURLProtocol.lastRequest, "a draft never signs a token grant")

        // The retry resumes the draft's key and recovery key rather than minting new ones.
        StubURLProtocol.handler = { request in
            switch request.url?.path ?? "" {
            case "/api/auth/challenge": return (200, Data(#"{"challenge_id":"c2","nonce":"n2","expires_in":120}"#.utf8))
            case "/api/auth/account/create":
                let body = self.requestBody(request)
                XCTAssertEqual(body["recovery_key"] as? String, draft.recoveryKey)
                let reply = """
                {"token_type":"Bearer","access_token":"tok","expires_in":3600,"refresh_token":"mrt_a","refresh_expires_in":7776000,"account_id":"acct_new","device_id":"550e8400-e29b-41d4-a716-446655440000","device_cap":5}
                """
                return (200, Data(reply.utf8))
            default: return (500, Data())
            }
        }
        let shown = try await manager.createAccount()
        XCTAssertEqual(shown, ClientAuthCrypto.formatRecoveryKey(draft.recoveryKey))
        XCTAssertTrue(manager.isEnrolled)
        XCTAssertEqual(store.load()?.installationKey, draft.installationKey)
        XCTAssertEqual(manager.status.accountID, "acct_new")
    }

    /// The server already holds an installation under this device id with a key this device
    /// does not have (a restored backup). The install takes a fresh device id and creates its
    /// account under it, once.
    func testCreateRotatesTheDeviceIDWhenTheServerAlreadyHasThisOne() async throws {
        let store = InMemoryClientAuthStore()
        nonisolated(unsafe) var deviceID = "550e8400-e29b-41d4-a716-446655440000"
        nonisolated(unsafe) var rotations = 0
        let manager = ClientAuthManager(
            store: store,
            baseURL: "https://api.test/api",
            session: stubbedSession(),
            deviceIDProvider: { deviceID },
            deviceIDRotator: {
                rotations += 1
                deviceID = "11111111-2222-4333-8444-555555555555"
                return deviceID
            }
        )
        nonisolated(unsafe) var createIDs: [String] = []
        StubURLProtocol.handler = { [self] request in
            let body = requestBody(request)
            switch request.url?.path ?? "" {
            case "/api/auth/challenge": return (200, Data(#"{"challenge_id":"c1","nonce":"n1","expires_in":120}"#.utf8))
            case "/api/auth/account/create":
                let id = body["device_id"] as? String ?? ""
                createIDs.append(id)
                if id == "550e8400-e29b-41d4-a716-446655440000" {
                    return (409, Data(#"{"error":"device_already_enrolled","message":"x"}"#.utf8))
                }
                let reply = """
                {"token_type":"Bearer","access_token":"tok","expires_in":3600,"refresh_token":"mrt_a","refresh_expires_in":7776000,"account_id":"acct_fresh","device_id":"\(id)","device_cap":5}
                """
                return (200, Data(reply.utf8))
            default: return (500, Data())
            }
        }
        defer { StubURLProtocol.handler = nil }

        let events = EventCollector()
        manager.attachEventSink { events.append($0) }

        _ = try await manager.createAccount()
        XCTAssertEqual(rotations, 1)
        XCTAssertEqual(createIDs, ["550e8400-e29b-41d4-a716-446655440000", "11111111-2222-4333-8444-555555555555"])
        XCTAssertTrue(manager.isEnrolled)
        XCTAssertEqual(manager.status.accountID, "acct_fresh")
        XCTAssertEqual(manager.status.enrollmentPath, "create")

        // A1: the conflict and the rotation are counted, with prefixes only.
        XCTAssertEqual(events.names, ["client_auth_create_conflict", "client_auth_device_rotated"])
        XCTAssertEqual(events.all[0].details, ["path": "create", "rotator": "yes"])
        XCTAssertEqual(events.all[1].level, .warning)
        XCTAssertEqual(events.all[1].details, ["from": "550e8400", "to": "11111111", "path": "create"])
        for event in events.all {
            for value in event.details.values { XCTAssertLessThan(value.count, 12, "no full identifiers in event details") }
        }
    }

    /// Without a rotator (tests, or an install that must keep its identity) the conflict is
    /// surfaced as-is and nothing is written beyond the draft.
    func testCreateSurfacesTheConflictWhenTheDeviceIDCannotChange() async {
        let store = InMemoryClientAuthStore()
        let manager = ClientAuthManager(store: store, baseURL: "https://api.test/api", session: stubbedSession(), deviceIDProvider: { "550e8400-e29b-41d4-a716-446655440000" })
        StubURLProtocol.handler = { request in
            switch request.url?.path ?? "" {
            case "/api/auth/challenge": return (200, Data(#"{"challenge_id":"c1","nonce":"n1","expires_in":120}"#.utf8))
            default: return (409, Data(#"{"error":"device_already_enrolled","message":"x"}"#.utf8))
            }
        }
        defer { StubURLProtocol.handler = nil }
        let events = EventCollector()
        manager.attachEventSink { events.append($0) }
        do {
            _ = try await manager.createAccount()
            XCTFail("expected deviceAlreadyEnrolled")
        } catch {
            XCTAssertEqual(error as? ClientAuthError, .deviceAlreadyEnrolled)
        }
        XCTAssertFalse(manager.isEnrolled)
        XCTAssertEqual(events.names, ["client_auth_create_conflict"], "no rotation event when nothing rotated")
        XCTAssertEqual(events.all[0].details["rotator"], "no")
    }

    // MARK: - A1 diagnostics events

    func testEventsRaisedBeforeTheSinkIsAttachedArriveOnceInOrder() async {
        // The credential is read in `init`, before AppState can attach anything: an
        // undecodable item must still reach the queue once the sink exists.
        let store = DiagnosticClientAuthStore(diagnostic: .undecodable(bytes: 42))
        let manager = ClientAuthManager(store: store, baseURL: "https://api.test/api", session: stubbedSession(), deviceIDProvider: { "550e8400-e29b-41d4-a716-446655440000" })
        let events = EventCollector()
        manager.attachEventSink { events.append($0) }
        XCTAssertEqual(events.names, ["client_auth_credential_undecodable"])
        XCTAssertEqual(events.all[0].level, .error)
        XCTAssertEqual(events.all[0].details, ["bytes": "42", "phase": "launch"])

        // Attaching again replays nothing; the same event is not raised twice in one process.
        let second = EventCollector()
        manager.attachEventSink { second.append($0) }
        XCTAssertEqual(second.names, [])
        XCTAssertEqual(events.names.count, 1)
    }

    func testAnUnreadableCredentialIsReportedWithItsStatus() {
        let store = DiagnosticClientAuthStore(diagnostic: .unreadable(status: -25308))
        let manager = ClientAuthManager(store: store, baseURL: "https://api.test/api", session: stubbedSession(), deviceIDProvider: { "550e8400-e29b-41d4-a716-446655440000" })
        XCTAssertFalse(manager.isEnrolled, "unchanged in A1: unreadable still reads as not enrolled; A3 changes that")
        let events = EventCollector()
        manager.attachEventSink { events.append($0) }
        XCTAssertEqual(events.names, ["client_auth_credential_unreadable"])
        XCTAssertEqual(events.all[0].level, .warning)
        XCTAssertEqual(events.all[0].details, ["status": "-25308", "phase": "launch"])
    }

    func testAFailedDraftWriteStopsTheEnrollmentBeforeAnyRequestAndIsCounted() async {
        // A2c: a credential the Keychain refuses to hold is one the person could never recover
        // from; the account is not created on the server first.
        let store = DiagnosticClientAuthStore(diagnostic: nil, saveSucceeds: false)
        let manager = ClientAuthManager(store: store, baseURL: "https://api.test/api", session: stubbedSession(), deviceIDProvider: { "550e8400-e29b-41d4-a716-446655440000" })
        StubURLProtocol.lastRequest = nil
        StubURLProtocol.handler = { request in
            if request.url?.path == "/api/auth/challenge" { return (200, Data(#"{"challenge_id":"c1","nonce":"n1","expires_in":120}"#.utf8)) }
            return (200, Data(#"{"token_type":"Bearer","access_token":"tok","expires_in":3600,"refresh_token":"mrt_a","refresh_expires_in":7776000,"account_id":"acct_new","device_id":"550e8400-e29b-41d4-a716-446655440000","device_cap":5}"#.utf8))
        }
        defer { StubURLProtocol.handler = nil }
        let events = EventCollector()
        manager.attachEventSink { events.append($0) }
        do {
            _ = try await manager.createAccount()
            XCTFail("expected storage")
        } catch {
            XCTAssertEqual(error as? ClientAuthError, .storage)
        }
        XCTAssertNil(StubURLProtocol.lastRequest, "no request was sent")
        XCTAssertFalse(manager.isEnrolled)
        XCTAssertEqual(events.names, ["client_auth_draft_write_failed"])
        XCTAssertEqual(events.all[0].details, ["path": "create"])
        XCTAssertEqual(ClientAuthError.storage.errorDescription, "miniti could not save its sign-in on this device. Try again.")

        // The same path with a working store proceeds.
        store.saveSucceeds = true
        _ = try? await manager.createAccount()
        XCTAssertTrue(manager.isEnrolled)
        XCTAssertEqual(manager.status.accountID, "acct_new")

        // Migrate stops the same way.
        let second = DiagnosticClientAuthStore(diagnostic: nil, saveSucceeds: false)
        let migrating = ClientAuthManager(store: second, baseURL: "https://api.test/api", session: stubbedSession(), deviceIDProvider: { "550e8400-e29b-41d4-a716-446655440000" })
        StubURLProtocol.lastRequest = nil
        do {
            try await migrating.migrateLegacyDevice()
            XCTFail("expected storage")
        } catch {
            XCTAssertEqual(error as? ClientAuthError, .storage)
        }
        XCTAssertNil(StubURLProtocol.lastRequest)
    }

    // MARK: - A2b credential format fixtures

    /// Captured shapes of the stored credential JSON, one per shipped format. Never edit a
    /// fixture; add one for each format change together with a test that the older ones still
    /// decode to the expected values (docs/enrollment-identity-plan.md, A2b). Key material is fake.
    private enum CredentialFixtures {
        /// 3.3.0, enrolled by recovery key, software key, acknowledged.
        static let enrolled_3_3_0 = """
        {"installationKey":{"kind":"sw","data":"AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE"},"recoveryKey":"M1ABCDEFGHJKMNPQRSTVWXYZ0123456789AB","accountID":"acct_fixture","accessToken":"hdr.payload.sig","accessExpiresAt":1761480000,"refreshToken":"mrt_fixture","deviceCap":5,"enrolledAt":"2026-10-21T18:25:09Z","enrollmentPath":"restore","recoveryKeyAcknowledged":true}
        """
        /// 3.3.0 draft: key and recovery key written before the request, no account, no token.
        static let draft_3_3_0 = """
        {"installationKey":{"kind":"se","data":"c2VfYmxvYg"},"recoveryKey":"M1ABCDEFGHJKMNPQRSTVWXYZ0123456789AB","accountID":"","enrolledAt":"","enrollmentPath":"create","recoveryKeyAcknowledged":false}
        """
        /// 3.3.0, joined by an approved email link: no recovery key of its own, Secure Enclave key.
        static let emailJoined_3_3_0 = """
        {"installationKey":{"kind":"se","data":"c2VfYmxvYg"},"recoveryKey":"","accountID":"acct_fixture","accessToken":"hdr.payload.sig","accessExpiresAt":1761480000,"refreshToken":"mrt_fixture","deviceCap":5,"enrolledAt":"2026-10-21T18:25:09Z","enrollmentPath":"restore","recoveryKeyAcknowledged":true}
        """
        /// 2.6.0 to 2.8.x wrote no acknowledgement flag; the decoder defaults it to false.
        static let enrolled_2_6_0 = """
        {"installationKey":{"kind":"sw","data":"AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE"},"recoveryKey":"M1ABCDEFGHJKMNPQRSTVWXYZ0123456789AB","accountID":"acct_fixture","accessToken":"hdr.payload.sig","accessExpiresAt":1761480000,"refreshToken":"mrt_fixture","deviceCap":5,"enrolledAt":"2026-09-06T00:00:00Z","enrollmentPath":"migrate"}
        """
    }

    private func decodeFixture(_ json: String) throws -> ClientAuthCredentials {
        try JSONDecoder().decode(ClientAuthCredentials.self, from: Data(json.utf8))
    }

    func testEveryShippedCredentialFormatStillDecodesFieldByField() throws {
        let enrolled = try decodeFixture(CredentialFixtures.enrolled_3_3_0)
        XCTAssertEqual(enrolled.installationKey, .init(kind: "sw", data: "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE"))
        XCTAssertEqual(enrolled.recoveryKey, "M1ABCDEFGHJKMNPQRSTVWXYZ0123456789AB")
        XCTAssertEqual(enrolled.accountID, "acct_fixture")
        XCTAssertEqual(enrolled.accessToken, "hdr.payload.sig")
        XCTAssertEqual(enrolled.accessExpiresAt, 1_761_480_000)
        XCTAssertEqual(enrolled.refreshToken, "mrt_fixture")
        XCTAssertEqual(enrolled.deviceCap, 5)
        XCTAssertEqual(enrolled.enrolledAt, "2026-10-21T18:25:09Z")
        XCTAssertEqual(enrolled.enrollmentPath, "restore")
        XCTAssertTrue(enrolled.recoveryKeyAcknowledged)
        XCTAssertNotNil(InstallationKey(stored: enrolled.installationKey), "a software key from a fixture loads anywhere")
        let enrolledManager = ClientAuthManager(store: InMemoryClientAuthStore(enrolled), deviceIDProvider: { "d" })
        XCTAssertTrue(enrolledManager.isEnrolled)
        XCTAssertFalse(enrolledManager.status.isHardwareBacked)
        XCTAssertEqual(enrolledManager.revealRecoveryKey(), ClientAuthCrypto.formatRecoveryKey("M1ABCDEFGHJKMNPQRSTVWXYZ0123456789AB"))
        // Round trip: what 3.3.1 writes for this blob decodes to the same values.
        XCTAssertEqual(try JSONDecoder().decode(ClientAuthCredentials.self, from: JSONEncoder().encode(enrolled)), enrolled)

        let draft = try decodeFixture(CredentialFixtures.draft_3_3_0)
        XCTAssertEqual(draft.accountID, "")
        XCTAssertNil(draft.accessToken)
        XCTAssertEqual(draft.enrollmentPath, "create")
        XCTAssertFalse(draft.recoveryKeyAcknowledged)
        let draftManager = ClientAuthManager(store: InMemoryClientAuthStore(draft), deviceIDProvider: { "d" })
        XCTAssertFalse(draftManager.isEnrolled, "a draft is not an enrollment")
        XCTAssertNil(draftManager.revealRecoveryKey())

        let joined = try decodeFixture(CredentialFixtures.emailJoined_3_3_0)
        XCTAssertEqual(joined.recoveryKey, "")
        XCTAssertEqual(joined.accountID, "acct_fixture")
        XCTAssertEqual(joined.installationKey.kind, "se")
        let joinedManager = ClientAuthManager(store: InMemoryClientAuthStore(joined), deviceIDProvider: { "d" })
        XCTAssertTrue(joinedManager.isEnrolled)
        XCTAssertTrue(joinedManager.status.isHardwareBacked)
        XCTAssertEqual(joinedManager.revealRecoveryKey(), "", "an email-joined device has no key of its own until it rotates one")
        XCTAssertNil(InstallationKey(stored: joined.installationKey), "a Secure Enclave blob from another machine does not load (the 2026-10-26 case, A2d)")

        let old = try decodeFixture(CredentialFixtures.enrolled_2_6_0)
        XCTAssertFalse(old.recoveryKeyAcknowledged, "defaulted for a blob that predates the flag")
        XCTAssertEqual(old.enrollmentPath, "migrate")
        XCTAssertTrue(ClientAuthManager(store: InMemoryClientAuthStore(old), deviceIDProvider: { "d" }).isEnrolled)
    }

    func testEnrollingOnAnOldDeviceIDWithNoCredentialIsCountedWithItsReason() async {
        // The id existed before this launch and there is no credential: a sign-out, a
        // revoke, or a wiped item, never a fresh install.
        let store = InMemoryClientAuthStore()
        let manager = ClientAuthManager(store: store, baseURL: "https://api.test/api", session: stubbedSession(), deviceIDProvider: { "550e8400-e29b-41d4-a716-446655440000" }, deviceIDIsNewThisLaunch: { false })
        StubURLProtocol.handler = { _ in (503, Data(#"{"error":"client_auth_unavailable","message":"x"}"#.utf8)) }
        defer { StubURLProtocol.handler = nil }
        let events = EventCollector()
        manager.attachEventSink { events.append($0) }
        _ = try? await manager.createAccount()
        XCTAssertEqual(events.all.first?.name, "client_auth_silent_recreate")
        XCTAssertEqual(events.all.first?.details, ["after": "unknown", "path": "create"])

        // After a sign-out in this process the reason is known.
        manager.clearLocal(reason: "signout")
        _ = try? await manager.migrateLegacyDevice()
        XCTAssertTrue(events.all.contains { $0.name == "client_auth_silent_recreate" && $0.details == ["after": "signout", "path": "migrate"] })

        // A new install (id minted this launch) is not counted.
        let fresh = ClientAuthManager(store: InMemoryClientAuthStore(), baseURL: "https://api.test/api", session: stubbedSession(), deviceIDProvider: { "550e8400-e29b-41d4-a716-446655440000" }, deviceIDIsNewThisLaunch: { true })
        let freshEvents = EventCollector()
        fresh.attachEventSink { freshEvents.append($0) }
        _ = try? await fresh.createAccount()
        XCTAssertFalse(freshEvents.names.contains("client_auth_silent_recreate"))
    }

    func testEventsBufferIsBoundedBeforeTheSinkExists() async {
        let store = InMemoryClientAuthStore()
        nonisolated(unsafe) var counter = 0
        let manager = ClientAuthManager(
            store: store, baseURL: "https://api.test/api", session: stubbedSession(),
            deviceIDProvider: { "550e8400-e29b-41d4-a716-446655440000" },
            deviceIDRotator: { counter += 1; return String(format: "%08d-0000-4000-8000-000000000000", counter) }
        )
        // Every create answers conflict, so each attempt rotates once and raises distinct events.
        StubURLProtocol.handler = { request in
            switch request.url?.path ?? "" {
            case "/api/auth/challenge": return (200, Data(#"{"challenge_id":"c1","nonce":"n1","expires_in":120}"#.utf8))
            default: return (409, Data(#"{"error":"device_already_enrolled","message":"x"}"#.utf8))
            }
        }
        defer { StubURLProtocol.handler = nil }
        for _ in 0..<12 { _ = try? await manager.createAccount() }
        let events = EventCollector()
        manager.attachEventSink { events.append($0) }
        XCTAssertLessThanOrEqual(events.all.count, ClientAuthManager.pendingEventLimit)
        XCTAssertTrue(events.all.count > 0)
    }

    func testAttachRejectsBadKeysLocallyAndMapsServerConflicts() async {
        let store = InMemoryClientAuthStore(credentials())
        let manager = ClientAuthManager(store: store, baseURL: "https://api.test/api", session: stubbedSession(), deviceIDProvider: { "d" })
        StubURLProtocol.lastRequest = nil
        do {
            _ = try await manager.attachToAccount(recoveryKeyInput: "M1-NOPE")
            XCTFail("expected invalidRecoveryKey")
        } catch {
            XCTAssertEqual(error as? ClientAuthError, .invalidRecoveryKey)
        }
        XCTAssertNil(StubURLProtocol.lastRequest, "no request for a malformed key")

        StubURLProtocol.handler = { _ in (409, Data(#"{"error":"subscription_conflict","message":"x"}"#.utf8)) }
        defer { StubURLProtocol.handler = nil }
        let before = store.load()
        do {
            _ = try await manager.attachToAccount(recoveryKeyInput: ClientAuthCrypto.formatRecoveryKey(ClientAuthCrypto.generateRecoveryKey()))
            XCTFail("expected subscriptionConflict")
        } catch {
            XCTAssertEqual(error as? ClientAuthError, .subscriptionConflict)
        }
        XCTAssertEqual(store.load()?.accountID, before?.accountID, "a refused move changes nothing locally")
        XCTAssertEqual(store.load()?.recoveryKey, before?.recoveryKey)
    }

    func testUnenrolledManagerRefusesToAuthorize() async {
        let manager = ClientAuthManager(store: InMemoryClientAuthStore(), deviceIDProvider: { "d" })
        XCTAssertFalse(manager.isEnrolled)
        var request = URLRequest(url: URL(string: "https://api.miniti.app/api/usage")!)
        do {
            try await manager.authorize(&request)
            XCTFail("expected notEnrolled")
        } catch {
            XCTAssertEqual(error as? ClientAuthError, .notEnrolled)
        }
        XCTAssertNil(manager.revealRecoveryKey())
    }

    func testCredentialsCodableRoundTrip() throws {
        let value = credentials(acknowledged: true)
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(ClientAuthCredentials.self, from: data), value)
        // Older stored blobs without the acknowledgement flag decode with the default.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "recoveryKeyAcknowledged")
        let legacy = try JSONDecoder().decode(ClientAuthCredentials.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(legacy.recoveryKeyAcknowledged)
    }

    // MARK: - Keychain storage policy (3.2.1 lost the macOS device id)

    /// In-memory stand-in for Security.framework. `dataProtectionAvailable == false` behaves like
    /// miniti's Developer ID build, which has no application-identifier entitlement: reads of the
    /// data protection keychain answer "not found" and writes fail with -34018.
    final class FakeKeychain: KeychainBackend, @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String: Data] = [:]
        private(set) var adds: [String: Int] = [:]
        var dataProtectionAvailable: Bool
        /// Make every read of one store answer this status (a locked or denied keychain,
        /// or a build whose data protection reads answer -34018 rather than "not found").
        private var readFailures: [Bool: OSStatus] = [:]

        init(dataProtectionAvailable: Bool) { self.dataProtectionAvailable = dataProtectionAvailable }

        func failReads(dataProtection: Bool, with status: OSStatus) {
            lock.lock(); defer { lock.unlock() }
            readFailures[dataProtection] = status
        }

        private func key(_ query: [String: Any]) -> String {
            let dp = (query[kSecUseDataProtectionKeychain as String] as? Bool) ?? false
            return "\(dp ? "dp" : "legacy")|\(query[kSecAttrService as String] as? String ?? "")|\(query[kSecAttrAccount as String] as? String ?? "")"
        }
        private func isDP(_ query: [String: Any]) -> Bool { (query[kSecUseDataProtectionKeychain as String] as? Bool) ?? false }

        func item(service: String, account: String, dataProtection: Bool) -> Data? {
            lock.lock(); defer { lock.unlock() }
            return items["\(dataProtection ? "dp" : "legacy")|\(service)|\(account)"]
        }
        func addCount(service: String, account: String, dataProtection: Bool) -> Int {
            lock.lock(); defer { lock.unlock() }
            return adds["\(dataProtection ? "dp" : "legacy")|\(service)|\(account)"] ?? 0
        }
        func set(_ data: Data, service: String, account: String, dataProtection: Bool) {
            lock.lock(); defer { lock.unlock() }
            items["\(dataProtection ? "dp" : "legacy")|\(service)|\(account)"] = data
        }

        func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?) {
            lock.lock(); defer { lock.unlock() }
            if let status = readFailures[isDP(query)] { return (status, nil) }
            if isDP(query), !dataProtectionAvailable { return (errSecItemNotFound, nil) }
            guard let data = items[key(query)] else { return (errSecItemNotFound, nil) }
            return (errSecSuccess, data)
        }
        func add(_ attributes: [String: Any]) -> OSStatus {
            lock.lock(); defer { lock.unlock() }
            if isDP(attributes), !dataProtectionAvailable { return KeychainSlot.missingEntitlement }
            let k = key(attributes)
            if items[k] != nil { return errSecDuplicateItem }
            items[k] = attributes[kSecValueData as String] as? Data
            adds[k, default: 0] += 1
            return errSecSuccess
        }
        func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus {
            lock.lock(); defer { lock.unlock() }
            if isDP(query), !dataProtectionAvailable { return KeychainSlot.missingEntitlement }
            let k = key(query)
            guard items[k] != nil else { return errSecItemNotFound }
            items[k] = attributes[kSecValueData as String] as? Data
            return errSecSuccess
        }
        func delete(_ query: [String: Any]) -> OSStatus {
            lock.lock(); defer { lock.unlock() }
            if isDP(query), !dataProtectionAvailable { return KeychainSlot.missingEntitlement }
            return items.removeValue(forKey: key(query)) == nil ? errSecItemNotFound : errSecSuccess
        }
    }

    private let deviceService = "com.miniti.device-id"
    private let deviceAccount = "device-uuid"

    /// Point `DeviceIdentifier` at a fake keychain and an empty defaults suite for one test,
    /// restoring the real storage afterwards so the host app's identity is untouched.
    private func withFakeDeviceStorage(_ fake: FakeKeychain, _ body: (UserDefaults) throws -> Void) throws {
        let originalSlot = DeviceIdentifier.slot
        let originalDefaults = DeviceIdentifier.defaults
        let defaults = UserDefaults(suiteName: "test_device_id_\(UUID().uuidString)")!
        DeviceIdentifier.slot = KeychainSlot(service: deviceService, account: deviceAccount, accessible: kSecAttrAccessibleAfterFirstUnlock, backend: fake)
        DeviceIdentifier.defaults = defaults
        DeviceIdentifier.resetForTesting()
        defer {
            DeviceIdentifier.slot = originalSlot
            DeviceIdentifier.defaults = originalDefaults
            DeviceIdentifier.resetForTesting()
        }
        try body(defaults)
    }

    private func fakeAccessToken(sub: String) throws -> String {
        let header = ClientAuthCrypto.b64url(Data("{\"alg\":\"HS256\",\"typ\":\"JWT\"}".utf8))
        let payload = ClientAuthCrypto.b64url(try JSONSerialization.data(withJSONObject: ["iss": "miniti", "sub": sub, "acct": "acct_test", "scope": "managed"]))
        return "\(header).\(payload).sig"
    }

    func testAccessTokenNamesTheDeviceItWasIssuedTo() throws {
        var stored = credentials()
        XCTAssertNil(stored.tokenDeviceID, "an opaque token names no device")
        stored.accessToken = try fakeAccessToken(sub: "550E8400-E29B-41D4-A716-446655440000")
        XCTAssertEqual(stored.tokenDeviceID, "550E8400-E29B-41D4-A716-446655440000")
        stored.accessToken = try fakeAccessToken(sub: "not-a-uuid")
        XCTAssertNil(stored.tokenDeviceID)
        stored.accessToken = nil
        XCTAssertNil(stored.tokenDeviceID)
    }

    func testManagerRestoresTheDeviceIDFromTheTokenWhenTheKeychainIDDiffers() throws {
        let tokenDevice = "550e8400-e29b-41d4-a716-446655440000"
        final class Adopted: @unchecked Sendable { var ids: [String] = [] }
        let adopted = Adopted()
        var stored = credentials()
        stored.accessToken = try fakeAccessToken(sub: tokenDevice)

        // The 3.2.1 case: credentials for device A, Keychain now says device B.
        _ = ClientAuthManager(store: InMemoryClientAuthStore(stored), deviceIDProvider: { "11111111-2222-3333-4444-555555555555" }, deviceIDAdopter: { adopted.ids.append($0); return true })
        XCTAssertEqual(adopted.ids, [tokenDevice])

        // Same id, any casing: nothing to do.
        adopted.ids = []
        _ = ClientAuthManager(store: InMemoryClientAuthStore(stored), deviceIDProvider: { tokenDevice.uppercased() }, deviceIDAdopter: { adopted.ids.append($0); return true })
        XCTAssertEqual(adopted.ids, [])

        // A draft has no token and no account: never touch the device id for it.
        let draft = ClientAuthCredentials(installationKey: stored.installationKey, recoveryKey: stored.recoveryKey, accountID: "", accessToken: nil, accessExpiresAt: nil, refreshToken: nil, deviceCap: nil, enrolledAt: "", enrollmentPath: "create")
        _ = ClientAuthManager(store: InMemoryClientAuthStore(draft), deviceIDProvider: { "11111111-2222-3333-4444-555555555555" }, deviceIDAdopter: { adopted.ids.append($0); return true })
        XCTAssertEqual(adopted.ids, [])

        // No adopter (tests, tools): no reconcile.
        _ = ClientAuthManager(store: InMemoryClientAuthStore(stored), deviceIDProvider: { "11111111-2222-3333-4444-555555555555" })
        XCTAssertEqual(adopted.ids, [])
    }

    func testCredentialStoreUpdatesInPlaceAndRoundTrips() throws {
        let fake = FakeKeychain(dataProtectionAvailable: true)
        let store = KeychainClientAuthStore(backend: fake)
        XCTAssertNil(store.load())
        var first = credentials()
        XCTAssertTrue(store.save(first))
        first.accessToken = "tok2"
        XCTAssertTrue(store.save(first))
        XCTAssertEqual(store.load(), first)
        XCTAssertEqual(fake.addCount(service: "com.miniti.device-auth", account: "credentials", dataProtection: true), 1, "a second save updates the item instead of re-creating it, so its access list survives")
        store.clear()
        XCTAssertNil(store.load())
    }

    func testAdoptMakesTheGivenIDTheDeviceIdentity() throws {
        let fake = FakeKeychain(dataProtectionAvailable: true)
        try withFakeDeviceStorage(fake) { defaults in
            let minted = DeviceIdentifier.getOrCreateDeviceId()
            XCTAssertNotNil(UUID(uuidString: minted))
            XCTAssertTrue(DeviceIdentifier.adopt("550E8400-E29B-41D4-A716-446655440000", reason: "test"))
            XCTAssertEqual(DeviceIdentifier.getOrCreateDeviceId(), "550E8400-E29B-41D4-A716-446655440000")
            DeviceIdentifier.resetForTesting()
            XCTAssertEqual(DeviceIdentifier.getOrCreateDeviceId(), "550E8400-E29B-41D4-A716-446655440000", "adopted id is persisted, not just cached")
            XCTAssertNil(defaults.string(forKey: "device-uuid-fallback"))
        }
    }

    #if os(macOS)
    func testDeviceIDStaysInTheLoginKeychainWhenTheBuildCannotUseDataProtection() throws {
        // The shipped Developer ID build: legacy item present, data protection keychain refuses writes.
        let fake = FakeKeychain(dataProtectionAvailable: false)
        fake.set(Data("550E8400-E29B-41D4-A716-446655440000".utf8), service: deviceService, account: deviceAccount, dataProtection: false)
        try withFakeDeviceStorage(fake) { defaults in
            XCTAssertEqual(DeviceIdentifier.getOrCreateDeviceId(), "550E8400-E29B-41D4-A716-446655440000")
            XCTAssertEqual(fake.item(service: deviceService, account: deviceAccount, dataProtection: false), Data("550E8400-E29B-41D4-A716-446655440000".utf8), "the login keychain item is not deleted before a replacement exists")
            XCTAssertNil(fake.item(service: deviceService, account: deviceAccount, dataProtection: true))
            XCTAssertNil(defaults.string(forKey: "device-uuid-fallback"))
            // Second launch (3.2.1 minted a new id here).
            DeviceIdentifier.resetForTesting()
            XCTAssertEqual(DeviceIdentifier.getOrCreateDeviceId(), "550E8400-E29B-41D4-A716-446655440000")
        }
    }

    func testDeviceIDMovesToTheDataProtectionKeychainOnlyAfterTheWriteSucceeded() throws {
        let fake = FakeKeychain(dataProtectionAvailable: true)
        fake.set(Data("550E8400-E29B-41D4-A716-446655440000".utf8), service: deviceService, account: deviceAccount, dataProtection: false)
        try withFakeDeviceStorage(fake) { _ in
            XCTAssertEqual(DeviceIdentifier.getOrCreateDeviceId(), "550E8400-E29B-41D4-A716-446655440000")
            XCTAssertEqual(fake.item(service: deviceService, account: deviceAccount, dataProtection: true), Data("550E8400-E29B-41D4-A716-446655440000".utf8))
            XCTAssertNil(fake.item(service: deviceService, account: deviceAccount, dataProtection: false), "moved, so the legacy copy is gone")
            DeviceIdentifier.resetForTesting()
            XCTAssertEqual(DeviceIdentifier.getOrCreateDeviceId(), "550E8400-E29B-41D4-A716-446655440000")
        }
    }

    func testFreshDeviceIDIsKeptInTheLoginKeychainWhenDataProtectionIsUnavailable() throws {
        let fake = FakeKeychain(dataProtectionAvailable: false)
        try withFakeDeviceStorage(fake) { defaults in
            let minted = DeviceIdentifier.getOrCreateDeviceId()
            XCTAssertNotNil(UUID(uuidString: minted))
            XCTAssertEqual(fake.item(service: deviceService, account: deviceAccount, dataProtection: false), Data(minted.utf8))
            XCTAssertNil(defaults.string(forKey: "device-uuid-fallback"), "the login keychain is persistence enough; no UserDefaults fallback")
            DeviceIdentifier.resetForTesting()
            XCTAssertEqual(DeviceIdentifier.getOrCreateDeviceId(), minted)
        }
    }

    /// A2a: the two stores read together. Every primary answer crossed with every login
    /// keychain answer; both read models of the shipped build (data protection reads answer
    /// "not found", or answer -34018) are rows here.
    func testKeychainSlotClassifiesBothStoresTogether() throws {
        enum Answer { case found, missing, unreadable(OSStatus) }
        let locked: OSStatus = -25308   // errSecInteractionNotAllowed
        let denied: OSStatus = -25293   // errSecAuthFailed
        let primaryAnswers: [Answer] = [.found, .missing, .unreadable(locked), .unreadable(denied), .unreadable(KeychainSlot.missingEntitlement)]
        let loginAnswers: [Answer] = [.found, .missing, .unreadable(locked)]
        let dpData = Data("dp".utf8)
        let loginData = Data("login".utf8)

        for primary in primaryAnswers {
            for login in loginAnswers {
                let fake = FakeKeychain(dataProtectionAvailable: true)
                switch primary {
                case .found: fake.set(dpData, service: "s", account: "a", dataProtection: true)
                case .missing: break
                case .unreadable(let status): fake.failReads(dataProtection: true, with: status)
                }
                switch login {
                case .found: fake.set(loginData, service: "s", account: "a", dataProtection: false)
                case .missing: break
                case .unreadable(let status): fake.failReads(dataProtection: false, with: status)
                }
                let slot = KeychainSlot(service: "s", account: "a", accessible: kSecAttrAccessibleAfterFirstUnlock, backend: fake)
                let result = slot.read()
                let label = "primary=\(primary) login=\(login)"

                switch (primary, login) {
                case (.found, _):
                    XCTAssertEqual(result, .found(dpData), label)
                case (.unreadable(KeychainSlot.missingEntitlement), .found):
                    XCTAssertEqual(result, .found(loginData), label)
                case (.unreadable(KeychainSlot.missingEntitlement), .missing):
                    XCTAssertEqual(result, .missing, "\(label): -34018 means this build cannot use the primary store; the login answer is the real one")
                case (.unreadable(KeychainSlot.missingEntitlement), .unreadable(let status)):
                    XCTAssertEqual(result, .unreadable(status), label)
                case (.unreadable(let status), .found):
                    XCTAssertEqual(result, .found(loginData), label)
                    _ = status
                case (.unreadable(let status), _):
                    XCTAssertEqual(result, .unreadable(status), "\(label): the primary store's own refusal is reported")
                case (.missing, .found):
                    XCTAssertEqual(result, .found(loginData), label)
                    XCTAssertEqual(fake.item(service: "s", account: "a", dataProtection: true), loginData, "\(label): moved into the primary store")
                case (.missing, .missing):
                    XCTAssertEqual(result, .missing, label)
                case (.missing, .unreadable(let status)):
                    XCTAssertEqual(result, .unreadable(status), "\(label): a locked login keychain is not absence (the 3.3.0 gap)")
                }
            }
        }
    }

    func testALockedLoginKeychainIsReportedAsUnreadableNotAsNoCredential() throws {
        // The shipped Developer ID build: data protection reads answer "not found" (postmortem
        // model) and the login keychain is locked.
        let fake = FakeKeychain(dataProtectionAvailable: false)
        fake.failReads(dataProtection: false, with: -25308)
        let store = KeychainClientAuthStore(backend: fake)
        XCTAssertNil(store.load(), "A1 and A2a: still nil for callers; A3 changes what the manager does with it")
        XCTAssertEqual(store.lastLoadDiagnostic, .unreadable(status: -25308))
        let manager = ClientAuthManager(store: store, deviceIDProvider: { "d" })
        let events = EventCollector()
        manager.attachEventSink { events.append($0) }
        XCTAssertEqual(events.names, ["client_auth_credential_unreadable"])
        XCTAssertEqual(events.all.first?.details["status"], "-25308")
    }

    func testCredentialStoreFallsBackToTheLoginKeychainAndReadsLegacyItems() throws {
        let fake = FakeKeychain(dataProtectionAvailable: false)
        let store = KeychainClientAuthStore(backend: fake)
        // A 3.2.0 credential in the login keychain is read as is.
        let legacy = credentials()
        fake.set(try JSONEncoder().encode(legacy), service: "com.miniti.device-auth", account: "credentials", dataProtection: false)
        XCTAssertEqual(store.load(), legacy)
        XCTAssertNotNil(fake.item(service: "com.miniti.device-auth", account: "credentials", dataProtection: false), "not deleted while the move cannot happen")
        // A token refresh saves back into the login keychain, in place.
        var refreshed = legacy
        refreshed.accessToken = "tok2"
        XCTAssertTrue(store.save(refreshed))
        XCTAssertEqual(store.load(), refreshed)
        XCTAssertEqual(fake.addCount(service: "com.miniti.device-auth", account: "credentials", dataProtection: false), 0, "the existing item was updated, never re-created")
        store.clear()
        XCTAssertNil(store.load())
    }
    #endif
    // MARK: - A2 enrollment coordinator

    /// Records every hook call so a test can assert the order of side effects.
    @MainActor
    private final class CoordinatorHost {
        var sessionOnly = false
        var statusEnrolled = false
        var enrolling: [Bool] = []
        var errors: [String?] = []
        var refreshes = 0
        var events: [(String, [String: String])] = []
        var logs: [String] = []

        // Strong captures on purpose: the coordinator owns the hooks, and a test may drop its
        // own reference to the host while the coordinator still reports into it.
        func hooks() -> ManagedEnrollmentCoordinator.Hooks {
            .init(
                deviceIDIsSessionOnly: { self.sessionOnly },
                deviceLabel: { "Mac" },
                statusIsEnrolled: { self.statusEnrolled },
                setEnrolling: { self.enrolling.append($0) },
                setError: { self.errors.append($0) },
                refreshStatus: { self.refreshes += 1 },
                event: { name, _, details in self.events.append((name, details)) },
                log: { self.logs.append($0) }
            )
        }
    }

    private enum Paths { nonisolated(unsafe) static var hits: [String] = [] }

    /// A manager wired to the stub; the handler maps each auth path to an answer.
    @MainActor
    private func coordinatorFixture(
        enrolled: Bool = false,
        rotator: (@Sendable () -> String)? = nil,
        answers: @escaping @Sendable (String, [String: Any]) -> (Int, Data)
    ) -> (ManagedEnrollmentCoordinator, CoordinatorHost, ClientAuthManager) {
        let store = InMemoryClientAuthStore(enrolled ? credentials() : nil)
        // The provider follows the rotator, as DeviceIdentifier does for the real manager.
        nonisolated(unsafe) var currentID = "550e8400-e29b-41d4-a716-446655440000"
        let manager = ClientAuthManager(
            store: store, baseURL: "https://api.test/api", session: stubbedSession(),
            deviceIDProvider: { currentID },
            deviceIDRotator: rotator.map { rotate in { currentID = rotate(); return currentID } }
        )
        Paths.hits = []
        StubURLProtocol.handler = { [self] request in
            let path = request.url?.path ?? ""
            Paths.hits.append(path)
            if path == "/api/auth/challenge" { return (200, Data(#"{"challenge_id":"c1","nonce":"n1","expires_in":120}"#.utf8)) }
            return answers(path, requestBody(request))
        }
        let host = CoordinatorHost()
        let coordinator = ManagedEnrollmentCoordinator(manager: manager, hooks: host.hooks())
        return (coordinator, host, manager)
    }

    private static func tokens(_ account: String, device: String = "550e8400-e29b-41d4-a716-446655440000") -> (Int, Data) {
        (200, Data("""
        {"token_type":"Bearer","access_token":"tok","expires_in":3600,"refresh_token":"mrt_a","refresh_expires_in":7776000,"account_id":"\(account)","device_id":"\(device)","device_cap":5}
        """.utf8))
    }

    private static func failure(_ status: Int, _ error: String) -> (Int, Data) {
        (status, Data("{\"error\":\"\(error)\",\"message\":\"x\"}".utf8))
    }

    @MainActor
    func testCoordinatorMigratesAnEligibleLegacyDevice() async {
        let (coordinator, host, manager) = coordinatorFixture { path, _ in
            path == "/api/auth/migrate" ? Self.tokens("acct_legacy") : Self.failure(500, "unexpected")
        }
        defer { StubURLProtocol.handler = nil }
        let ok = await coordinator.ensure(trigger: "usage")
        XCTAssertTrue(ok)
        XCTAssertTrue(manager.isEnrolled)
        XCTAssertEqual(manager.status.enrollmentPath, "migrate")
        XCTAssertFalse(Paths.hits.contains("/api/auth/account/create"), "migrate first, create never needed")
        XCTAssertEqual(host.enrolling, [true, false])
        XCTAssertEqual(host.errors, [nil])
        XCTAssertEqual(host.events.map(\.0), ["client_auth_migrated"])
        XCTAssertEqual(host.refreshes, 1)
    }

    @MainActor
    func testCoordinatorCreatesWhenNotEligibleForMigration() async {
        let (coordinator, host, manager) = coordinatorFixture { path, _ in
            switch path {
            case "/api/auth/migrate": return Self.failure(404, "device_not_eligible")
            case "/api/auth/account/create": return Self.tokens("acct_new")
            default: return Self.failure(500, "unexpected")
            }
        }
        defer { StubURLProtocol.handler = nil }
        let outcome1 = await coordinator.ensure(trigger: "start")
        XCTAssertTrue(outcome1)
        XCTAssertEqual(manager.status.accountID, "acct_new")
        XCTAssertEqual(manager.status.enrollmentPath, "create")
        XCTAssertEqual(host.events.map(\.0), ["client_auth_created"])
        XCTAssertEqual(host.errors, [nil])
    }

    @MainActor
    func testCoordinatorFallsBackToCreateWhenMigrateSaysAlreadyEnrolled() async {
        let (coordinator, _, manager) = coordinatorFixture { path, _ in
            switch path {
            case "/api/auth/migrate": return Self.failure(409, "device_already_enrolled")
            case "/api/auth/account/create": return Self.tokens("acct_new")
            default: return Self.failure(500, "unexpected")
            }
        }
        defer { StubURLProtocol.handler = nil }
        let outcome2 = await coordinator.ensure(trigger: "start")
        XCTAssertTrue(outcome2)
        XCTAssertEqual(manager.status.accountID, "acct_new")
        XCTAssertEqual(Paths.hits.filter { $0 == "/api/auth/account/create" }.count, 1)
    }

    @MainActor
    func testCoordinatorRotatesOnceWhenCreateConflicts() async {
        nonisolated(unsafe) var rotations = 0
        let (coordinator, host, manager) = coordinatorFixture(rotator: { rotations += 1; return "11111111-2222-4333-8444-555555555555" }) { path, body in
            switch path {
            case "/api/auth/migrate": return Self.failure(404, "device_not_eligible")
            case "/api/auth/account/create":
                let id = body["device_id"] as? String ?? ""
                return id == "550e8400-e29b-41d4-a716-446655440000" ? Self.failure(409, "device_already_enrolled") : Self.tokens("acct_rotated", device: id)
            default: return Self.failure(500, "unexpected")
            }
        }
        defer { StubURLProtocol.handler = nil }
        let outcome3 = await coordinator.ensure(trigger: "start")
        XCTAssertTrue(outcome3)
        XCTAssertEqual(rotations, 1, "the rotator is counted once")
        XCTAssertEqual(manager.status.accountID, "acct_rotated")
        XCTAssertEqual(host.events.map(\.0), ["client_auth_created"])
    }

    @MainActor
    func testCoordinatorDefersWhileTheDeviceIDIsSessionOnlyAndMakesNoRequest() async {
        let (coordinator, host, manager) = coordinatorFixture { _, _ in Self.failure(500, "unexpected") }
        defer { StubURLProtocol.handler = nil }
        host.sessionOnly = true
        let outcome4 = await coordinator.ensure(trigger: "usage")
        XCTAssertFalse(outcome4)
        XCTAssertTrue(Paths.hits.isEmpty, "no network call while the id is temporary")
        XCTAssertFalse(manager.isEnrolled)
        XCTAssertEqual(host.enrolling, [])
        XCTAssertTrue(host.logs.contains { $0.hasPrefix("enrollment_deferred_session_only_device_id trigger=usage") })
    }

    @MainActor
    func testCoordinatorReturnsTrueWithoutNetworkWhenAlreadyEnrolledAndRefreshesALaggingStatus() async {
        let (coordinator, host, _) = coordinatorFixture(enrolled: true) { _, _ in Self.failure(500, "unexpected") }
        defer { StubURLProtocol.handler = nil }
        host.statusEnrolled = false
        let outcome5 = await coordinator.ensure(trigger: "settings")
        XCTAssertTrue(outcome5)
        XCTAssertTrue(Paths.hits.isEmpty)
        XCTAssertEqual(host.refreshes, 1, "the host's published status lagged and was refreshed")
        host.statusEnrolled = true
        let outcome6 = await coordinator.ensure(trigger: "settings")
        XCTAssertTrue(outcome6)
        XCTAssertEqual(host.refreshes, 1, "no refresh when the status already agrees")
        XCTAssertEqual(host.enrolling, [])
    }

    @MainActor
    func testCoordinatorSharesOneAttemptBetweenConcurrentCallers() async {
        let (coordinator, host, _) = coordinatorFixture { path, _ in
            switch path {
            case "/api/auth/migrate": return Self.failure(404, "device_not_eligible")
            case "/api/auth/account/create": return Self.tokens("acct_new")
            default: return Self.failure(500, "unexpected")
            }
        }
        defer { StubURLProtocol.handler = nil }
        async let first = coordinator.ensure(trigger: "start")
        async let second = coordinator.ensure(trigger: "usage")
        let results = await [first, second]
        XCTAssertEqual(results, [true, true])
        XCTAssertEqual(Paths.hits.filter { $0 == "/api/auth/account/create" }.count, 1, "one network sequence for two callers")
        XCTAssertEqual(host.enrolling, [true, false], "one attempt, one pair of mirror updates")
        XCTAssertFalse(coordinator.isAttemptInFlight)
    }

    @MainActor
    func testCoordinatorRemembersAFailureAndRetriesOnTheNextTrigger() async {
        nonisolated(unsafe) var createAnswer: (Int, Data) = Self.failure(503, "client_auth_unavailable")
        let (coordinator, host, manager) = coordinatorFixture { path, _ in
            switch path {
            case "/api/auth/migrate": return Self.failure(404, "device_not_eligible")
            case "/api/auth/account/create": return createAnswer
            default: return Self.failure(500, "unexpected")
            }
        }
        defer { StubURLProtocol.handler = nil }
        let outcome7 = await coordinator.ensure(trigger: "start")
        XCTAssertFalse(outcome7)
        XCTAssertFalse(manager.isEnrolled)
        XCTAssertNotNil(host.errors.last ?? nil, "the failure is remembered for the host to show")
        XCTAssertEqual(host.events.map(\.0), ["client_auth_enrollment_failed"])
        XCTAssertEqual(host.events.last?.1, ["path": "create"])
        XCTAssertEqual(host.enrolling, [true, false])
        XCTAssertEqual(host.refreshes, 1)

        createAnswer = Self.tokens("acct_new")
        let outcome8 = await coordinator.ensure(trigger: "usage")
        XCTAssertTrue(outcome8)
        XCTAssertTrue(manager.isEnrolled)
        XCTAssertNil(host.errors.last ?? nil, "cleared on success")
        XCTAssertEqual(host.enrolling, [true, false, true, false])
    }

    @MainActor
    func testCoordinatorReportsAMigrateFailureOnItsOwnPath() async {
        let (coordinator, host, _) = coordinatorFixture { path, _ in
            path == "/api/auth/migrate" ? Self.failure(503, "client_auth_unavailable") : Self.failure(500, "unexpected")
        }
        defer { StubURLProtocol.handler = nil }
        let outcome9 = await coordinator.ensure(trigger: "start")
        XCTAssertFalse(outcome9)
        XCTAssertFalse(Paths.hits.contains("/api/auth/account/create"), "a 503 on migrate is not a reason to create")
        XCTAssertEqual(host.events.last?.0, "client_auth_enrollment_failed")
        XCTAssertEqual(host.events.last?.1, ["path": "migrate"])
    }

}

// MARK: - A1 fixtures

/// Collects `ClientAuthEvent`s from a sink; thread-safe because the sink may run off the test thread.
private final class EventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var all: [ClientAuthEvent] = []
    var names: [String] { lock.lock(); defer { lock.unlock() }; return all.map(\.name) }
    func append(_ event: ClientAuthEvent) { lock.lock(); defer { lock.unlock() }; all.append(event) }
}

/// A store that reports a load diagnostic (unreadable or undecodable) and may refuse saves.
private final class DiagnosticClientAuthStore: ClientAuthCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: ClientAuthCredentials?
    private let diagnostic: ClientAuthStoreDiagnostic?
    private var saveAllowed: Bool
    var saveSucceeds: Bool {
        get { lock.lock(); defer { lock.unlock() }; return saveAllowed }
        set { lock.lock(); defer { lock.unlock() }; saveAllowed = newValue }
    }

    init(diagnostic: ClientAuthStoreDiagnostic?, saveSucceeds: Bool = true) {
        self.diagnostic = diagnostic
        self.saveAllowed = saveSucceeds
    }

    var lastLoadDiagnostic: ClientAuthStoreDiagnostic? { diagnostic }
    func load() -> ClientAuthCredentials? { lock.lock(); defer { lock.unlock() }; return diagnostic == nil ? value : nil }
    func save(_ credentials: ClientAuthCredentials) -> Bool {
        guard saveSucceeds else { return false }
        lock.lock(); defer { lock.unlock() }; value = credentials; return true
    }
    func clear() { lock.lock(); defer { lock.unlock() }; value = nil }
}
