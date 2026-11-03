import Foundation
import SwiftData
import XCTest
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

@MainActor
final class WireContractExchangeTests: XCTestCase {
    private func directory() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["MINITI_WIRE_DIR"], path.hasPrefix("/") else {
            throw XCTSkip("Run the dedicated cross-language exchange lane with MINITI_WIRE_DIR")
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func testCanonicalAuthFixtures() throws {
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(ContractFixtures.auth.utf8)) as? [String: Any])
        for row in try XCTUnwrap(fixture["body_hashes"] as? [[String: String]]) {
            XCTAssertEqual(ClientAuthCrypto.hashB64(Data(try XCTUnwrap(row["body"]).utf8)), row["bh"])
        }
        for row in try XCTUnwrap(fixture["recovery_key_normalization"] as? [[String: String]]) {
            XCTAssertEqual(ClientAuthCrypto.parseRecoveryKey(try XCTUnwrap(row["input"])), row["canonical"])
        }
        let thumbprint = try XCTUnwrap(fixture["jwk_thumbprint"] as? [String: Any])
        let jwk = try XCTUnwrap(thumbprint["jwk"] as? [String: String])
        XCTAssertEqual(ClientAuthCrypto.jwkThumbprint(x: try XCTUnwrap(jwk["x"]), y: try XCTUnwrap(jwk["y"])), thumbprint["jkt"] as? String)
    }

    func testExportForBackend() throws {
        let directory = try directory()
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        var fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(ContractFixtures.meeting.utf8)) as? [String: Any])
        fixture["future_field"] = ["nullable": NSNull(), "decimal": 1.25, "text": "é 日本語"] as [String: Any]
        fixture["start_time"] = "2026-10-01T09:00:00Z" // accepted old-client date spelling
        let decoded = try XCTUnwrap(MeetingSyncDocument.decode(fixture))
        let meeting = MeetingSyncDocument.makeMeeting(decoded, in: context)
        let body = try MeetingSyncDocument.encodeData(meeting, segments: meeting.segments)
        let key = InstallationKey.generate(preferSecureEnclave: false)
        let proof = try key.requestProof(accessToken: "synthetic.access.token", method: "PUT", target: "/api/sync/meetings/fixture", body: body, now: 1_700_000_000, jti: "wire-exchange-1")
        let payload: [String: Any] = ["body": String(decoding: body, as: UTF8.self), "public_jwk": key.publicJWK, "proof": proof]
        try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]).write(to: directory.appendingPathComponent("swift.json"), options: .atomic)
    }

    func testImportBackendResponse() throws {
        let directory = try directory()
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("swift.json"))) as? [String: Any])
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try XCTUnwrap(envelope["body"] as? String).utf8)) as? [String: Any])
        let returned = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("backend.json"))) as? [String: Any])
        let container = try TestSupport.makeInMemoryContainer()
        let decoded = try XCTUnwrap(MeetingSyncDocument.decode(returned))
        let meeting = MeetingSyncDocument.makeMeeting(decoded, in: ModelContext(container))
        let encoded = MeetingSyncDocument.encode(meeting, segments: meeting.segments)
        XCTAssertEqual(encoded as NSDictionary, original as NSDictionary)
        XCTAssertEqual(meeting.title, "Budget review")
        XCTAssertEqual(meeting.segments.count, 2)
        XCTAssertEqual(meeting.startTime, MeetingSyncDocument.date("2026-10-01T09:00:00.000Z"))
        try Data("decoded".utf8).write(to: directory.appendingPathComponent("swift-import.ok"))
    }
}
