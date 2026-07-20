import XCTest
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

final class MinitiAPIServiceTests: XCTestCase {

    // MARK: - Decoder helper

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            try MinitiAPIService.decodeFlexibleDate(from: decoder)
        }
        return d
    }

    // MARK: - UsageInfo decoding

    func testUsageInfoSnakeCase() throws {
        let json = """
        {
            "minutes_used": 123.5,
            "minutes_limit": 500,
            "resets_at": "2026-04-01T00:00:00Z",
            "tier": "free"
        }
        """.data(using: .utf8)!

        let info = try decoder.decode(MinitiAPIService.UsageInfo.self, from: json)
        XCTAssertEqual(info.minutesUsed, 123.5)
        XCTAssertEqual(info.minutesLimit, 500)
        XCTAssertEqual(info.tier, "free")
        XCTAssertFalse(info.isPro)
    }

    func testUsageInfoCamelCase() throws {
        let json = """
        {
            "minutesUsed": 250,
            "minutesLimit": 500,
            "resetsAt": "2026-04-01T00:00:00Z",
            "tier": "pro",
            "subscriptionStatus": "active"
        }
        """.data(using: .utf8)!

        let info = try decoder.decode(MinitiAPIService.UsageInfo.self, from: json)
        XCTAssertEqual(info.minutesUsed, 250)
        XCTAssertTrue(info.isPro)
        XCTAssertEqual(info.subscriptionStatus, "active")
    }

    func testUsageInfoStringNumbers() throws {
        let json = """
        {
            "minutes_used": "42.7",
            "minutes_limit": "500",
            "resets_at": "2026-04-01T00:00:00Z",
            "tier": "free"
        }
        """.data(using: .utf8)!

        let info = try decoder.decode(MinitiAPIService.UsageInfo.self, from: json)
        XCTAssertEqual(info.minutesUsed, 42.7, accuracy: 0.01)
        XCTAssertEqual(info.minutesLimit, 500)
    }

    func testUsageInfoDerivedProperties() throws {
        let json = """
        {
            "minutes_used": 450,
            "minutes_limit": 500,
            "resets_at": "2026-04-01T00:00:00Z",
            "tier": "free"
        }
        """.data(using: .utf8)!

        let info = try decoder.decode(MinitiAPIService.UsageInfo.self, from: json)
        XCTAssertEqual(info.minutesRemaining, 50)
        XCTAssertFalse(info.isLimitReached)
        XCTAssertEqual(info.usagePercentage, 0.9, accuracy: 0.01)
        XCTAssertEqual(info.formattedRemaining, "50m")
    }

    func testUsageInfoLimitReached() throws {
        let json = """
        {
            "minutes_used": 500,
            "minutes_limit": 500,
            "resets_at": "2026-04-01T00:00:00Z",
            "tier": "free"
        }
        """.data(using: .utf8)!

        let info = try decoder.decode(MinitiAPIService.UsageInfo.self, from: json)
        XCTAssertTrue(info.isLimitReached)
        XCTAssertEqual(info.minutesRemaining, 0)
    }

    func testUsageInfoFormattedRemainingHours() throws {
        let json = """
        {
            "minutes_used": 100,
            "minutes_limit": 5000,
            "resets_at": "2026-04-01T00:00:00Z",
            "tier": "pro"
        }
        """.data(using: .utf8)!

        let info = try decoder.decode(MinitiAPIService.UsageInfo.self, from: json)
        XCTAssertEqual(info.formattedRemaining, "81h 40m")
    }

    // MARK: - SessionResponse decoding

    func testSessionResponseAccessTokenCanonical() throws {
        let json = """
        {
            "access_token": "eyJhbGciOi.test",
            "token_type": "Bearer",
            "expires_in": 3600,
            "expires_at": "2026-04-01T04:00:00Z",
            "session_id": "sess_xyz"
        }
        """.data(using: .utf8)!

        let resp = try decoder.decode(MinitiAPIService.SessionResponse.self, from: json)
        XCTAssertEqual(resp.accessToken, "eyJhbGciOi.test")
        XCTAssertEqual(resp.tempApiKey, "eyJhbGciOi.test")
        XCTAssertEqual(resp.tokenType, "Bearer")
        XCTAssertEqual(resp.expiresIn, 3600)
        XCTAssertEqual(resp.sessionId, "sess_xyz")
    }

    func testSessionResponsePrefersAccessTokenOverTempApiKey() throws {
        let json = """
        {
            "access_token": "canonical-jwt",
            "temp_api_key": "deprecated-alias",
            "token_type": "Bearer",
            "expires_in": 1800,
            "expires_at": "2026-04-01T04:00:00Z",
            "session_id": "sess_both"
        }
        """.data(using: .utf8)!

        let resp = try decoder.decode(MinitiAPIService.SessionResponse.self, from: json)
        XCTAssertEqual(resp.accessToken, "canonical-jwt")
        XCTAssertEqual(resp.tempApiKey, "canonical-jwt")
    }

    func testSessionResponseFallsBackToTempApiKey() throws {
        let json = """
        {
            "temp_api_key": "abc123",
            "expires_at": "2026-04-01T04:00:00Z",
            "session_id": "sess_xyz"
        }
        """.data(using: .utf8)!

        let resp = try decoder.decode(MinitiAPIService.SessionResponse.self, from: json)
        XCTAssertEqual(resp.accessToken, "abc123")
        XCTAssertEqual(resp.tempApiKey, "abc123")
        XCTAssertEqual(resp.tokenType, "Bearer")
        XCTAssertEqual(resp.sessionId, "sess_xyz")
    }

    func testSessionResponseDerivesExpiresAtFromExpiresIn() throws {
        let before = Date()
        let json = """
        {
            "access_token": "jwt-no-expires-at",
            "token_type": "Bearer",
            "expires_in": 120,
            "session_id": "sess_ttl"
        }
        """.data(using: .utf8)!

        let resp = try decoder.decode(MinitiAPIService.SessionResponse.self, from: json)
        let after = Date()
        XCTAssertEqual(resp.expiresIn, 120)
        XCTAssertGreaterThanOrEqual(resp.expiresAt, before.addingTimeInterval(120))
        XCTAssertLessThanOrEqual(resp.expiresAt, after.addingTimeInterval(120))
    }

    func testSessionResponseThrowsWithoutExpiry() {
        let json = """
        {
            "access_token": "jwt-no-expiry",
            "session_id": "sess_bad"
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try decoder.decode(MinitiAPIService.SessionResponse.self, from: json))
    }

    func testSessionResponseIntSessionId() throws {
        let json = """
        {
            "access_token": "key123",
            "expires_at": "2026-04-01T04:00:00Z",
            "session_id": 42
        }
        """.data(using: .utf8)!

        let resp = try decoder.decode(MinitiAPIService.SessionResponse.self, from: json)
        XCTAssertEqual(resp.sessionId, "42")
    }

    func testSessionResponseThrowsOnEmpty() {
        let json = """
        {
            "access_token": "",
            "expires_at": "2026-04-01T04:00:00Z",
            "session_id": ""
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try decoder.decode(MinitiAPIService.SessionResponse.self, from: json))
    }

    // MARK: - EndSessionResponse decoding

    func testEndSessionResponseNumeric() throws {
        let json = """
        {
            "minutes_used": 15.5,
            "minutes_remaining": 484.5,
            "session_finalized": true
        }
        """.data(using: .utf8)!

        let resp = try decoder.decode(MinitiAPIService.EndSessionResponse.self, from: json)
        XCTAssertEqual(resp.minutesUsed, 15.5)
        XCTAssertEqual(resp.minutesRemaining, 484.5)
        XCTAssertEqual(resp.sessionFinalized, true)
    }

    func testEndSessionResponseStringNumbers() throws {
        let json = """
        {
            "minutes_used": "20",
            "minutes_remaining": "480"
        }
        """.data(using: .utf8)!

        let resp = try decoder.decode(MinitiAPIService.EndSessionResponse.self, from: json)
        XCTAssertEqual(resp.minutesUsed, 20)
        XCTAssertEqual(resp.minutesRemaining, 480)
        XCTAssertNil(resp.sessionFinalized)
    }

    // MARK: - AttioSendResponse

    func testAttioSendResponseTaskCount() throws {
        let json = """
        {
            "success": true,
            "note_ids": ["n1"],
            "task_ids": ["t1"],
            "task_count": 3
        }
        """.data(using: .utf8)!

        let resp = try decoder.decode(MinitiAPIService.AttioSendResponse.self, from: json)
        XCTAssertTrue(resp.success)
        XCTAssertEqual(resp.taskCount, 3)
        XCTAssertEqual(resp.noteIDs, ["n1"])
    }

    func testAttioSendResponseTasksSynced() throws {
        let json = """
        {
            "success": true,
            "tasks_synced": 5
        }
        """.data(using: .utf8)!

        let resp = try decoder.decode(MinitiAPIService.AttioSendResponse.self, from: json)
        XCTAssertEqual(resp.taskCount, 5)
    }

    func testAttioSendResponseTasksCreated() throws {
        let json = """
        {
            "success": true,
            "tasks_created": 2
        }
        """.data(using: .utf8)!

        let resp = try decoder.decode(MinitiAPIService.AttioSendResponse.self, from: json)
        XCTAssertEqual(resp.taskCount, 2)
    }

    // MARK: - AttioSearchRecord

    func testAttioSearchRecordSecondaryIdentifier() throws {
        let json = """
        {
            "id": {"workspace_id": "w1", "object_id": "o1", "record_id": "r1"},
            "record_text": "John Doe",
            "record_image": null,
            "object_slug": "people",
            "record_email": "john@example.com",
            "record_domain": null
        }
        """.data(using: .utf8)!

        let record = try decoder.decode(MinitiAPIService.AttioSearchRecord.self, from: json)
        XCTAssertEqual(record.secondaryIdentifier, "john@example.com")
        XCTAssertEqual(record.id, "people:r1")
    }

    func testAttioSearchRecordCompanyDomain() throws {
        let json = """
        {
            "id": {"workspace_id": "w1", "object_id": "o1", "record_id": "r2"},
            "record_text": "Acme Corp",
            "record_image": null,
            "object_slug": "companies",
            "record_email": null,
            "record_domain": "acme.com"
        }
        """.data(using: .utf8)!

        let record = try decoder.decode(MinitiAPIService.AttioSearchRecord.self, from: json)
        XCTAssertEqual(record.secondaryIdentifier, "acme.com")
    }

    // MARK: - ManagedInsightsResponse

    func testManagedInsightsResponseFullDecode() throws {
        let json = """
        {
            "summary": "A meeting about Q4 planning",
            "action_items": ["Review budget", "Schedule follow-up"],
            "topics": ["Budget", "Timeline"],
            "discussion_flow": ["Intro", "Budget review"],
            "title": "Q4 Planning",
            "metrics": "Revenue target: $10M",
            "economic_buyer": "CFO",
            "meta": {"degraded": false, "request_seq": 3}
        }
        """.data(using: .utf8)!

        let resp = try decoder.decode(ManagedInsightsResponse.self, from: json)
        XCTAssertEqual(resp.summary, "A meeting about Q4 planning")
        XCTAssertEqual(resp.actionItems.count, 2)
        XCTAssertEqual(resp.title, "Q4 Planning")
        XCTAssertEqual(resp.metrics, "Revenue target: $10M")
        XCTAssertEqual(resp.meta?.degraded, false)
        XCTAssertEqual(resp.meta?.requestSeq, 3)
    }

    func testManagedInsightsResponseMinimalDecode() throws {
        let json = "{}".data(using: .utf8)!

        let resp = try decoder.decode(ManagedInsightsResponse.self, from: json)
        XCTAssertEqual(resp.summary, "")
        XCTAssertTrue(resp.actionItems.isEmpty)
        XCTAssertTrue(resp.topics.isEmpty)
        XCTAssertNil(resp.title)
        XCTAssertNil(resp.metrics)
        XCTAssertNil(resp.meta)
    }

    func testManagedInsightsResponseToLiveInsights() throws {
        let json = """
        {
            "summary": "Test summary",
            "action_items": ["Action 1"],
            "topics": ["Topic 1"],
            "discussion_flow": ["Point 1"],
            "title": "Test Title",
            "champion": "Alice"
        }
        """.data(using: .utf8)!

        let resp = try decoder.decode(ManagedInsightsResponse.self, from: json)
        let live = resp.toLiveInsights()
        XCTAssertEqual(live.summary, "Test summary")
        XCTAssertEqual(live.actionItems, ["Action 1"])
        XCTAssertEqual(live.suggestedTitle, "Test Title")
        XCTAssertEqual(live.champion, "Alice")
    }

    // MARK: - ManagedInsightsMeta

    func testManagedInsightsMetaDegraded() throws {
        let json = """
        {"degraded": true, "fallback_reason": "timeout"}
        """.data(using: .utf8)!

        let meta = try decoder.decode(ManagedInsightsMeta.self, from: json)
        XCTAssertTrue(meta.degraded)
        XCTAssertEqual(meta.fallbackReason, "timeout")
    }

    func testManagedInsightsMetaDefaults() throws {
        let json = "{}".data(using: .utf8)!

        let meta = try decoder.decode(ManagedInsightsMeta.self, from: json)
        XCTAssertFalse(meta.degraded)
        XCTAssertNil(meta.fallbackReason)
    }

    // MARK: - AppleVerifyResponse

    func testAppleVerifyResponse() throws {
        let json = """
        {
            "success": true,
            "tier": "pro",
            "minutes_limit": 5000,
            "resets_at": "2026-04-01T00:00:00Z",
            "subscription_status": "active"
        }
        """.data(using: .utf8)!

        let resp = try decoder.decode(MinitiAPIService.AppleVerifyResponse.self, from: json)
        XCTAssertTrue(resp.success)
        XCTAssertEqual(resp.tier, "pro")
        XCTAssertEqual(resp.minutesLimit, 5000)
        XCTAssertEqual(resp.subscriptionStatus, "active")
    }

    func testAppleVerifyResponseStringMinutes() throws {
        let json = """
        {
            "success": true,
            "tier": "pro",
            "minutes_limit": "5000",
            "resets_at": "2026-04-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let resp = try decoder.decode(MinitiAPIService.AppleVerifyResponse.self, from: json)
        XCTAssertEqual(resp.minutesLimit, 5000)
    }

    // MARK: - Flexible date decoding

    func testTimestampToDateSeconds() {
        let date = MinitiAPIService.timestampToDate(1711929600)
        XCTAssertEqual(date.timeIntervalSince1970, 1711929600, accuracy: 1)
    }

    func testTimestampToDateMilliseconds() {
        let date = MinitiAPIService.timestampToDate(1711929600000)
        XCTAssertEqual(date.timeIntervalSince1970, 1711929600, accuracy: 1)
    }

    func testFlexibleDateISO8601() throws {
        let json = """
        {"resets_at": "2026-04-01T00:00:00Z", "minutes_used": 0, "minutes_limit": 500, "tier": "free"}
        """.data(using: .utf8)!

        let info = try decoder.decode(MinitiAPIService.UsageInfo.self, from: json)
        let cal = Calendar(identifier: .gregorian)
        let components = cal.dateComponents(in: TimeZone(identifier: "UTC")!, from: info.resetsAt)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 4)
        XCTAssertEqual(components.day, 1)
    }

    func testFlexibleDateISO8601FractionalSeconds() throws {
        let json = """
        {"resets_at": "2026-04-01T00:00:00.123Z", "minutes_used": 0, "minutes_limit": 500, "tier": "free"}
        """.data(using: .utf8)!

        let info = try decoder.decode(MinitiAPIService.UsageInfo.self, from: json)
        XCTAssertNotNil(info.resetsAt)
    }

    func testFlexibleDateNumericTimestamp() throws {
        let json = """
        {"resets_at": 1711929600, "minutes_used": 0, "minutes_limit": 500, "tier": "free"}
        """.data(using: .utf8)!

        let info = try decoder.decode(MinitiAPIService.UsageInfo.self, from: json)
        XCTAssertEqual(info.resetsAt.timeIntervalSince1970, 1711929600, accuracy: 1)
    }

    // MARK: - normalizedActionItems

    func testNormalizedActionItemsStripsBullets() {
        let items = ["- Review the budget", "* Send the email", "• Update the doc"]
        let result = AttioMeetingPayload.normalizedActionItems(from: items)
        XCTAssertEqual(result, ["Review the budget", "Send the email", "Update the doc"])
    }

    func testNormalizedActionItemsStripsCheckboxes() {
        let items = ["- [ ] Review budget", "- [x] Send email"]
        let result = AttioMeetingPayload.normalizedActionItems(from: items)
        XCTAssertEqual(result, ["Review budget", "Send email"])
    }

    func testNormalizedActionItemsFilterPlaceholders() {
        let items = ["None", "N/A", "No action items", "Real action"]
        let result = AttioMeetingPayload.normalizedActionItems(from: items)
        XCTAssertEqual(result, ["Real action"])
    }

    func testNormalizedActionItemsDeduplication() {
        let items = ["Review budget", "review budget", "REVIEW BUDGET"]
        let result = AttioMeetingPayload.normalizedActionItems(from: items)
        XCTAssertEqual(result.count, 1)
    }

    func testNormalizedActionItemsSplitsMultiline() {
        let items = ["- First item\n- Second item\n- Third item"]
        let result = AttioMeetingPayload.normalizedActionItems(from: items)
        XCTAssertEqual(result.count, 3)
    }

    // MARK: - APIError decoding

    func testAPIErrorDecoding() throws {
        let json = """
        {
            "error": "limit_reached",
            "message": "Monthly limit exceeded",
            "minutes_used": 500,
            "limit": 500,
            "resets_at": "2026-04-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let err = try decoder.decode(MinitiAPIService.APIError.self, from: json)
        XCTAssertEqual(err.error, "limit_reached")
        XCTAssertEqual(err.message, "Monthly limit exceeded")
        XCTAssertEqual(err.minutesUsed, 500)
        XCTAssertEqual(err.limit, 500)
    }

    // MARK: - VersionInfo decoding

    func testVersionInfoDecoding() throws {
        let json = """
        {
            "latest_version": "1.17.0",
            "download_url": "https://example.com/miniti.dmg",
            "release_notes": "Bug fixes"
        }
        """.data(using: .utf8)!

        let info = try decoder.decode(MinitiAPIService.VersionInfo.self, from: json)
        XCTAssertEqual(info.latestVersion, "1.17.0")
        XCTAssertEqual(info.downloadUrl, "https://example.com/miniti.dmg")
        XCTAssertEqual(info.releaseNotes, "Bug fixes")
        XCTAssertNil(info.minVersion)
    }

    func testVersionInfoDecodingWithMinVersion() throws {
        let json = """
        {
            "latest_version": "1.19.0",
            "min_version": "1.15.0",
            "download_url": "https://example.com/miniti.dmg",
            "release_notes": "New features"
        }
        """.data(using: .utf8)!

        let info = try decoder.decode(MinitiAPIService.VersionInfo.self, from: json)
        XCTAssertEqual(info.latestVersion, "1.19.0")
        XCTAssertEqual(info.minVersion, "1.15.0")
        XCTAssertEqual(info.downloadUrl, "https://example.com/miniti.dmg")
        XCTAssertEqual(info.releaseNotes, "New features")
    }
}
