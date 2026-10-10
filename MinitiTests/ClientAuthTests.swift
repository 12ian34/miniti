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

        _ = try await manager.createAccount()
        XCTAssertEqual(rotations, 1)
        XCTAssertEqual(createIDs, ["550e8400-e29b-41d4-a716-446655440000", "11111111-2222-4333-8444-555555555555"])
        XCTAssertTrue(manager.isEnrolled)
        XCTAssertEqual(manager.status.accountID, "acct_fresh")
        XCTAssertEqual(manager.status.enrollmentPath, "create")
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
        do {
            _ = try await manager.createAccount()
            XCTFail("expected deviceAlreadyEnrolled")
        } catch {
            XCTAssertEqual(error as? ClientAuthError, .deviceAlreadyEnrolled)
        }
        XCTAssertFalse(manager.isEnrolled)
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
}
