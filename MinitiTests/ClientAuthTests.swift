import XCTest
import CryptoTokenKit
import CryptoKit
import SwiftData
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

    // MARK: - A2d: a key this machine cannot use

    /// A credential whose software key is real, with a recovery key unless `recoveryKey` says otherwise.
    private func repairableCredentials(recoveryKey: String? = nil) -> (ClientAuthCredentials, InstallationKey) {
        let key = InstallationKey.generate(preferSecureEnclave: false)
        let stored = ClientAuthCredentials(
            installationKey: key.stored,
            recoveryKey: recoveryKey ?? ClientAuthCrypto.generateRecoveryKey(),
            accountID: "acct_same",
            accessToken: "cached-bearer",
            accessExpiresAt: Int64(Date().timeIntervalSince1970) + 3600,
            refreshToken: "mrt_cached",
            deviceCap: 5,
            enrolledAt: "2026-10-21T18:25:09Z",
            enrollmentPath: "restore",
            recoveryKeyAcknowledged: true
        )
        return (stored, key)
    }

    /// A loader that applies `fault` to signatures made with the original key only, so a
    /// repaired credential loads cleanly, as a real machine's fresh key would.
    private func signingFaultLoader(for original: InstallationKey.Stored, domain: String, code: Int) -> @Sendable (InstallationKey.Stored) -> Result<InstallationKey, Error> {
        { stored in
            InstallationKey.load(stored: stored).map { key in
                stored == original ? InstallationKey(backing: key.backing, signingFault: NSError(domain: domain, code: code)) : key
            }
        }
    }

    /// Bytes that cannot be a key: the one load failure that is unusable without a device code.
    private func unloadableLoader(for original: InstallationKey.Stored) -> @Sendable (InstallationKey.Stored) -> Result<InstallationKey, Error> {
        { stored in stored == original ? .failure(InstallationKey.LoadError.corruptData) : InstallationKey.load(stored: stored) }
    }

    private enum Restore {
        nonisolated(unsafe) static var hits = 0
        nonisolated(unsafe) static var jwkX: [String] = []
        nonisolated(unsafe) static var answer: (Int, Data) = (200, Data())
    }

    /// Stub: challenges succeed; restore answers `Restore.answer`; everything else is unexpected.
    private func restoreStub(account: String = "acct_same") {
        Restore.hits = 0
        Restore.jwkX = []
        Restore.answer = Self.tokens(account)
        StubURLProtocol.handler = { [self] request in
            switch request.url?.path ?? "" {
            case "/api/auth/challenge": return (200, Data(#"{"challenge_id":"c1","nonce":"n1","expires_in":120}"#.utf8))
            case "/api/auth/account/restore":
                Restore.hits += 1
                if let jwk = requestBody(request)["public_key_jwk"] as? [String: Any], let x = jwk["x"] as? String { Restore.jwkX.append(x) }
                return Restore.answer
            default: return Self.failure(500, "unexpected:\(request.url?.path ?? "")")
            }
        }
    }

    private func managerFor(_ stored: ClientAuthCredentials, store: ClientAuthCredentialStore? = nil, loader: @escaping @Sendable (InstallationKey.Stored) -> Result<InstallationKey, Error>) -> ClientAuthManager {
        ClientAuthManager(
            store: store ?? InMemoryClientAuthStore(stored),
            baseURL: "https://api.test/api", session: stubbedSession(),
            deviceIDProvider: { "550e8400-e29b-41d4-a716-446655440000" },
            deviceLabelProvider: { "Mac" },
            keyLoader: loader,
            defaults: UserDefaults(suiteName: "test_auth_\(UUID().uuidString)")!
        )
    }

    private func postRequest() -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.test/api/session")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        return request
    }

    func testAKeyThatCannotLoadIsReplacedThroughRestoreOnTheSameAccountAndDeviceID() async throws {
        let (stored, original) = repairableCredentials()
        let store = InMemoryClientAuthStore(stored)
        let manager = managerFor(stored, store: store, loader: unloadableLoader(for: stored.installationKey))
        let events = EventCollector()
        manager.attachEventSink { events.append($0) }
        restoreStub()
        defer { StubURLProtocol.handler = nil }

        XCTAssertTrue(manager.isEnrolled, "a repairable credential still counts as enrolled")
        var request = postRequest()
        try await manager.authorize(&request)

        XCTAssertNotNil(request.value(forHTTPHeaderField: "X-Request-Proof"), "the original request was signed after the repair")
        XCTAssertEqual(Restore.hits, 1)
        let after = try XCTUnwrap(store.load())
        XCTAssertNotEqual(after.installationKey, stored.installationKey, "a fresh key")
        XCTAssertEqual(after.recoveryKey, stored.recoveryKey, "the recovery key is kept")
        XCTAssertEqual(after.accountID, "acct_same")
        XCTAssertEqual(after.enrollmentPath, "restore")
        XCTAssertTrue(after.recoveryKeyAcknowledged)
        XCTAssertNotEqual(Restore.jwkX.first, original.publicJWK["x"], "the restore was proved with the new key")
        XCTAssertEqual(events.names, ["client_auth_key_unusable", "client_auth_repair_attempt", "client_auth_key_repaired", "client_auth_repair_outcome"])
        XCTAssertEqual(events.all[1].details["attempt_id"], events.all[3].details["attempt_id"])
        XCTAssertEqual(events.all[3].details["outcome"], "success")
        XCTAssertEqual(events.all[0].details["recovery"], "yes")
        XCTAssertEqual(events.all[0].details["phase"], "load")
        XCTAssertEqual(manager.credentialState, ClientAuthManager.CredentialState.enrolled)

        // The repaired key signs without any further request.
        var second = postRequest()
        try await manager.authorize(&second)
        XCTAssertEqual(Restore.hits, 1)
    }

    func testAnAllowListedSigningFailureIsRepairedEvenWhenTheCachedBearerSkippedRefresh() async throws {
        let (stored, _) = repairableCredentials()
        let store = InMemoryClientAuthStore(stored)
        let manager = managerFor(stored, store: store, loader: signingFaultLoader(for: stored.installationKey, domain: TKErrorDomain, code: -10))
        let events = EventCollector()
        manager.attachEventSink { events.append($0) }
        restoreStub()
        defer { StubURLProtocol.handler = nil }

        var request = postRequest()
        try await manager.authorize(&request)
        XCTAssertNotNil(request.value(forHTTPHeaderField: "X-Request-Proof"))
        XCTAssertEqual(Restore.hits, 1)
        XCTAssertNotEqual(store.load()?.installationKey, stored.installationKey)
        XCTAssertEqual(events.names, ["client_auth_key_unusable", "client_auth_repair_attempt", "client_auth_key_repaired", "client_auth_repair_outcome"])
        XCTAssertEqual(events.all[1].details["attempt_id"], events.all[3].details["attempt_id"])
        XCTAssertEqual(events.all[3].details["outcome"], "success")
        XCTAssertEqual(events.all[0].details["phase"], "sign")
        XCTAssertEqual(events.all[0].details["error_domain"], TKErrorDomain)
        XCTAssertEqual(events.all[0].details["error_code"], "-10")
    }

    func testATemporarySigningFailureKeepsTheKeyOffersRetryAndRecoversOnItsOwn() async throws {
        let (stored, _) = repairableCredentials()
        let store = InMemoryClientAuthStore(stored)
        let defaults = UserDefaults(suiteName: "test_auth_\(UUID().uuidString)")!
        // Three launches with a locked key: nothing replaced, no restore, the count rises.
        for launch in 1...3 {
            let manager = ClientAuthManager(store: store, baseURL: "https://api.test/api", session: stubbedSession(), deviceIDProvider: { "d" }, keyLoader: signingFaultLoader(for: stored.installationKey, domain: NSOSStatusErrorDomain, code: -25308), defaults: defaults)
            let events = EventCollector()
            manager.attachEventSink { events.append($0) }
            restoreStub()
            var request = postRequest()
            do {
                try await manager.authorize(&request)
                XCTFail("expected keyUnavailable")
            } catch {
                XCTAssertEqual(error as? ClientAuthError, .keyUnavailable("sign:\(NSOSStatusErrorDomain):-25308"))
            }
            XCTAssertEqual(Restore.hits, 0, "launch \(launch): nothing restored for a temporary failure")
            XCTAssertEqual(store.load()?.installationKey, stored.installationKey, "launch \(launch): the credential is untouched")
            XCTAssertTrue(manager.isEnrolled)
            XCTAssertEqual(manager.credentialState, ClientAuthManager.CredentialState.enrolled)
            XCTAssertEqual(manager.keyUnavailableLaunches, launch)
            XCTAssertEqual(events.names, ["client_auth_key_unavailable"])
            XCTAssertEqual(ClientAuthError.keyUnavailable("x").errorDescription, "miniti could not use its saved sign-in right now. Try again, or sign in again from Settings, Account.")
            StubURLProtocol.handler = nil
        }
        // Unlock: the original credential signs, nothing restored, the count is cleared.
        let healed = ClientAuthManager(store: store, baseURL: "https://api.test/api", session: stubbedSession(), deviceIDProvider: { "d" }, defaults: defaults)
        restoreStub()
        defer { StubURLProtocol.handler = nil }
        var request = postRequest()
        try await healed.authorize(&request)
        XCTAssertNotNil(request.value(forHTTPHeaderField: "X-Request-Proof"))
        XCTAssertEqual(Restore.hits, 0)
        XCTAssertEqual(store.load()?.installationKey, stored.installationKey)
        XCTAssertEqual(healed.keyUnavailableLaunches, 0)
    }

    func testTryAgainProbesTheExistingKeyLocallyAndNeverEnrolsOrRebinds() async throws {
        final class Lock: @unchecked Sendable { var engaged = true }
        let (stored, _) = repairableCredentials()
        let store = InMemoryClientAuthStore(stored)
        let lockBox = Lock()
        let original = stored.installationKey
        let loader: @Sendable (InstallationKey.Stored) -> Result<InstallationKey, Error> = { candidate in
            InstallationKey.load(stored: candidate).map { key in
                candidate == original && lockBox.engaged ? InstallationKey(backing: key.backing, signingFault: NSError(domain: NSOSStatusErrorDomain, code: -25308)) : key
            }
        }
        let manager = managerFor(stored, store: store, loader: loader)
        restoreStub()
        defer { StubURLProtocol.handler = nil }

        // The real request fails while the key is locked: temporary, reported as such.
        var request = postRequest()
        do { try await manager.authorize(&request); XCTFail("expected keyUnavailable") } catch {}
        XCTAssertTrue(manager.status.keyTemporarilyUnavailable)
        XCTAssertFalse(manager.status.keyUnusable)
        XCTAssertTrue(manager.keyNeedsReauthentication)

        // Try again while still locked: still temporary, same classification, no request.
        let requestsBefore = StubURLProtocol.requests.count
        XCTAssertFalse(manager.retrySigningProbe())
        XCTAssertTrue(manager.status.keyTemporarilyUnavailable)
        XCTAssertEqual(Restore.hits, 0)
        XCTAssertEqual(StubURLProtocol.requests.count, requestsBefore, "the probe is local")

        // Unlock, then Try again: the original key signs, the flag clears, nothing changed.
        lockBox.engaged = false
        XCTAssertTrue(manager.retrySigningProbe())
        XCTAssertFalse(manager.status.keyTemporarilyUnavailable)
        XCTAssertFalse(manager.keyNeedsReauthentication)
        XCTAssertTrue(manager.isEnrolled)
        XCTAssertEqual(store.load(), stored, "key, account and tokens untouched")
        XCTAssertEqual(Restore.hits, 0)
        XCTAssertEqual(StubURLProtocol.requests.count, requestsBefore, "no create, migrate, restore or re-bind left the device")
        var again = postRequest()
        try await again.setValueForTesting(manager)
        XCTAssertNotNil(again.value(forHTTPHeaderField: "X-Request-Proof"))
    }

    func testTryAgainOnAPermanentlyInvalidKeyIsNotCalledTemporary() async throws {
        let (stored, _) = repairableCredentials()
        let store = InMemoryClientAuthStore(stored)
        let manager = managerFor(stored, store: store, loader: unloadableLoader(for: stored.installationKey))
        let requestsBefore = StubURLProtocol.requests.count
        XCTAssertFalse(manager.retrySigningProbe())
        XCTAssertFalse(manager.status.keyTemporarilyUnavailable, "a permanent failure is classified permanent, not temporary")
        XCTAssertTrue(manager.keyNeedsReauthentication)
        XCTAssertEqual(store.load(), stored)
        XCTAssertEqual(StubURLProtocol.requests.count, requestsBefore)
    }

    @MainActor
    func testAPermanentProbeFailureWithARecoveryKeyStillReadsAsUnusableInAccount() throws {
        // Review 2026-10-27: a stored recovery key keeps enrolment alive while the coordinator
        // repairs, but the section must still offer Sign in again and hide signed actions.
        let (stored, _) = repairableCredentials()
        let manager = managerFor(stored, store: InMemoryClientAuthStore(stored), loader: unloadableLoader(for: stored.installationKey))
        let app = AppState()
        app.clientAuthManager = manager
        XCTAssertFalse(app.retrySigning())
        XCTAssertTrue(manager.keyNeedsReauthentication)
        XCTAssertTrue(manager.isEnrolled, "the recovery key keeps enrolment alive")
        XCTAssertTrue(app.clientAuthStatus.keyPermanentlyUnavailable)
        XCTAssertFalse(app.clientAuthStatus.keyTemporarilyUnavailable)
        XCTAssertEqual(app.accountSectionInputs.keyState, .unusable)
        let model = AccountSectionModel.make(app.accountSectionInputs)
        XCTAssertTrue(model.accountActions.contains(.signInAgain))
        XCTAssertFalse(model.accountActions.contains(.switchAccount))
        XCTAssertEqual(model.recoveryKeyActions, [.showKey])
    }

    func testADelayedRepairCannotUndoASignOut() async throws {
        // Review 2026-10-27: sign out while the repair's restore answer is in flight.
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let (stored, _) = repairableCredentials()
        let store = InMemoryClientAuthStore(stored)
        let manager = managerFor(stored, store: store, loader: unloadableLoader(for: stored.installationKey))
        restoreStub()
        StubURLProtocol.delay = 0.3
        let repairing = Task {
            var request = self.postRequest()
            try await manager.authorize(&request)
        }
        for _ in 0..<200 {
            if StubURLProtocol.requests.contains(where: { $0.url?.path == "/api/auth/account/restore" }) { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(StubURLProtocol.requests.contains(where: { $0.url?.path == "/api/auth/account/restore" }))
        try await manager.signOut()
        XCTAssertFalse(manager.isEnrolled)
        _ = try? await repairing.value
        XCTAssertFalse(manager.isEnrolled, "a delayed repair must not undo a completed sign-out")
        XCTAssertNil(store.load(), "signed-out credentials must stay cleared")
    }

    func testAnOfflineLicenseRestoreReportsTheConnection() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let (stored, _) = repairableCredentials()
        let manager = managerFor(stored, loader: { InstallationKey.load(stored: $0) })
        let api = MinitiAPIService(session: stubbedSession(), auth: manager)
        StubURLProtocol.script = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await api.restoreSubscription(deviceId: "550e8400-e29b-41d4-a716-446655440000", licenseKey: "test-key")
            XCTFail("expected offline")
        } catch {
            let failure = AppState.restoreFailure(for: error)
            XCTAssertEqual(failure.code, "network")
            XCTAssertEqual(failure.message, "Could not reach miniti's servers. Check your connection and try again.")
        }
    }

    @MainActor
    func testTheCurrentDeviceRowSignsOutLocallyWithABrokenKey() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let (stored, _) = repairableCredentials(recoveryKey: "")
        let store = InMemoryClientAuthStore(stored)
        let manager = managerFor(stored, store: store, loader: unloadableLoader(for: stored.installationKey))
        XCTAssertFalse(manager.retrySigningProbe())
        let app = AppState()
        app.clientAuthManager = manager
        app.refreshClientAuthStatus()
        let removed = await app.removeManagedDevice(installationID: "550e8400-e29b-41d4-a716-446655440000")
        XCTAssertTrue(removed, "the current-device Sign out action works without a usable key")
        XCTAssertNil(store.load(), "through the local sign-out fallback")
        XCTAssertFalse(app.clientAuthStatus.isEnrolled)
    }

    func testASignOutDuringTheCredentialCommitCannotBeUndone() async throws {
        // Review 2026-10-27: the restore answer passed the epoch check; its store write is
        // outstanding when the local clear lands. The commit is ordered against the clear.
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let (stored, _) = repairableCredentials()
        let store = SaveGateStore(stored)
        let manager = managerFor(stored, store: store, loader: unloadableLoader(for: stored.installationKey))
        restoreStub()
        let repairing = Task { try await manager.repairUnusableKey() }
        let entered = await Task.detached { store.entered.wait(timeout: .now() + 3) == .success }.value
        XCTAssertTrue(entered)
        let clearing = Task.detached { manager.clearLocal(reason: "signout") }
        try await Task.sleep(nanoseconds: 100_000_000)
        store.release.signal()
        await clearing.value
        _ = try? await repairing.value
        XCTAssertFalse(manager.isEnrolled, "the commit must be ordered atomically against a local clear")
        XCTAssertNil(store.load(), "the persistent credential must stay cleared")
    }

    @MainActor
    func testOwnDeviceSignOutOfflineReportsFailureAndStaysSignedIn() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let (stored, _) = repairableCredentials()
        let store = InMemoryClientAuthStore(stored)
        let manager = managerFor(stored, store: store, loader: { InstallationKey.load(stored: $0) })
        StubURLProtocol.script = { _ in throw URLError(.notConnectedToInternet) }
        let app = AppState()
        app.clientAuthManager = manager
        app.refreshClientAuthStatus()
        let success = await app.removeManagedDevice(installationID: "550e8400-e29b-41d4-a716-446655440000")
        XCTAssertFalse(success, "offline: the revoke could not be proved, so no success")
        XCTAssertTrue(manager.isEnrolled, "and the device stays signed in")
        XCTAssertNotNil(store.load())
        XCTAssertTrue(app.clientAuthStatus.isEnrolled)
        XCTAssertEqual(app.managedDevicesError, "No connection. Signing out tells miniti's servers to forget this device, so it needs the network. Try again when you are online.")
        let direct = await app.signOutManagedDevice()
        XCTAssertFalse(direct)
    }

    func testATokenRefreshCommitCannotUndoALocalClear() async throws {
        // Review of f3ee4d9: the refresh answer is being written when the clear lands.
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let (stored, _) = repairableCredentials()
        let store = SaveGateStore(stored)
        let manager = managerFor(stored, store: store, loader: { InstallationKey.load(stored: $0) })
        StubURLProtocol.handler = { _ in Self.tokens("acct_same") }
        let refreshing = Task { try await manager.forceRefresh() }
        let entered = await Task.detached { store.entered.wait(timeout: .now() + 3) == .success }.value
        XCTAssertTrue(entered)
        let clearing = Task.detached { manager.clearLocal(reason: "signout") }
        try await Task.sleep(nanoseconds: 100_000_000)
        store.release.signal()
        await clearing.value
        _ = try? await refreshing.value
        XCTAssertFalse(manager.isEnrolled, "a token-only commit must not resurrect cleared credentials")
        XCTAssertNil(store.load(), "the persistent credential must stay cleared")
    }

    func testARefreshAnswerAfterAClearAndReEnrolmentIsRefusedAndNeverLandsOnTheNewCredential() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let (stored, _) = repairableCredentials()
        let store = InMemoryClientAuthStore(stored)
        let manager = managerFor(stored, store: store, loader: { InstallationKey.load(stored: $0) })
        // The old account's refresh is slow; meanwhile the device signs out and signs in to another account.
        StubURLProtocol.handler = { request in
            if request.url?.path == "/api/auth/token" { return Self.tokens("acct_old") }
            return (404, Data())
        }
        StubURLProtocol.delay = 0.4
        let refreshing = Task { try await manager.forceRefresh() }
        try await Task.sleep(nanoseconds: 50_000_000)
        StubURLProtocol.delay = 0
        manager.clearLocal(reason: "signout")
        restoreStub(account: "acct_new")
        // The restore stub answers the re-enrolment; the slow refresh still gets the old account's tokens.
        let restoreHandler = StubURLProtocol.handler!
        StubURLProtocol.handler = { request in
            request.url?.path == "/api/auth/token" ? Self.tokens("acct_old") : restoreHandler(request)
        }
        try await manager.restoreAccount(recoveryKeyInput: ClientAuthCrypto.formatRecoveryKey(ClientAuthCrypto.generateRecoveryKey()))
        XCTAssertEqual(store.load()?.accountID, "acct_new")
        let newToken = store.load()?.accessToken
        do {
            _ = try await refreshing.value
            XCTFail("a stale refresh must not return a usable token")
        } catch {
            XCTAssertEqual(error as? ClientAuthError, .notEnrolled)
        }
        XCTAssertEqual(store.load()?.accountID, "acct_new", "the old account's tokens never overwrite the new credential")
        XCTAssertEqual(store.load()?.accessToken, newToken)
        XCTAssertEqual(manager.status.accountID, "acct_new")
    }

    func testAKeyRotationAnswerAfterAClearIsRefused() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let (stored, _) = repairableCredentials()
        let store = InMemoryClientAuthStore(stored)
        let manager = managerFor(stored, store: store, loader: { InstallationKey.load(stored: $0) })
        StubURLProtocol.handler = { _ in (200, Data("{}".utf8)) }
        StubURLProtocol.delay = 0.3
        let rotating = Task { try await manager.rotateRecoveryKey() }
        try await Task.sleep(nanoseconds: 50_000_000)
        StubURLProtocol.delay = 0
        manager.clearLocal(reason: "signout")
        do {
            _ = try await rotating.value
            XCTFail("the rotation landed after the clear")
        } catch {
            XCTAssertEqual(error as? ClientAuthError, .notEnrolled)
        }
        XCTAssertNil(store.load())
        XCTAssertFalse(manager.isEnrolled)
    }

    func testACloudRequestsRetryNeverRunsUnderANewerCredential() async throws {
        // Review 2026-10-27: a delete on A answered token_expired after a switch to B must not be
        // replayed with B's credential.
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let (stored, _) = repairableCredentials()
        let store = InMemoryClientAuthStore(stored)
        let manager = managerFor(stored, store: store, loader: { InstallationKey.load(stored: $0) })
        let api = MinitiAPIService(session: stubbedSession(), auth: manager)
        restoreStub(account: "acct_new")
        let restoreHandler = StubURLProtocol.handler!
        StubURLProtocol.handler = { request in
            if request.url?.path.contains("/sync/meetings/") == true {
                if request.value(forHTTPHeaderField: "Authorization") == "Bearer cached-bearer" {
                    return Self.failure(401, "token_expired")
                }
                return (200, Data(#"{"revision":2}"#.utf8))
            }
            if request.url?.path == "/api/auth/token" { return Self.tokens("acct_new") }
            return restoreHandler(request)
        }
        StubURLProtocol.delay = 0.4
        let deleting = Task { try await api.deleteMeeting(id: UUID(), baseRevision: 1) }
        try await TestSupport.waitUntil { StubURLProtocol.requests.contains { $0.url?.path.contains("/sync/meetings/") == true } }
        StubURLProtocol.delay = 0
        manager.clearLocal(reason: "signout")
        try await manager.restoreAccount(recoveryKeyInput: ClientAuthCrypto.formatRecoveryKey(ClientAuthCrypto.generateRecoveryKey()))
        XCTAssertEqual(store.load()?.accountID, "acct_new")
        _ = try? await deleting.value
        let deletes = StubURLProtocol.requests.filter { $0.httpMethod == "DELETE" && $0.url?.path.contains("/sync/meetings/") == true }
        XCTAssertEqual(deletes.count, 1, "A's delayed 401 must not replay the delete using B's credential")
        XCTAssertFalse(deletes.contains { $0.value(forHTTPHeaderField: "Authorization") == "Bearer tok" })
        XCTAssertEqual(store.load()?.accountID, "acct_new")
    }

    func testAStaleRevocationAnswerDoesNotClearTheNewEnrolment() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let (stored, _) = repairableCredentials()
        let store = InMemoryClientAuthStore(stored)
        let manager = managerFor(stored, store: store, loader: { InstallationKey.load(stored: $0) })
        restoreStub(account: "acct_new")
        let restoreHandler = StubURLProtocol.handler!
        StubURLProtocol.handler = { request in
            request.url?.path == "/api/auth/token" ? Self.failure(401, "installation_revoked") : restoreHandler(request)
        }
        StubURLProtocol.delay = 0.4
        let refreshing = Task { try await manager.forceRefresh() }
        try await TestSupport.waitUntil { StubURLProtocol.requests.contains { $0.url?.path == "/api/auth/token" } }
        StubURLProtocol.delay = 0
        manager.clearLocal(reason: "signout")
        try await manager.restoreAccount(recoveryKeyInput: ClientAuthCrypto.formatRecoveryKey(ClientAuthCrypto.generateRecoveryKey()))
        XCTAssertEqual(store.load()?.accountID, "acct_new")
        do {
            _ = try await refreshing.value
            XCTFail("the stale refresh must not succeed")
        } catch {
            XCTAssertEqual(error as? ClientAuthError, .notEnrolled, "stale, not revoked: the current credential was never refused")
        }
        XCTAssertEqual(store.load()?.accountID, "acct_new", "an old revoked response must not clear the newly enrolled credential")
        XCTAssertEqual(manager.status.accountID, "acct_new")
        XCTAssertTrue(manager.isEnrolled)
    }

    func testRotationAfterAutomaticRepairKeepsTheAcceptedRecoveryKey() async throws {
        // Review 2026-10-27: the migrated key fails its first signature inside the rotation
        // request; the repair that follows is this request's own lineage, not a stale write.
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let (stored, _) = repairableCredentials()
        let store = InMemoryClientAuthStore(stored)
        let manager = managerFor(stored, store: store, loader: signingFaultLoader(for: stored.installationKey, domain: TKErrorDomain, code: -10))
        restoreStub(account: stored.accountID)
        let restoreHandler = StubURLProtocol.handler!
        StubURLProtocol.handler = { request in
            if request.url?.path.hasSuffix("/recovery-key/rotate") == true { return (200, Data("{}".utf8)) }
            return restoreHandler(request)
        }
        XCTAssertTrue(manager.isEnrolled)
        XCTAssertFalse(manager.keyNeedsReauthentication, "the migrated key has not failed its first signature yet")
        var failure: Error?
        do { _ = try await manager.rotateRecoveryKey() } catch { failure = error }
        let rotation = try XCTUnwrap(StubURLProtocol.requests.first { $0.url?.path.hasSuffix("/recovery-key/rotate") == true })
        let acceptedKey = try XCTUnwrap(requestBody(rotation)["new_recovery_key"] as? String)
        XCTAssertNotEqual(acceptedKey, stored.recoveryKey)
        XCTAssertEqual(store.load()?.recoveryKey, acceptedKey, "the server accepted this key; the old stored key no longer works")
        XCTAssertNil(failure, "same-account repair must allow the accepted rotation to commit")
        XCTAssertNotEqual(store.load()?.installationKey, stored.installationKey, "and the repaired key is the one kept")
    }

    func testAttachAfterAutomaticRepairCommitsAndASignOutAfterTheSendStillMakesItStale() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let (stored, _) = repairableCredentials()
        let store = InMemoryClientAuthStore(stored)
        let manager = managerFor(stored, store: store, loader: signingFaultLoader(for: stored.installationKey, domain: TKErrorDomain, code: -10))
        restoreStub(account: stored.accountID)
        let restoreHandler = StubURLProtocol.handler!
        let attach = #"{"moved":true,"access_token":"att","expires_in":3600,"refresh_token":"mrt_att","account_id":"acct_other","device_cap":5}"#
        StubURLProtocol.handler = { request in
            request.url?.path.hasSuffix("/auth/account/attach") == true ? (200, Data(attach.utf8)) : restoreHandler(request)
        }
        // Repair inside the attach request: the accepted move commits.
        let moved = try await manager.attachToAccount(recoveryKeyInput: ClientAuthCrypto.formatRecoveryKey(ClientAuthCrypto.generateRecoveryKey()))
        XCTAssertTrue(moved)
        XCTAssertEqual(store.load()?.accountID, "acct_other")
        XCTAssertEqual(store.load()?.accessToken, "att")

        // The email variant, with a sign-out landing while the answer is in flight: stale.
        StubURLProtocol.delay = 0.3
        let attaching = Task { try await manager.attachToAccount(loginLinkID: "link_1") }
        try await TestSupport.waitUntil { StubURLProtocol.requests.filter { $0.url?.path.hasSuffix("/auth/account/attach") == true }.count == 2 }
        StubURLProtocol.delay = 0
        manager.clearLocal(reason: "signout")
        do {
            _ = try await attaching.value
            XCTFail("an attach answered after a sign-out must not commit")
        } catch {
            XCTAssertEqual(error as? ClientAuthError, .notEnrolled)
        }
        XCTAssertNil(store.load())
    }

    func testASignedRequestKeepsItsOwnGenerationAcrossAuthorization() async throws {
        // Review 2026-10-27: the request signs with A; a sign-out and an enrolment of B land
        // before authorization returns; A's revoked answer must not clear B.
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let (stored, _) = repairableCredentials()
        let store = InMemoryClientAuthStore(stored)
        let gate = SigningDefaultsGate(suiteName: "AuthGate-\(UUID().uuidString)")!
        let manager = ClientAuthManager(store: store, baseURL: "https://api.test/api", session: stubbedSession(), deviceIDProvider: { "550e8400-e29b-41d4-a716-446655440000" }, defaults: gate)
        let api = MinitiAPIService(session: stubbedSession(), auth: manager)
        restoreStub(account: "acct_new")
        let restoreHandler = StubURLProtocol.handler!
        StubURLProtocol.handler = { request in
            if request.url?.path.contains("/sync/meetings/") == true { return Self.failure(401, "installation_revoked") }
            return restoreHandler(request)
        }
        let deleting = Task { try await api.deleteMeeting(id: UUID(), baseRevision: 1) }
        let signed = await Task.detached { gate.entered.wait(timeout: .now() + 3) == .success }.value
        XCTAssertTrue(signed)
        manager.clearLocal(reason: "signout")
        try await manager.restoreAccount(recoveryKeyInput: ClientAuthCrypto.formatRecoveryKey(ClientAuthCrypto.generateRecoveryKey()))
        XCTAssertEqual(store.load()?.accountID, "acct_new")
        gate.release.signal()
        _ = try? await deleting.value
        XCTAssertEqual(store.load()?.accountID, "acct_new", "an A-signed request must not acquire B's generation and clear B")
        XCTAssertEqual(manager.status.accountID, "acct_new")
        XCTAssertTrue(manager.isEnrolled)
    }

    func testADelayedSuccessfulSignOutDoesNotClearANewerEnrolment() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let (stored, _) = repairableCredentials()
        let store = InMemoryClientAuthStore(stored)
        let manager = managerFor(stored, store: store, loader: { InstallationKey.load(stored: $0) })
        restoreStub(account: "acct_new")
        let restoreHandler = StubURLProtocol.handler!
        StubURLProtocol.handler = { request in
            request.url?.path == "/api/auth/revoke" ? (200, Data("{}".utf8)) : restoreHandler(request)
        }
        StubURLProtocol.delay = 0.4
        let signingOut = Task { try await manager.signOut() }
        try await TestSupport.waitUntil { StubURLProtocol.requests.contains { $0.url?.path == "/api/auth/revoke" } }
        StubURLProtocol.delay = 0
        manager.clearLocal(reason: "signout")
        try await manager.restoreAccount(recoveryKeyInput: ClientAuthCrypto.formatRecoveryKey(ClientAuthCrypto.generateRecoveryKey()))
        XCTAssertEqual(store.load()?.accountID, "acct_new")
        let cleared = try? await signingOut.value
        XCTAssertEqual(cleared, false, "the old sign-out completed, but it cleared nothing of the new credential")
        XCTAssertEqual(store.load()?.accountID, "acct_new", "a completed old sign-out must not clear the new credential")
        XCTAssertEqual(manager.status.accountID, "acct_new")
    }

    func testAKeyFailureNeverRepairsANewerAccountToSendTheOldRequest() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let (stored, _) = repairableCredentials()
        let store = InMemoryClientAuthStore(stored)
        let manager = managerFor(stored, store: store, loader: signingFaultLoader(for: stored.installationKey, domain: TKErrorDomain, code: -10))
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        manager.attachEventSink { event in
            if event.name == "client_auth_key_unusable" {
                entered.signal()
                _ = release.wait(timeout: .now() + 5)
            }
        }
        restoreStub(account: "acct_new")
        let restoreHandler = StubURLProtocol.handler!
        StubURLProtocol.handler = { request in
            if request.url?.path.contains("/sync/meetings/") == true { return (200, Data(#"{"revision":2}"#.utf8)) }
            return restoreHandler(request)
        }
        let api = MinitiAPIService(session: stubbedSession(), auth: manager)
        let deleting = Task { try await api.deleteMeeting(id: UUID(), baseRevision: 1) }
        let failed = await Task.detached { entered.wait(timeout: .now() + 3) == .success }.value
        XCTAssertTrue(failed)
        manager.clearLocal(reason: "signout")
        try await manager.restoreAccount(recoveryKeyInput: ClientAuthCrypto.formatRecoveryKey(ClientAuthCrypto.generateRecoveryKey()))
        XCTAssertEqual(store.load()?.accountID, "acct_new")
        release.signal()
        _ = try? await deleting.value
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.url?.path.contains("/sync/meetings/") == true }, "A's failed signing must not repair B and send A's delete under B")
        XCTAssertEqual(Restore.hits, 1, "only the explicit enrolment of B was authorized; A's failure must not trigger another repair on B")
        XCTAssertEqual(store.load()?.accountID, "acct_new")
    }

    func testACompletedRepairDoesNotResumeTheOldRequestUnderANewerAccount() async throws {
        // Review 2026-10-27: pause after A's repair committed, enrol B, resume: A's request must
        // continue under A's replacement or not at all.
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let (stored, _) = repairableCredentials()
        let store = InMemoryClientAuthStore(stored)
        let manager = managerFor(stored, store: store, loader: signingFaultLoader(for: stored.installationKey, domain: TKErrorDomain, code: -10))
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        manager.attachEventSink { event in
            if event.name == "client_auth_key_repaired" {
                entered.signal()
                _ = release.wait(timeout: .now() + 5)
            }
        }
        restoreStub(account: stored.accountID)
        let restoreHandler = StubURLProtocol.handler!
        StubURLProtocol.handler = { request in
            if request.url?.path.contains("/sync/meetings/") == true { return (200, Data(#"{"revision":2}"#.utf8)) }
            return restoreHandler(request)
        }
        let api = MinitiAPIService(session: stubbedSession(), auth: manager)
        let deleting = Task { try await api.deleteMeeting(id: UUID(), baseRevision: 1) }
        let repaired = await Task.detached { entered.wait(timeout: .now() + 3) == .success }.value
        XCTAssertTrue(repaired)
        XCTAssertEqual(store.load()?.accountID, stored.accountID)
        manager.clearLocal(reason: "signout")
        Restore.answer = Self.tokens("acct_new")
        try await manager.restoreAccount(recoveryKeyInput: ClientAuthCrypto.formatRecoveryKey(ClientAuthCrypto.generateRecoveryKey()))
        XCTAssertEqual(store.load()?.accountID, "acct_new")
        release.signal()
        _ = try? await deleting.value
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.url?.path.contains("/sync/meetings/") == true }, "A's completed repair must return A's replacement context, not whatever account is current afterwards")
        XCTAssertEqual(store.load()?.accountID, "acct_new")
    }

    @MainActor
    func testAnAlreadyRevokedSignOutReportsItsLocalClearSoBookkeepingRuns() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let (stored, _) = repairableCredentials()
        let store = InMemoryClientAuthStore(stored)
        let manager = managerFor(stored, store: store, loader: { InstallationKey.load(stored: $0) })
        StubURLProtocol.handler = { _ in Self.failure(401, "installation_revoked") }
        let app = AppState()
        app.clientAuthManager = manager
        app.refreshClientAuthStatus()
        let signedOut = await app.signOutManagedDevice()
        XCTAssertNil(store.load(), "the request's revoked handler already cleared this credential")
        XCTAssertTrue(signedOut, "this is a completed sign-out, not a stale operation; normal bookkeeping cleanup must run")
        XCTAssertFalse(app.clientAuthStatus.isEnrolled)
    }

    func testConcurrentCallersShareOneRepair() async throws {
        let (stored, _) = repairableCredentials()
        let manager = managerFor(stored, loader: unloadableLoader(for: stored.installationKey))
        restoreStub()
        defer { StubURLProtocol.handler = nil }
        async let a: Void = { var r = self.postRequest(); try await manager.authorize(&r) }()
        async let b: Void = { var r = self.postRequest(); try await manager.authorize(&r) }()
        async let c: Void = { var r = self.postRequest(); try await manager.authorize(&r) }()
        _ = try await (a, b, c)
        XCTAssertEqual(Restore.hits, 1, "one restore for three callers")
    }

    func testARepairRetriesAfterALostResponse() async throws {
        let (stored, _) = repairableCredentials()
        let store = InMemoryClientAuthStore(stored)
        let manager = managerFor(stored, store: store, loader: unloadableLoader(for: stored.installationKey))
        restoreStub()
        defer { StubURLProtocol.handler = nil }
        Restore.answer = Self.failure(503, "client_auth_unavailable")
        var request = postRequest()
        do {
            try await manager.authorize(&request)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? ClientAuthError, .unavailable)
        }
        XCTAssertEqual(store.load()?.installationKey, stored.installationKey, "nothing changed while the restore failed")
        XCTAssertTrue(manager.isEnrolled)

        Restore.answer = Self.tokens("acct_same")
        var retry = postRequest()
        try await manager.authorize(&retry)
        XCTAssertEqual(Restore.hits, 2)
        XCTAssertNotEqual(store.load()?.installationKey, stored.installationKey)
    }

    func testARepairWhoseSaveFailsKeepsTheStateAndRestoresAgainNextTime() async throws {
        let (stored, _) = repairableCredentials()
        let store = DiagnosticClientAuthStore(diagnostic: nil, saveSucceeds: false, initial: stored)
        let manager = managerFor(stored, store: store, loader: unloadableLoader(for: stored.installationKey))
        restoreStub()
        defer { StubURLProtocol.handler = nil }
        var request = postRequest()
        do {
            try await manager.authorize(&request)
            XCTFail("expected storage")
        } catch {
            XCTAssertEqual(error as? ClientAuthError, .storage)
        }
        XCTAssertEqual(Restore.hits, 1)
        XCTAssertEqual(store.load()?.installationKey, stored.installationKey)
        XCTAssertTrue(manager.isEnrolled)

        store.saveSucceeds = true
        var retry = postRequest()
        try await manager.authorize(&retry)
        XCTAssertEqual(Restore.hits, 2, "the server replaced the key a second time; no cap slot, no new account")
        XCTAssertNotEqual(store.load()?.installationKey, stored.installationKey)
    }

    @MainActor
    func testAnEmailJoinedCredentialWithAnUnusableKeyWaitsForAChoiceAndRestoresByEmail() async throws {
        // The 2026-10-26 case: joined by email (no recovery key), Secure Enclave key refuses to sign.
        let (stored, _) = repairableCredentials(recoveryKey: "")
        let store = InMemoryClientAuthStore(stored)
        let loader = signingFaultLoader(for: stored.installationKey, domain: TKErrorDomain, code: -10)
        let (coordinator, host, manager) = coordinatorFixture(storedCredentials: stored, keyLoader: loader) { path, _ in
            path == "/api/auth/account/restore" ? Self.tokens("acct_same") : Self.failure(500, "unexpected")
        }
        _ = store
        let events = EventCollector()
        manager.attachEventSink { events.append($0) }
        defer { StubURLProtocol.handler = nil }

        var request = postRequest()
        do {
            try await manager.authorize(&request)
            XCTFail("expected keyUnusable")
        } catch {
            XCTAssertEqual(error as? ClientAuthError, .keyUnusable)
        }
        XCTAssertFalse(Paths.hits.contains("/api/auth/account/restore"), "no restore without a recovery key")
        XCTAssertEqual(manager.credentialState, ClientAuthManager.CredentialState.keyUnusable)
        XCTAssertFalse(manager.isEnrolled, "every gate sees not enrolled")
        XCTAssertTrue(manager.status.keyUnusable)
        XCTAssertEqual(manager.status.accountID, "acct_same", "the copy can still name the account")
        XCTAssertEqual(events.all.first?.details["recovery"], "no")

        // The coordinator neither migrates, creates nor rotates; it shows the way forward.
        Paths.hits = []
        let outcome = await coordinator.ensure(trigger: "start")
        XCTAssertFalse(outcome)
        XCTAssertTrue(Paths.hits.isEmpty, "no network: nothing created")
        XCTAssertEqual(host.errors.last ?? nil, ClientAuthError.keyUnusable.errorDescription)
        XCTAssertTrue(host.enrolling.isEmpty)

        // The approved email restores the same installation with a fresh key.
        try await manager.restoreAccount(loginLinkID: "lnk_approved", label: "Mac")
        XCTAssertEqual(manager.credentialState, ClientAuthManager.CredentialState.enrolled)
        XCTAssertTrue(manager.isEnrolled)
        XCTAssertEqual(manager.status.accountID, "acct_same")
        var signed = postRequest()
        try await manager.authorize(&signed)
        XCTAssertNotNil(signed.value(forHTTPHeaderField: "X-Request-Proof"))
        XCTAssertEqual(Paths.hits.filter { $0 == "/api/auth/account/restore" }.count, 1)
    }

    func testAnEmailForAnotherAccountLeavesTheUnusableCredentialUntouched() async throws {
        let (stored, _) = repairableCredentials(recoveryKey: "")
        let store = InMemoryClientAuthStore(stored)
        let manager = managerFor(stored, store: store, loader: signingFaultLoader(for: stored.installationKey, domain: TKErrorDomain, code: -10))
        StubURLProtocol.handler = { request in
            switch request.url?.path ?? "" {
            case "/api/auth/challenge": return (200, Data(#"{"challenge_id":"c1","nonce":"n1","expires_in":120}"#.utf8))
            default: return Self.failure(409, "device_already_enrolled")
            }
        }
        defer { StubURLProtocol.handler = nil }
        var request = postRequest()
        _ = try? await manager.authorize(&request)
        XCTAssertEqual(manager.credentialState, ClientAuthManager.CredentialState.keyUnusable)
        do {
            try await manager.restoreAccount(loginLinkID: "lnk_other", label: "Mac")
            XCTFail("expected deviceAlreadyEnrolled")
        } catch {
            XCTAssertEqual(error as? ClientAuthError, .deviceAlreadyEnrolled)
        }
        XCTAssertEqual(store.load(), stored, "nothing abandoned")
        XCTAssertEqual(manager.credentialState, ClientAuthManager.CredentialState.keyUnusable)
    }

    func testSignOutClearsLocallyWhenTheKeyCannotSign() async throws {
        let (stored, _) = repairableCredentials(recoveryKey: "")
        let store = InMemoryClientAuthStore(stored)
        let manager = managerFor(stored, store: store, loader: signingFaultLoader(for: stored.installationKey, domain: TKErrorDomain, code: -10))
        StubURLProtocol.lastRequest = nil
        StubURLProtocol.handler = { _ in Self.failure(500, "unexpected") }
        defer { StubURLProtocol.handler = nil }
        try await manager.signOut()
        XCTAssertNil(store.load(), "the credential is gone")
        XCTAssertEqual(manager.credentialState, ClientAuthManager.CredentialState.notEnrolled)
        XCTAssertNil(StubURLProtocol.lastRequest, "the revoke could not be proved; nothing was sent")
    }

    @MainActor
    func testCoordinatorRepairsAnUnloadableKeyBeforeAnythingElse() async throws {
        let (stored, _) = repairableCredentials()
        let (coordinator, host, manager) = coordinatorFixture(storedCredentials: stored, keyLoader: unloadableLoader(for: stored.installationKey)) { path, _ in
            path == "/api/auth/account/restore" ? Self.tokens("acct_same") : Self.failure(500, "unexpected")
        }
        defer { StubURLProtocol.handler = nil }
        XCTAssertTrue(manager.needsKeyRepair)
        let outcome = await coordinator.ensure(trigger: "usage")
        XCTAssertTrue(outcome)
        XCTAssertEqual(Paths.hits.filter { $0 == "/api/auth/account/restore" }.count, 1)
        XCTAssertFalse(Paths.hits.contains("/api/auth/account/create"))
        XCTAssertFalse(Paths.hits.contains("/api/auth/migrate"))
        XCTAssertFalse(manager.needsKeyRepair)
        XCTAssertEqual(host.errors.last ?? "unset", nil)
        XCTAssertTrue(host.enrolling.isEmpty, "a repair is not an enrollment")
    }

    // MARK: - Review 2026-10-26: load classification, reauthentication, sign-out

    func testLoadFailuresAreClassifiedAsConservativelyAsSigning() {
        let locked = InstallationKeyFailure.classify(loadError: NSError(domain: NSOSStatusErrorDomain, code: -25308))
        XCTAssertEqual(locked, .temporary(reason: "load:\(NSOSStatusErrorDomain):-25308"))
        let unknown = InstallationKeyFailure.classify(loadError: NSError(domain: "CryptoKit.CryptoKitError", code: 3))
        if case .temporary = unknown {} else { XCTFail("an unknown load error must not replace a credential: \(unknown)") }
        if case .unusable = InstallationKeyFailure.classify(loadError: InstallationKey.LoadError.corruptData) {} else { XCTFail("bytes that cannot be a key are unusable") }
        if case .unusable = InstallationKeyFailure.classify(loadError: InstallationKey.LoadError.unknownKind("x")) {} else { XCTFail() }
        XCTAssertTrue(InstallationKeyFailure.unusableLoadCodes.isEmpty, "no Secure Enclave load code is allow-listed until device QA records one")
    }

    func testAnUnknownLoadErrorWithARecoveryKeyIsNotRepairedAutomatically() async throws {
        let (stored, _) = repairableCredentials()
        let store = InMemoryClientAuthStore(stored)
        let manager = managerFor(stored, store: store, loader: { s in s == stored.installationKey ? .failure(NSError(domain: NSOSStatusErrorDomain, code: -25308)) : InstallationKey.load(stored: s) })
        restoreStub()
        defer { StubURLProtocol.handler = nil }
        XCTAssertFalse(manager.needsKeyRepair)
        var request = postRequest()
        do {
            try await manager.authorize(&request)
            XCTFail("expected keyUnavailable")
        } catch {
            XCTAssertEqual(error as? ClientAuthError, .keyUnavailable("load:\(NSOSStatusErrorDomain):-25308"))
        }
        XCTAssertEqual(Restore.hits, 0, "nothing restored for a load error that is not on the list")
        XCTAssertEqual(store.load(), stored)
        XCTAssertTrue(manager.keyNeedsReauthentication, "but Sign in again takes the fresh-key route")
    }

    func testSignInAgainAfterATemporaryFailureUsesAFreshKeyAndKeepsTheOldCredentialUntilSuccess() async throws {
        let (stored, _) = repairableCredentials()
        let store = InMemoryClientAuthStore(stored)
        let manager = managerFor(stored, store: store, loader: signingFaultLoader(for: stored.installationKey, domain: NSOSStatusErrorDomain, code: -25308))
        restoreStub()
        defer { StubURLProtocol.handler = nil }
        var request = postRequest()
        _ = try? await manager.authorize(&request)
        XCTAssertTrue(manager.keyNeedsReauthentication)
        XCTAssertTrue(manager.isEnrolled, "a temporary failure does not unenrol")

        // A lost response leaves everything as it was.
        Restore.answer = Self.failure(503, "client_auth_unavailable")
        do {
            try await manager.reauthenticate(loginLinkID: "lnk_approved", label: "Mac")
            XCTFail("expected unavailable")
        } catch {
            XCTAssertEqual(error as? ClientAuthError, .unavailable)
        }
        XCTAssertEqual(store.load(), stored, "the old credential is kept until the server accepts a new key")
        XCTAssertTrue(manager.keyNeedsReauthentication)

        // Approval by email: the restore route, a fresh key, the recovery key preserved.
        Restore.answer = Self.tokens("acct_same")
        try await manager.reauthenticate(loginLinkID: "lnk_approved", label: "Mac")
        let after = try XCTUnwrap(store.load())
        XCTAssertNotEqual(after.installationKey, stored.installationKey)
        XCTAssertEqual(after.recoveryKey, stored.recoveryKey, "an email re-authentication keeps the recovery key the credential already had")
        XCTAssertEqual(after.accountID, "acct_same")
        XCTAssertFalse(manager.keyNeedsReauthentication)
        XCTAssertEqual(Restore.hits, 2)
        var signed = postRequest()
        try await manager.authorize(&signed)
        XCTAssertNotNil(signed.value(forHTTPHeaderField: "X-Request-Proof"))

        // The typed recovery key route, same rules; a key for another account is refused and changes nothing.
        let (second, _) = repairableCredentials()
        let secondStore = InMemoryClientAuthStore(second)
        let again = managerFor(second, store: secondStore, loader: signingFaultLoader(for: second.installationKey, domain: NSOSStatusErrorDomain, code: -25308))
        var r = postRequest()
        _ = try? await again.authorize(&r)
        StubURLProtocol.handler = { request in
            switch request.url?.path ?? "" {
            case "/api/auth/challenge": return (200, Data(#"{"challenge_id":"c1","nonce":"n1","expires_in":120}"#.utf8))
            default: return Self.failure(409, "device_already_enrolled")
            }
        }
        do {
            try await again.reauthenticate(recoveryKeyInput: ClientAuthCrypto.formatRecoveryKey(ClientAuthCrypto.generateRecoveryKey()), label: "Mac")
            XCTFail("expected deviceAlreadyEnrolled")
        } catch {
            XCTAssertEqual(error as? ClientAuthError, .deviceAlreadyEnrolled)
        }
        XCTAssertEqual(secondStore.load(), second, "a key for another account abandons nothing")
        restoreStub()
        let typed = ClientAuthCrypto.generateRecoveryKey()
        try await again.reauthenticate(recoveryKeyInput: ClientAuthCrypto.formatRecoveryKey(typed), label: "Mac")
        XCTAssertEqual(secondStore.load()?.recoveryKey, typed, "the typed key becomes the stored one")
        XCTAssertNotEqual(secondStore.load()?.installationKey, second.installationKey)
    }

    func testSignOutClearsLocallyAfterTheUnusableStateIsEstablished() async throws {
        // The reviewer's sequence: email-joined, signing fails, then sign out.
        let (stored, _) = repairableCredentials(recoveryKey: "")
        let store = InMemoryClientAuthStore(stored)
        let manager = managerFor(stored, store: store, loader: signingFaultLoader(for: stored.installationKey, domain: TKErrorDomain, code: -10))
        StubURLProtocol.handler = { _ in Self.failure(500, "unexpected") }
        defer { StubURLProtocol.handler = nil }
        var request = postRequest()
        _ = try? await manager.authorize(&request)
        XCTAssertEqual(manager.credentialState, ClientAuthManager.CredentialState.keyUnusable)
        StubURLProtocol.lastRequest = nil
        try await manager.signOut()
        XCTAssertNil(store.load(), "the credential is gone")
        XCTAssertNil(StubURLProtocol.lastRequest, "nothing could be proved, nothing was sent")
        XCTAssertEqual(manager.credentialState, ClientAuthManager.CredentialState.notEnrolled)

        // And after a temporary failure, likewise.
        let (second, _) = repairableCredentials()
        let secondStore = InMemoryClientAuthStore(second)
        let temp = managerFor(second, store: secondStore, loader: signingFaultLoader(for: second.installationKey, domain: NSOSStatusErrorDomain, code: -25308))
        var r = postRequest()
        _ = try? await temp.authorize(&r)
        try await temp.signOut()
        XCTAssertNil(secondStore.load())
    }

    // MARK: - Re-review 2026-10-26: refresh keeps the flag, real callers, email switch semantics

    func testAnUnsignedRefreshDoesNotClearTheKeyFailure() async throws {
        let (stored, _) = repairableCredentials()
        let store = InMemoryClientAuthStore(stored)
        let manager = managerFor(stored, store: store, loader: signingFaultLoader(for: stored.installationKey, domain: NSOSStatusErrorDomain, code: -25308))
        StubURLProtocol.handler = { [self] request in
            let body = requestBody(request)
            if request.url?.path == "/api/auth/token", body["grant_type"] as? String == "refresh" { return Self.tokens("acct_same") }
            return Self.failure(500, "unexpected")
        }
        defer { StubURLProtocol.handler = nil }
        var request = postRequest()
        _ = try? await manager.authorize(&request)
        XCTAssertTrue(manager.keyNeedsReauthentication)
        _ = try await manager.forceRefresh()
        XCTAssertEqual(store.load()?.accessToken, "tok", "the unsigned refresh went through")
        XCTAssertTrue(manager.keyNeedsReauthentication, "fresh tokens do not fix a key that cannot sign")
        XCTAssertEqual(store.load()?.installationKey, stored.installationKey)
    }

    func testEmailReauthenticationKeepsTheRecoveryKeyOnlyForTheSameAccount() async throws {
        let (stored, _) = repairableCredentials()
        let store = InMemoryClientAuthStore(stored)
        let manager = managerFor(stored, store: store, loader: signingFaultLoader(for: stored.installationKey, domain: NSOSStatusErrorDomain, code: -25308))
        var r = postRequest()
        _ = try? await manager.authorize(&r)
        restoreStub(account: "acct_other")
        defer { StubURLProtocol.handler = nil }
        try await manager.reauthenticate(loginLinkID: "lnk_other", label: "Mac")
        let moved = try XCTUnwrap(store.load())
        XCTAssertEqual(moved.accountID, "acct_other")
        XCTAssertEqual(moved.recoveryKey, "", "the old account's key must not sit beside the new account")
        XCTAssertEqual(moved.enrollmentPath, "restore")
        XCTAssertFalse(manager.keyNeedsReauthentication)

        let (again, _) = repairableCredentials()
        let againStore = InMemoryClientAuthStore(again)
        let same = managerFor(again, store: againStore, loader: signingFaultLoader(for: again.installationKey, domain: NSOSStatusErrorDomain, code: -25308))
        var r2 = postRequest()
        _ = try? await same.authorize(&r2)
        restoreStub(account: "acct_same")
        try await same.reauthenticate(loginLinkID: "lnk_same", label: "Mac")
        XCTAssertEqual(againStore.load()?.recoveryKey, again.recoveryKey, "same account: the key the credential already had is kept")
    }

    @MainActor
    func testTheEnrolledRecoveryKeyActionReauthenticatesWithAFreshKeyAfterAKeyFailure() async throws {
        // The real caller: Settings opens the recovery-key sheet in move mode for an enrolled
        // device, which calls attachManagedDevice (reviewer's finding 2).
        let (stored, _) = repairableCredentials()
        let store = InMemoryClientAuthStore(stored)
        let manager = managerFor(stored, store: store, loader: signingFaultLoader(for: stored.installationKey, domain: NSOSStatusErrorDomain, code: -25308))
        let app = AppState()
        app.clientAuthManager = manager
        var r = postRequest()
        _ = try? await manager.authorize(&r)
        restoreStub()
        defer { StubURLProtocol.handler = nil }
        Paths.hits = []
        let typed = ClientAuthCrypto.formatRecoveryKey(ClientAuthCrypto.generateRecoveryKey())
        let ok = await app.attachManagedDevice(recoveryKey: typed)
        XCTAssertTrue(ok, app.managedEnrollmentError ?? "")
        XCTAssertEqual(Restore.hits, 1, "restore with a fresh key, not attach with the failed one")
        XCTAssertNotEqual(store.load()?.installationKey, stored.installationKey)
        XCTAssertFalse(manager.keyNeedsReauthentication)

        // Another account's key: refused, nothing abandoned, the explicit copy shown.
        let (second, _) = repairableCredentials()
        let secondStore = InMemoryClientAuthStore(second)
        let failing = managerFor(second, store: secondStore, loader: signingFaultLoader(for: second.installationKey, domain: NSOSStatusErrorDomain, code: -25308))
        app.clientAuthManager = failing
        var r2 = postRequest()
        _ = try? await failing.authorize(&r2)
        StubURLProtocol.handler = { request in
            if request.url?.path == "/api/auth/challenge" { return (200, Data(#"{"challenge_id":"c1","nonce":"n1","expires_in":120}"#.utf8)) }
            return Self.failure(409, "device_already_enrolled")
        }
        let refused = await app.attachManagedDevice(recoveryKey: typed)
        XCTAssertFalse(refused)
        XCTAssertEqual(app.managedEnrollmentError, AppState.recoveryBelongsElsewhereMessage)
        XCTAssertEqual(secondStore.load(), second)
    }

    @MainActor
    func testTheRestoreAndEmailActionsReauthenticateThroughAppStateAfterAKeyFailure() async throws {
        let (stored, _) = repairableCredentials()
        let store = InMemoryClientAuthStore(stored)
        let manager = managerFor(stored, store: store, loader: signingFaultLoader(for: stored.installationKey, domain: NSOSStatusErrorDomain, code: -25308))
        let app = AppState()
        app.clientAuthManager = manager
        var r = postRequest()
        _ = try? await manager.authorize(&r)
        restoreStub()
        defer { StubURLProtocol.handler = nil }
        let typed = ClientAuthCrypto.generateRecoveryKey()
        let restored = await app.restoreManagedAccount(recoveryKey: ClientAuthCrypto.formatRecoveryKey(typed))
        XCTAssertTrue(restored, app.managedEnrollmentError ?? "")
        XCTAssertEqual(Restore.hits, 1)
        XCTAssertFalse(Paths.hits.contains("/api/auth/revoke"), "no sign-out, the credential was kept until the server accepted the new key")
        XCTAssertEqual(store.load()?.recoveryKey, typed)

        let (second, _) = repairableCredentials()
        let secondStore = InMemoryClientAuthStore(second)
        let viaEmail = managerFor(second, store: secondStore, loader: signingFaultLoader(for: second.installationKey, domain: NSOSStatusErrorDomain, code: -25308))
        app.clientAuthManager = viaEmail
        var r2 = postRequest()
        _ = try? await viaEmail.authorize(&r2)
        restoreStub()
        let joined = await app.joinAccount(approvedLinkID: "lnk_approved")
        XCTAssertTrue(joined, app.managedEnrollmentError ?? "")
        XCTAssertEqual(Restore.hits, 1, "the approved link went through restore with a fresh key, not attach")
        XCTAssertNotEqual(secondStore.load()?.installationKey, second.installationKey)
    }

    @MainActor
    func testARecoveryKeyRestoreOntoAnotherAccountResetsCloudBookkeepingAndASameAccountRepairKeepsIt() async throws {
        // Account A's pending deletion must never run against account B (reviewer's finding).
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let sharedID = UUID()
        let meeting = Meeting(title: "shared", startTime: Date())
        meeting.cloudRevision = 3
        meeting.syncFingerprint = "fp"
        context.insert(meeting)
        context.insert(MeetingTombstone(id: sharedID, cloudRevision: 2))
        try context.save()

        let (stored, _) = repairableCredentials()
        let store = InMemoryClientAuthStore(stored)
        let revoked = managerFor(stored, store: store, loader: { InstallationKey.load(stored: $0) })
        let app = AppState()
        app.modelContext = context
        // Production attaches the host in configureCloudSyncIfNeeded, which the test host skips so
        // it never syncs the real store. Attach it here against the in-memory store, no start().
        app.cloudSync.host = app
        app.clientAuthManager = revoked
        app.refreshClientAuthStatus()
        XCTAssertEqual(app.cloudAccountID, "acct_same")

        // Revoked on the server; the typed key belongs to account B.
        StubURLProtocol.handler = { request in
            switch request.url?.path ?? "" {
            case "/api/auth/challenge": return (200, Data(#"{"challenge_id":"c1","nonce":"n1","expires_in":120}"#.utf8))
            case "/api/auth/revoke": return (401, Data(#"{"error":"installation_revoked","message":"x"}"#.utf8))
            case "/api/auth/account/restore": return Self.tokens("acct_b")
            default: return Self.failure(500, "unexpected")
            }
        }
        defer { StubURLProtocol.handler = nil }
        let moved = await app.restoreManagedAccount(recoveryKey: ClientAuthCrypto.formatRecoveryKey(ClientAuthCrypto.generateRecoveryKey()))
        XCTAssertTrue(moved, app.managedEnrollmentError ?? "")
        XCTAssertEqual(app.cloudAccountID, "acct_b")
        XCTAssertEqual(try context.fetch(FetchDescriptor<MeetingTombstone>()).count, 0, "A's pending deletion is gone before any sync pass could send it to B")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Meeting>()).first?.cloudRevision, 0, "A's revisions do not describe B's copies")
        XCTAssertNil(try context.fetch(FetchDescriptor<Meeting>()).first?.syncFingerprint)

        // Same-account repair after a key failure: the bookkeeping is kept.
        context.insert(MeetingTombstone(id: UUID(), cloudRevision: 1))
        let kept = try XCTUnwrap(try context.fetch(FetchDescriptor<Meeting>()).first)
        kept.cloudRevision = 5
        try context.save()
        let (second, _) = repairableCredentials()
        let secondStore = InMemoryClientAuthStore(second)
        let failing = managerFor(second, store: secondStore, loader: signingFaultLoader(for: second.installationKey, domain: NSOSStatusErrorDomain, code: -25308))
        app.clientAuthManager = failing
        app.refreshClientAuthStatus()
        var r = postRequest()
        _ = try? await failing.authorize(&r)
        restoreStub(account: "acct_same")
        let repaired = await app.restoreManagedAccount(recoveryKey: ClientAuthCrypto.formatRecoveryKey(ClientAuthCrypto.generateRecoveryKey()))
        XCTAssertTrue(repaired, app.managedEnrollmentError ?? "")
        XCTAssertEqual(try context.fetch(FetchDescriptor<MeetingTombstone>()).count, 1, "same account: pending deletions stay")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Meeting>()).first?.cloudRevision, 5, "same account: revisions stay")
    }

    // MARK: - A2e error copy

    func testRestoreFailuresAreMappedByCodeNotByOneSentence() {
        typealias E = MinitiAPIService.ServiceError
        let invalid = AppState.restoreFailure(for: E.apiError(code: "invalid_key", message: "Invalid or expired license key", status: 400))
        XCTAssertEqual(invalid.code, "invalid_key")
        XCTAssertTrue(invalid.message.contains("not valid for miniti"))
        let refused = AppState.restoreFailure(for: E.apiError(code: "activation_refused", message: "x", status: 409))
        XCTAssertEqual(refused.code, "activation_refused")
        XCTAssertTrue(refused.message.contains("will not activate"))
        let config = AppState.restoreFailure(for: E.apiError(code: "provider_config", message: "There is a configuration problem on our side. Try again later.", status: 503))
        XCTAssertEqual(config.code, "provider_config")
        XCTAssertEqual(config.message, "There is a configuration problem on our side. Try again later.")
        XCTAssertFalse(config.message.lowercased().contains("key"), "a fault on our side is never blamed on the key")
        let down = AppState.restoreFailure(for: E.apiError(code: "provider_unavailable", message: "x", status: 503))
        XCTAssertTrue(down.message.contains("could not reach Polar"))
        let limited = AppState.restoreFailure(for: E.rateLimited)
        XCTAssertEqual(limited.code, "rate_limited")
        XCTAssertTrue(limited.message.contains("Wait a minute"))
        let offline = AppState.restoreFailure(for: E.networkError(URLError(.notConnectedToInternet)))
        XCTAssertEqual(offline.code, "network")
        let none = AppState.restoreFailure(for: E.apiError(code: "no_active_subscription", message: "x", status: 400))
        XCTAssertTrue(none.message.contains("no active subscription"))
    }

    func testEmailSignInFailuresAreMappedByStage() {
        let send = AppState.emailStartFailure(for: ClientAuthError.server(code: "email_send_failed", status: 502))
        XCTAssertEqual(send.code, "email_send_failed")
        XCTAssertTrue(send.message.contains("could not be sent"))
        XCTAssertEqual(AppState.emailStartFailure(for: ClientAuthError.rateLimited).code, "rate_limited")
        XCTAssertTrue(AppState.emailStartFailure(for: ClientAuthError.network("offline")).message.contains("connection"))

        let expired = AppState.joinFailure(for: ClientAuthError.server(code: "login_link_expired", status: 410), keyWasUnusable: false)
        XCTAssertTrue(expired.message.contains("expired"))
        let elsewhere = AppState.joinFailure(for: ClientAuthError.deviceAlreadyEnrolled, keyWasUnusable: true)
        XCTAssertEqual(elsewhere.message, AppState.recoveryBelongsElsewhereMessage)
        let stillEnrolled = AppState.joinFailure(for: ClientAuthError.deviceAlreadyEnrolled, keyWasUnusable: false)
        XCTAssertNotEqual(stillEnrolled.message, AppState.recoveryBelongsElsewhereMessage, "the other-account copy is for the unusable-key state only")
        let cap = AppState.joinFailure(for: ClientAuthError.deviceCapReached(5), keyWasUnusable: false)
        XCTAssertEqual(cap.code, "device_cap_reached")
        XCTAssertTrue(cap.message.contains("5 devices"))
    }

    // MARK: - A2b credential format fixtures

    /// Captured shapes of the stored credential JSON, one per shipped format. Never edit a
    /// fixture; add one for each format change together with a test that the older ones still
    /// decode to the expected values (docs/archive/enrollment-identity-plan.md, A2b). Key material is fake.
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
        // Round trip: what 3.4.0 writes for this blob decodes to the same values.
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
        storedCredentials: ClientAuthCredentials? = nil,
        rotator: (@Sendable () -> String)? = nil,
        keyLoader: @escaping @Sendable (InstallationKey.Stored) -> Result<InstallationKey, Error> = { InstallationKey.load(stored: $0) },
        answers: @escaping @Sendable (String, [String: Any]) -> (Int, Data)
    ) -> (ManagedEnrollmentCoordinator, CoordinatorHost, ClientAuthManager) {
        let store = InMemoryClientAuthStore(storedCredentials ?? (enrolled ? credentials() : nil))
        // The provider follows the rotator, as DeviceIdentifier does for the real manager.
        nonisolated(unsafe) var currentID = "550e8400-e29b-41d4-a716-446655440000"
        let manager = ClientAuthManager(
            store: store, baseURL: "https://api.test/api", session: stubbedSession(),
            deviceIDProvider: { currentID },
            deviceIDRotator: rotator.map { rotate in { currentID = rotate(); return currentID } },
            keyLoader: keyLoader,
            defaults: UserDefaults(suiteName: "test_auth_\(UUID().uuidString)")!
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

    init(diagnostic: ClientAuthStoreDiagnostic?, saveSucceeds: Bool = true, initial: ClientAuthCredentials? = nil) {
        self.diagnostic = diagnostic
        self.saveAllowed = saveSucceeds
        self.value = initial
    }

    var lastLoadDiagnostic: ClientAuthStoreDiagnostic? { diagnostic }
    func load() -> ClientAuthCredentials? { lock.lock(); defer { lock.unlock() }; return diagnostic == nil ? value : nil }
    func save(_ credentials: ClientAuthCredentials) -> Bool {
        guard saveSucceeds else { return false }
        lock.lock(); defer { lock.unlock() }; value = credentials; return true
    }
    func clear() { lock.lock(); defer { lock.unlock() }; value = nil }
}

// MARK: - B6a: account email, the Home card and the account section model

final class AccessCardPolicyTests: XCTestCase {
    private let empty = AccountEmailState.loaded(AccountEmail())

    func testShowsOnlyForAnEnrolledAccountWithAMeetingAndNoProtection() {
        XCTAssertTrue(AppState.accessCardVisible(enrolled: true, emailState: empty, hasSavedMeeting: true, recoveryKeyAcknowledged: false, dismissed: false))
        XCTAssertFalse(AppState.accessCardVisible(enrolled: false, emailState: empty, hasSavedMeeting: true, recoveryKeyAcknowledged: false, dismissed: false), "no account, nothing to protect")
        XCTAssertFalse(AppState.accessCardVisible(enrolled: true, emailState: empty, hasSavedMeeting: false, recoveryKeyAcknowledged: false, dismissed: false), "the first launch stays quiet")
        XCTAssertFalse(AppState.accessCardVisible(enrolled: true, emailState: empty, hasSavedMeeting: true, recoveryKeyAcknowledged: true, dismissed: false), "a saved recovery key is protection")
        XCTAssertFalse(AppState.accessCardVisible(enrolled: true, emailState: empty, hasSavedMeeting: true, recoveryKeyAcknowledged: false, dismissed: true), "not now is respected")
    }

    func testLoadingAndUnavailableSuppressTheCardAndAVerifiedEmailEndsIt() {
        XCTAssertFalse(AppState.accessCardVisible(enrolled: true, emailState: .loading, hasSavedMeeting: true, recoveryKeyAcknowledged: false, dismissed: false))
        XCTAssertFalse(AppState.accessCardVisible(enrolled: true, emailState: .unavailable("No connection."), hasSavedMeeting: true, recoveryKeyAcknowledged: false, dismissed: false), "a failed fetch never nags")
        XCTAssertFalse(AppState.accessCardVisible(enrolled: true, emailState: .loaded(AccountEmail(verified: "a@example.com")), hasSavedMeeting: true, recoveryKeyAcknowledged: false, dismissed: false))
        XCTAssertFalse(AppState.accessCardVisible(enrolled: true, emailState: .loaded(AccountEmail(verified: "a@example.com", pending: "b@example.com")), hasSavedMeeting: true, recoveryKeyAcknowledged: false, dismissed: false), "a pending replacement does not remove protection")
        XCTAssertTrue(AppState.accessCardVisible(enrolled: true, emailState: .loaded(AccountEmail(pending: "b@example.com")), hasSavedMeeting: true, recoveryKeyAcknowledged: false, dismissed: false), "first verification pending shows the quiet form")
    }
}

final class AccountSectionModelTests: XCTestCase {
    private typealias M = AccountSectionModel
    private func enrolled(acknowledged: Bool = true) -> ClientAuthStatus {
        ClientAuthStatus(isEnrolled: true, accountID: "acct_test", deviceCap: 5, enrolledAt: "2026-10-27T00:00:00Z", enrollmentPath: "create", recoveryKeyAcknowledged: acknowledged, isHardwareBacked: true)
    }
    private func make(_ configure: (inout M.Inputs) -> Void) -> M {
        var i = M.Inputs()
        i.status = enrolled()
        i.emailState = .loaded(AccountEmail())
        configure(&i)
        return M.make(i)
    }

    func testTheEightStatesShowTheirSentenceAndTheirOneAction() {
        let loading = make { $0.emailState = .loading }
        XCTAssertEqual(loading.emailLine, "Checking this account's email…")
        XCTAssertEqual(loading.emailActions, [])

        let unavailable = make { $0.emailState = .unavailable("No connection.") }
        XCTAssertEqual(unavailable.emailLine, "Could not check this account's email. No connection.")
        XCTAssertEqual(unavailable.emailActions, [.retryEmail], "never an add-email nudge from a failed request")

        let none = make { _ in }
        XCTAssertEqual(none.emailLine, "No email yet")
        XCTAssertEqual(none.emailActions, [.addEmail])
        XCTAssertNil(none.emailBadge)

        let pending = make { $0.emailState = .loaded(AccountEmail(pending: "new@example.com")) }
        XCTAssertEqual(pending.emailLine, "Check your email: link sent to new@example.com")
        XCTAssertEqual(pending.emailActions, [.resendEmail, .changeEmail])
        XCTAssertNil(pending.emailBadge, "pending is not verified")

        let verified = make { $0.emailState = .loaded(AccountEmail(verified: "me@example.com")) }
        XCTAssertEqual(verified.emailLine, "me@example.com", "the full address, not a mask")
        XCTAssertEqual(verified.emailBadge, "Verified")
        XCTAssertEqual(verified.emailActions, [.changeEmail, .removeEmail])

        let replacing = make { $0.emailState = .loaded(AccountEmail(verified: "me@example.com", pending: "new@example.com")) }
        XCTAssertEqual(replacing.emailLine, "me@example.com")
        XCTAssertEqual(replacing.emailBadge, "Verified", "still protected while the replacement waits")
        XCTAssertEqual(replacing.pendingLine, "Replacement pending: new@example.com")
        XCTAssertEqual(replacing.emailActions, [.resendEmail, .changeEmail, .removeEmail], "no Cancel: there is no backend operation for it")

        let emailJoined = make { $0.hasLocalRecoveryKey = false }
        XCTAssertEqual(emailJoined.recoveryKeyLine, "Not on this device")
        XCTAssertEqual(emailJoined.recoveryKeyActions, [.replaceKey])
        XCTAssertTrue(emailJoined.recoveryKeyNote?.contains("does not hold the recovery key") == true)

        let unusable = make { $0.keyState = .unusable }
        XCTAssertEqual(unusable.accountActions, [.signInAgain, .signOut])
        XCTAssertTrue(unusable.keyNote?.contains("no longer works here") == true)
        XCTAssertEqual(unusable.recoveryKeyActions, [.showKey], "showing the stored key needs no installation key and is the way back in")
        XCTAssertEqual(unusable.emailActions, [], "add, change and remove are signed requests")
        XCTAssertFalse(unusable.signedActionsDisabled)
    }

    func testATemporaryKeyFailureDisablesSignedActionsWithoutHidingOrBlaming() {
        let temporary = make { $0.keyState = .temporarilyUnavailable; $0.emailState = .loaded(AccountEmail(verified: "me@example.com")) }
        XCTAssertTrue(temporary.signedActionsDisabled)
        XCTAssertEqual(temporary.emailActions, [.changeEmail, .removeEmail], "visible, disabled")
        XCTAssertEqual(temporary.recoveryKeyActions, [.showKey, .replaceKey])
        XCTAssertEqual(temporary.accountActions, [.tryAgain, .signInAgain, .switchAccount, .signOut, .deleteAccount])
        XCTAssertFalse(temporary.keyNote?.lowercased().contains("no longer") == true, "a temporary failure never reads as permanent damage")
        XCTAssertEqual(M.temporarilyUnavailable, "Temporarily unavailable. Try again.")
        for action in [M.Action.addEmail, .changeEmail, .resendEmail, .removeEmail, .replaceKey, .switchAccount, .deleteAccount] {
            XCTAssertTrue(M.needsSignature(action), "\(action)")
        }
        for action in [M.Action.showKey, .signInAgain, .tryAgain, .signOut, .retryEmail] {
            XCTAssertFalse(M.needsSignature(action), "\(action)")
        }
    }

    func testPlanAndRestoreWordingPerPlatform() {
        let mac = make { $0.isMac = true; $0.isPro = true }
        XCTAssertEqual(mac.planLine, "Pro")
        XCTAssertEqual(mac.restoreTitle, "Restore Pro purchase with a license key")
        XCTAssertTrue(mac.restoreCaption.hasPrefix("This restores a purchase. It does not sign you into an account."))
        let phone = make { $0.isMac = false; $0.isPro = true }
        XCTAssertEqual(phone.planLine, "Pro", "Your account keeps the word; Plan and billing says where it comes from (L3)")
        XCTAssertEqual(phone.restoreTitle, "Restore App Store purchases")
        XCTAssertEqual(make { _ in }.planLine, "Free")
    }

    func testDeviceIDSearchOpensExpandedHelpDetails() {
        let item = SettingsSearchCatalog.items.first { $0.id == "account.deviceID" }
        XCTAssertEqual(item?.destination, .help)
        XCTAssertEqual(item?.section, "Support details")
    }

    func testNoSentenceCallsTheKeyTheAccountOrTheOnlyWayBack() {
        let banned = ["only way", "your account is", "this key is your", "reveal", "rotate", "create one", "settings, cloud", "—"]
        var inputs: [M.Inputs] = []
        for key in [M.KeyState.usable, .temporarilyUnavailable, .unusable] {
            for email in [AccountEmailState.loading, .unavailable("x"), .loaded(AccountEmail()), .loaded(AccountEmail(verified: "a@b.c")), .loaded(AccountEmail(verified: "a@b.c", pending: "d@e.f")), .loaded(AccountEmail(pending: "d@e.f"))] {
                for local in [true, false] {
                    var i = M.Inputs(); i.status = enrolled(); i.keyState = key; i.emailState = email; i.hasLocalRecoveryKey = local
                    inputs.append(i)
                }
            }
        }
        for i in inputs {
            let m = M.make(i)
            let texts = [m.emailLine, m.pendingLine ?? "", m.recoveryKeyLine, m.recoveryKeyNote ?? "", m.keyNote ?? "", m.planLine, m.restoreTitle, m.restoreCaption, m.deviceRemovalMessage, m.signOutMessage]
            for text in texts {
                let lower = text.lowercased()
                for phrase in banned { XCTAssertFalse(lower.contains(phrase), "\"\(phrase)\" in: \(text)") }
            }
            XCTAssertTrue(m.signOutMessage.contains("email or recovery key"), "sign-out names both ways back")
            XCTAssertTrue(m.deviceRemovalMessage.contains("email or recovery key"))
        }
    }
}

/// A tiny account-email server behind the stub: state per bearer, a request log, optional
/// failures. The reconciliation reads see exactly what the writes did.
final class FakeEmailServer: @unchecked Sendable {
    struct Account { var verified: String?; var pending: String? }
    private let lock = NSLock()
    private var accounts: [String: Account] = [:]
    private(set) var log: [String] = []
    var failGET: (Int, String)?
    var failPOST: (Int, String)?
    var failDELETE: (Int, String)?

    func set(_ bearer: String, verified: String?, pending: String?) {
        lock.lock(); accounts[bearer] = Account(verified: verified, pending: pending); lock.unlock()
    }
    func account(_ bearer: String) -> Account {
        lock.lock(); defer { lock.unlock() }
        return accounts[bearer] ?? Account()
    }
    func install() {
        StubURLProtocol.handler = { [self] request in
            guard request.url?.path.hasSuffix("/account/email") == true else { return (200, Data("{}".utf8)) }
            let bearer = (request.value(forHTTPHeaderField: "Authorization") ?? "").replacingOccurrences(of: "Bearer ", with: "")
            lock.lock(); defer { lock.unlock() }
            var state = accounts[bearer] ?? Account()
            switch request.httpMethod {
            case "POST":
                log.append("POST \(bearer)")
                if let (status, code) = failPOST { return (status, Data("{\"error\":\"\(code)\"}".utf8)) }
                let body = (try? JSONSerialization.jsonObject(with: TestSupport.bodyData(of: request)) as? [String: Any]) ?? [:]
                state.pending = body["email"] as? String
                accounts[bearer] = state
                return (202, Data("{\"email\":\(state.verified.map { "\"\($0)\"" } ?? "null"),\"pending\":\"\(state.pending ?? "")\"}".utf8))
            case "DELETE":
                log.append("DELETE \(bearer)")
                if let (status, code) = failDELETE { return (status, Data("{\"error\":\"\(code)\"}".utf8)) }
                accounts[bearer] = Account()
                return (200, Data("{\"removed\":true,\"sessions_revoked\":0,\"grants_revoked\":0}".utf8))
            default:
                log.append("GET \(bearer)")
                if let (status, code) = failGET { return (status, Data("{\"error\":\"\(code)\"}".utf8)) }
                let email = state.verified.map { "\"\($0)\"" } ?? "null"
                let pending = state.pending.map { "\"\($0)\"" } ?? "null"
                return (200, Data("{\"email\":\(email),\"pending\":\(pending)}".utf8))
            }
        }
    }
}

@MainActor
final class AccountEmailStateTests: XCTestCase {
    private var session: URLSession!
    private var server: FakeEmailServer!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        session = TestSupport.stubbedSession()
        server = FakeEmailServer()
        server.install()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    /// Credentials whose bearer is the account id, so the fake server keeps state per account.
    private func credentials(account: String, acknowledged: Bool = true) -> ClientAuthCredentials {
        var c = TestSupport.enrolledCredentials(accessToken: account, acknowledged: acknowledged)
        c.accountID = account
        return c
    }

    private func manager(_ account: String, acknowledged: Bool = true) -> ClientAuthManager {
        TestSupport.enrolledAuthManager(session: session, credentials: credentials(account: account, acknowledged: acknowledged))
    }

    /// An enrolled `AppState` whose auth and API go through the stub. The status refresh
    /// starts the account-change read in its own task; it is settled here so each scenario
    /// starts from a quiet state with one read on the log.
    private func makeApp(account: String = "acct_a", acknowledged: Bool = true) async -> AppState {
        let manager = manager(account, acknowledged: acknowledged)
        let app = AppState()
        app.appModeRaw = AppMode.managed.rawValue
        app.clientAuthManager = manager
        app.minitiAPIService = MinitiAPIService(session: session, auth: manager)
        app.refreshClientAuthStatus()
        // Wait for that read to land rather than pausing a fixed 120 ms: on 2026-10-27 the CI
        // runner was still mid-read when the refresh-queue scenario started, so its slow read
        // was merely queued, the state stayed loading and the log showed one GET instead of two.
        for _ in 0..<600 {
            if !app.accountEmailInFlight, app.accountEmailPending == nil, app.accountEmailState != .loading { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return app
    }

    /// Switch the app to another account the way a real switch does (status refresh bumps the
    /// generation and starts the account-change read).
    private func switchAccount(_ app: AppState, to account: String) {
        let m = manager(account)
        app.clientAuthManager = m
        app.minitiAPIService = MinitiAPIService(session: session, auth: m)
        app.refreshClientAuthStatus()
    }

    private func gets() -> Int { server.log.filter { $0.hasPrefix("GET") }.count }

    private func settle() async throws { try await Task.sleep(nanoseconds: 120_000_000) }

    // MARK: Shapes and loads

    func testTheFourLoadedShapesAndTheProtectedRule() async {
        let app = await makeApp()
        let cloudBefore = app.cloudSyncEnabled
        server.set("acct_a", verified: "me@example.com", pending: "new@example.com")
        await app.refreshAccountEmail(reason: "test", force: true)
        XCTAssertEqual(app.accountEmailState, .loaded(AccountEmail(verified: "me@example.com", pending: "new@example.com")))
        XCTAssertTrue(app.accountEmailState.email?.isProtected == true, "verified with a replacement pending is still protected")
        server.set("acct_a", verified: nil, pending: "new@example.com")
        await app.refreshAccountEmail(reason: "test", force: true)
        XCTAssertEqual(app.accountEmailState.email?.isProtected, false)
        server.set("acct_a", verified: nil, pending: nil)
        await app.refreshAccountEmail(reason: "test", force: true)
        XCTAssertEqual(app.accountEmailState, .loaded(AccountEmail()))
        XCTAssertEqual(app.clientAuthStatus.accountID, "acct_a", "loading the email never touches the account")
        XCTAssertEqual(app.cloudSyncEnabled, cloudBefore, "and never changes the cloud switch")
    }

    func testAFailedFetchIsUnavailableAndKeepsNoStaleAddress() async {
        let app = await makeApp()
        server.set("acct_a", verified: "me@example.com", pending: nil)
        await app.refreshAccountEmail(reason: "test", force: true)
        server.failGET = (503, "cloud_unavailable")
        await app.refreshAccountEmail(reason: "test", force: true)
        XCTAssertEqual(app.accountEmailState, .unavailable("The account service is unavailable right now."))
        XCTAssertNil(app.accountEmailState.email, "unavailable is not \"no email\" and not the old address")
        XCTAssertNil(app.accountEmailLastLoaded, "the next activation retries instead of trusting a stale load")
    }

    // MARK: Mutations (F1)

    func testAddShowsPendingBesideTheVerifiedAddressAndReconcilesWithTheServer() async {
        let app = await makeApp()
        let cloudBefore = app.cloudSyncEnabled
        server.set("acct_a", verified: "me@example.com", pending: nil)
        await app.refreshAccountEmail(reason: "test", force: true)
        let outcome = await app.addAccountEmail(" New@Example.com ")
        XCTAssertEqual(outcome, .sent("new@example.com"))
        XCTAssertEqual(app.accountEmailState, .loaded(AccountEmail(verified: "me@example.com", pending: "new@example.com")), "the verified address stays until the link is opened")
        XCTAssertEqual(server.log.last, "GET acct_a", "a completed mutation is read back from the server")
        // The browser handed back after the link was opened.
        server.set("acct_a", verified: "new@example.com", pending: nil)
        await app.refreshAccountEmail(reason: "browser callback", force: true)
        XCTAssertEqual(app.accountEmailState, .loaded(AccountEmail(verified: "new@example.com", pending: nil)))
        XCTAssertEqual(app.clientAuthStatus.accountID, "acct_a")
        XCTAssertEqual(app.cloudSyncEnabled, cloudBefore, "confirming an email never changes the cloud switch")
    }

    func testAnAddressOnAnotherAccountAndAProviderFailureLeaveTheStateAlone() async {
        let app = await makeApp()
        await app.refreshAccountEmail(reason: "test", force: true)
        server.failPOST = (409, "email_in_use")
        let inUse = await app.addAccountEmail("taken@example.com")
        XCTAssertEqual(inUse, .inUse)
        XCTAssertEqual(app.accountEmailState, .loaded(AccountEmail()))
        server.failPOST = (502, "email_send_failed")
        let failed = await app.addAccountEmail("x@example.com")
        XCTAssertEqual(failed, .failed("The confirmation email could not be sent. Try again in a minute."))
        XCTAssertEqual(app.accountEmailState, .loaded(AccountEmail()), "a provider error is retryable and changes nothing")
        let nonsense = await app.addAccountEmail("nonsense")
        XCTAssertEqual(nonsense, .failed("Enter an email address."))
    }

    func testRemoveReturnsToNoEmail() async {
        let app = await makeApp()
        server.set("acct_a", verified: "me@example.com", pending: nil)
        await app.refreshAccountEmail(reason: "test", force: true)
        let outcome = await app.removeAccountEmail()
        XCTAssertEqual(outcome, .removed)
        XCTAssertEqual(app.accountEmailState, .loaded(AccountEmail()))
        XCTAssertNil(server.account("acct_a").verified)
    }

    func testASlowWriteFromTheOldAccountIsStaleAfterASwitchAndTheServerStateIsKept() async throws {
        let app = await makeApp(account: "acct_a")
        await app.refreshAccountEmail(reason: "test", force: true)
        StubURLProtocol.delay = 0.4
        let slowAdd = Task { await app.addAccountEmail("a@example.com") }
        try await Task.sleep(nanoseconds: 50_000_000)
        StubURLProtocol.delay = 0
        switchAccount(app, to: "acct_b")
        let outcome = await slowAdd.value
        XCTAssertEqual(outcome, .staleAccount, "the write finished after the switch: nothing shown")
        await app.refreshAccountEmail(reason: "settle", force: true)
        XCTAssertEqual(app.accountEmailState, .loaded(AccountEmail()), "B's state is B's")
        XCTAssertEqual(server.account("acct_a").pending, "a@example.com", "the server did apply A's write")
        XCTAssertNil(server.account("acct_b").pending)

        // Back to A: the reconciled server state shows, through the account-change read.
        switchAccount(app, to: "acct_a")
        await app.refreshAccountEmail(reason: "settle", force: true)
        XCTAssertEqual(app.accountEmailState, .loaded(AccountEmail(pending: "a@example.com")))
    }

    func testASlowRemoveAcrossAToBToAIsStaleAndBIsUntouched() async throws {
        let app = await makeApp(account: "acct_a")
        server.set("acct_a", verified: "a@example.com", pending: nil)
        server.set("acct_b", verified: "b@example.com", pending: nil)
        await app.refreshAccountEmail(reason: "test", force: true)
        StubURLProtocol.delay = 0.4
        let slowRemove = Task { await app.removeAccountEmail() }
        try await Task.sleep(nanoseconds: 50_000_000)
        StubURLProtocol.delay = 0
        switchAccount(app, to: "acct_b")
        switchAccount(app, to: "acct_a")
        let outcome = await slowRemove.value
        XCTAssertEqual(outcome, .staleAccount)
        await app.refreshAccountEmail(reason: "settle", force: true)
        XCTAssertEqual(app.accountEmailState, .loaded(AccountEmail()), "A's address really was removed on the server, and the read shows it")
        XCTAssertEqual(server.account("acct_b").verified, "b@example.com", "B was never touched")
        // A failing slow write across a switch is stale too, with no message for B.
        switchAccount(app, to: "acct_b")
        server.failPOST = (502, "email_send_failed")
        StubURLProtocol.delay = 0.3
        let slowFail = Task { await app.addAccountEmail("c@example.com") }
        try await Task.sleep(nanoseconds: 50_000_000)
        StubURLProtocol.delay = 0
        switchAccount(app, to: "acct_a")
        let failOutcome = await slowFail.value
        XCTAssertEqual(failOutcome, .staleAccount)
    }

    func testMutationsFromThisClientRunInOrderAndAReadDuringOneCannotLeaveThePreWriteValue() async throws {
        let app = await makeApp()
        await app.refreshAccountEmail(reason: "test", force: true)
        let before = server.log.count
        StubURLProtocol.delay = 0.3
        let add = Task { await app.addAccountEmail("one@example.com") }
        try await Task.sleep(nanoseconds: 20_000_000)
        StubURLProtocol.delay = 0
        let remove = Task { await app.removeAccountEmail() }
        // A read while the add is in flight is kept, not run; it cannot show "no email".
        await app.refreshAccountEmail(reason: "activate")
        XCTAssertNotNil(app.accountEmailPending)
        let addOutcome = await add.value
        let removeOutcome = await remove.value
        XCTAssertEqual(addOutcome, .sent("one@example.com"))
        XCTAssertEqual(removeOutcome, .removed)
        let writes = server.log[before...].filter { !$0.hasPrefix("GET") }
        XCTAssertEqual(writes, ["POST acct_a", "DELETE acct_a"], "the remove waited for the add")
        XCTAssertEqual(app.accountEmailState, .loaded(AccountEmail()), "the reconciled server state after both")
        XCTAssertNil(server.account("acct_a").pending)
        XCTAssertNil(app.accountEmailPending)
    }

    func testRepeatedSendsCannotOvertakeOneAnother() async {
        let app = await makeApp()
        await app.refreshAccountEmail(reason: "test", force: true)
        async let first = app.addAccountEmail("x@example.com")
        async let second = app.addAccountEmail("x@example.com")
        let outcomes = await (first, second)
        XCTAssertEqual(outcomes.0, .sent("x@example.com"))
        XCTAssertEqual(outcomes.1, .sent("x@example.com"))
        XCTAssertEqual(server.log.filter { $0.hasPrefix("POST") }.count, 2)
        XCTAssertEqual(app.accountEmailState, .loaded(AccountEmail(pending: "x@example.com")))
    }

    func testASwitchDuringTheReconcilingReadMakesTheWriteStale() async throws {
        // Review 2026-10-27: the write finished on A; the read-back is still waiting when B
        // becomes current. A's success must not reach B's screen.
        let app = await makeApp(account: "acct_a")
        let originalHandler = StubURLProtocol.handler!
        StubURLProtocol.handler = { request in
            // Delay what follows a write: the reconciling read is the window under test.
            if request.httpMethod == "POST" || request.httpMethod == "DELETE" { StubURLProtocol.delay = 0.4 }
            return originalHandler(request)
        }
        let operation = Task { await app.addAccountEmail("review@example.com") }
        for _ in 0..<200 {
            if app.accountEmailInFlight { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(app.accountEmailInFlight, "the POST completed and its reconciliation GET is waiting")
        StubURLProtocol.delay = 0
        switchAccount(app, to: "acct_b")
        let outcome = await operation.value
        XCTAssertEqual(outcome, .staleAccount, "no success message from account A may be returned on B")
        XCTAssertEqual(server.account("acct_a").pending, "review@example.com", "the server kept A's write")
        // The same for a remove and for a failed write.
        switchAccount(app, to: "acct_a")
        await app.refreshAccountEmail(reason: "settle", force: true)
        let removal = Task { await app.removeAccountEmail() }
        for _ in 0..<200 {
            if app.accountEmailInFlight { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        StubURLProtocol.delay = 0
        switchAccount(app, to: "acct_b")
        let removeOutcome = await removal.value
        XCTAssertEqual(removeOutcome, .staleAccount)
    }

    // MARK: Refresh queue (F2)

    func testACallbackDuringAnOlderReadRunsAfterItAndShowsTheConfirmedAddress() async throws {
        let app = await makeApp()
        let base = gets()
        StubURLProtocol.delay = 0.3
        let slow = Task { await app.refreshAccountEmail(reason: "activate", force: true) }
        try await Task.sleep(nanoseconds: 50_000_000)
        StubURLProtocol.delay = 0
        server.set("acct_a", verified: "me@example.com", pending: nil)
        await app.refreshAccountEmail(reason: "browser callback", force: true)
        XCTAssertEqual(app.accountEmailPending, AccountEmailRefreshRequest(reason: "browser callback", force: true))
        await slow.value
        XCTAssertEqual(app.accountEmailState, .loaded(AccountEmail(verified: "me@example.com")), "the follow-up read saw the confirmation")
        XCTAssertEqual(gets(), base + 2)
        try await settle()
        XCTAssertEqual(gets(), base + 2, "completion does not requeue work")
    }

    func testAnAccountSwitchDuringAnOlderReadEndsWithTheNewAccountLoaded() async throws {
        let app = await makeApp(account: "acct_a")
        server.set("acct_b", verified: "b@example.com", pending: nil)
        StubURLProtocol.delay = 0.3
        let slow = Task { await app.refreshAccountEmail(reason: "activate", force: true) }
        try await Task.sleep(nanoseconds: 50_000_000)
        StubURLProtocol.delay = 0
        switchAccount(app, to: "acct_b")
        await slow.value
        try await settle()
        XCTAssertEqual(app.accountEmailState, .loaded(AccountEmail(verified: "b@example.com")), "not stuck loading, and not A's answer")
        XCTAssertFalse(server.log.suffix(1).contains("GET acct_a"))
    }

    func testForcedThenOrdinaryTriggersCoalesceIntoOneForcedFollowUp() async throws {
        let app = await makeApp()
        await app.refreshAccountEmail(reason: "first", force: true)
        let base = gets()
        StubURLProtocol.delay = 0.3
        let slow = Task { await app.refreshAccountEmail(reason: "callback", force: true) }
        try await Task.sleep(nanoseconds: 50_000_000)
        StubURLProtocol.delay = 0
        await app.refreshAccountEmail(reason: "activate 1")
        await app.refreshAccountEmail(reason: "activate 2")
        await app.refreshAccountEmail(reason: "callback 2", force: true)
        await app.refreshAccountEmail(reason: "activate 3")
        XCTAssertEqual(app.accountEmailPending?.force, true, "an ordinary trigger never downgrades a forced one")
        server.set("acct_a", verified: "me@example.com", pending: nil)
        await slow.value
        XCTAssertEqual(gets(), base + 2, "the slow read and one follow-up, never one per trigger")
        XCTAssertEqual(app.accountEmailState, .loaded(AccountEmail(verified: "me@example.com")))
    }

    func testAFailingOlderReadStillRunsTheForcedFollowUp() async throws {
        let app = await makeApp()
        server.failGET = (503, "cloud_unavailable")
        StubURLProtocol.delay = 0.3
        let slow = Task { await app.refreshAccountEmail(reason: "activate", force: true) }
        try await Task.sleep(nanoseconds: 50_000_000)
        StubURLProtocol.delay = 0
        await app.refreshAccountEmail(reason: "callback", force: true)
        server.failGET = nil
        server.set("acct_a", verified: "me@example.com", pending: nil)
        await slow.value
        XCTAssertEqual(app.accountEmailState, .loaded(AccountEmail(verified: "me@example.com")))
    }

    func testSignOutWhileAReadIsQueuedDiscardsIt() async throws {
        let app = await makeApp()
        let base = gets()
        StubURLProtocol.delay = 0.3
        let slow = Task { await app.refreshAccountEmail(reason: "activate", force: true) }
        try await Task.sleep(nanoseconds: 50_000_000)
        StubURLProtocol.delay = 0
        await app.refreshAccountEmail(reason: "callback", force: true)
        app.clientAuthManager = TestSupport.unenrolledAuthManager(session: session)
        app.refreshClientAuthStatus()
        await slow.value
        try await settle()
        XCTAssertNil(app.accountEmailPending)
        XCTAssertEqual(app.accountEmailState, .loading, "nothing of the old account shows after sign-out")
        XCTAssertEqual(gets(), base + 1, "no read for a signed-out device")
    }

    func testActivationRefreshIsFreshnessLimitedAndRetriesAfterUnavailable() async {
        let app = await makeApp()
        await app.refreshAccountEmail(reason: "first", force: true)
        let after = gets()
        await app.refreshAccountEmail(reason: "activate")
        XCTAssertEqual(gets(), after, "a load under 60 s old is fresh enough for an activation")
        app.accountEmailLastLoaded = nil
        server.failGET = (503, "cloud_unavailable")
        await app.refreshAccountEmail(reason: "activate")
        XCTAssertEqual(app.accountEmailState, .unavailable("The account service is unavailable right now."))
        // Another device added and confirmed an address meanwhile: the next activation sees it.
        server.failGET = nil
        server.set("acct_a", verified: "added@elsewhere.com", pending: nil)
        let before = gets()
        async let one: Void = app.refreshAccountEmail(reason: "activate")
        async let two: Void = app.refreshAccountEmail(reason: "activate")
        _ = await (one, two)
        XCTAssertEqual(gets(), before + 1, "two activations in flight send one request")
        XCTAssertEqual(app.accountEmailState, .loaded(AccountEmail(verified: "added@elsewhere.com")))
        XCTAssertFalse(AppState.accessCardVisible(enrolled: true, emailState: app.accountEmailState, hasSavedMeeting: true, recoveryKeyAcknowledged: false, dismissed: false), "device B drops its card once A's address arrives")
    }

    // MARK: The first saved meeting (F6)

    func testTheFirstFinishedMeetingSavedThroughTheQueueMakesTheCardEligible() async throws {
        let app = await makeApp(acknowledged: false)
        let container = try TestSupport.makeInMemoryContainer()
        app.modelContext = container.mainContext
        await app.refreshAccountEmail(reason: "test", force: true)
        XCTAssertEqual(app.accountEmailState, .loaded(AccountEmail()))
        XCTAssertFalse(app.showAccessCard, "no finished meeting yet")

        let meeting = Meeting(title: "first")
        meeting.endTime = Date()
        app.currentMeeting = meeting
        app.liveSegments = [AppState.LiveSegment(id: UUID(), text: "hello", speaker: 0, timestamp: 1, isFinal: true)]

        struct InjectedSaveFailure: Error {}
        app.persistenceSaveHandler = { _ in throw InjectedSaveFailure() }
        let failed = await app.saveCurrentMeetingAndWait()
        XCTAssertFalse(failed)
        XCTAssertFalse(app.showAccessCard, "a failed save leaves it hidden")

        app.persistenceSaveHandler = { try $0.save() }
        app.liveSegments.append(AppState.LiveSegment(id: UUID(), text: "again", speaker: 0, timestamp: 2, isFinal: true))
        let saved = await app.saveCurrentMeetingAndWait()
        XCTAssertTrue(saved)
        XCTAssertTrue(app.showAccessCard, "the successful commit made the card eligible without any other refresh")
    }
}

#if IOS_TEST_TARGET
final class SettingsNavigationPlanTests: XCTestCase {
    func testARequestPushesOrReusesTheDestinationAndDropsAnUnavailableOne() {
        let available = Set(SettingsDestination.available(on: .iOS))
        let account = SettingsNavigationRequest(destination: .account, target: "account.email")
        XCTAssertEqual(SettingsNavigationPlan.path(for: account, current: [], available: available), [SettingsRoute(destination: .account, target: "account.email")])
        let shown = [SettingsRoute(destination: .account, target: nil)]
        XCTAssertEqual(SettingsNavigationPlan.path(for: account, current: shown, available: available), shown, "already on Account: reuse it, the detail scrolls itself")
        let elsewhere = [SettingsRoute(destination: .cloud, target: nil)]
        XCTAssertEqual(SettingsNavigationPlan.path(for: account, current: elsewhere, available: available), [SettingsRoute(destination: .account, target: "account.email")], "another detail is replaced, not stacked")
        let unavailable = SettingsNavigationRequest(destination: .crm, target: "integrations.attio")
        XCTAssertNil(SettingsNavigationPlan.path(for: unavailable, current: [], available: available), "CRM is Mac only")
        let regular = SettingsNavigationPlan.regular(for: account, available: available)
        XCTAssertEqual(regular?.selection, .account)
        XCTAssertEqual(regular?.detailPath, [], "an iPad request clears whatever Privacy's Configure pushed under the previous selection")
        XCTAssertNil(SettingsNavigationPlan.regular(for: unavailable, available: available))
        XCTAssertEqual(SettingsNavigationPlan.sidebarSelection(for: account, available: available), .account)
        XCTAssertNil(SettingsNavigationPlan.sidebarSelection(for: unavailable, available: available))
    }

    func testResizingCarriesTheVisibleScreenBetweenLayoutsAndClearsTheOtherStack() {
        let available = Set(SettingsDestination.available(on: .iOS))
        // Regular: Privacy selected, Configure Cloud pushed.
        let pushed = [SettingsRoute(destination: .cloud, target: "cloud.sync")]
        // To compact: the visible Cloud screen, not Privacy, is what the stack shows.
        let compact = SettingsNavigationPlan.toCompact(selection: .privacy, detailPath: pushed)
        XCTAssertEqual(compact, pushed)
        // An Account request while compact replaces it.
        let request = SettingsNavigationRequest(destination: .account, target: "account.email")
        let afterRequest = SettingsNavigationPlan.path(for: request, current: compact, available: available)
        XCTAssertEqual(afterRequest, [SettingsRoute(destination: .account, target: "account.email")])
        // Back to regular: Account is the selection with a fresh detail stack and the target to scroll to.
        let regular = SettingsNavigationPlan.toRegular(path: afterRequest!, selection: .privacy)
        XCTAssertEqual(regular.selection, .account)
        XCTAssertEqual(regular.detailPath, [], "the old Cloud push never resurfaces")
        XCTAssertEqual(regular.target, "account.email")
        // General is a screen of its own (Appearance), pushed like any other; only no selection is the list.
        XCTAssertEqual(SettingsNavigationPlan.toCompact(selection: .general, detailPath: []), [SettingsRoute(destination: .general, target: nil)])
        XCTAssertEqual(SettingsNavigationPlan.toCompact(selection: nil, detailPath: []), [])
        XCTAssertEqual(SettingsNavigationPlan.toCompact(selection: .cloud, detailPath: []), [SettingsRoute(destination: .cloud, target: nil)])
        let plain = SettingsNavigationPlan.toRegular(path: [], selection: .cloud)
        XCTAssertEqual(plain.selection, .cloud)
        XCTAssertNil(plain.target)
    }

    @MainActor
    func testJumpToSettingPostsOneRequestOnIOS() {
        let app = AppState()
        app.settingsNavigationRequest = nil
        app.jumpToSetting("account.email")
        XCTAssertEqual(app.settingsNavigationRequest?.destination, .account)
        XCTAssertEqual(app.settingsNavigationRequest?.target, "account.email")
        XCTAssertEqual(app.selectedSettingsTab, SettingsDestination.account.rawValue)
        app.jumpToSetting("no.such.row")
        XCTAssertEqual(app.settingsNavigationRequest?.target, "account.email", "an unknown id posts nothing")
    }
}
#endif

private extension URLRequest {
    /// `authorize` through the manager, for the probe test's final proof that the key signs again.
    mutating func setValueForTesting(_ manager: ClientAuthManager) async throws {
        try await manager.authorize(&self)
    }
}

/// A store whose save blocks until released, to order a credential commit against a clear.
final class SaveGateStore: ClientAuthCredentialStore, @unchecked Sendable {
    let backing: InMemoryClientAuthStore
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    init(_ value: ClientAuthCredentials) { backing = InMemoryClientAuthStore(value) }
    func load() -> ClientAuthCredentials? { backing.load() }
    func clear() { backing.clear() }
    func save(_ value: ClientAuthCredentials) -> Bool {
        entered.signal()
        guard release.wait(timeout: .now() + 5) == .success else { return false }
        return backing.save(value)
    }
}

/// Pauses the real signing path after its signature and before authorize returns: the manager
/// reads the temporary-failure counter from its defaults right after a successful signature.
final class SigningDefaultsGate: UserDefaults, @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    private let gateLock = NSLock()
    private var armed = true
    override func object(forKey defaultName: String) -> Any? {
        gateLock.lock()
        let hold = defaultName == ClientAuthManager.keyUnavailableLaunchesKey && armed
        if hold { armed = false }
        gateLock.unlock()
        if hold {
            entered.signal()
            _ = release.wait(timeout: .now() + 5)
        }
        return super.object(forKey: defaultName)
    }
}
