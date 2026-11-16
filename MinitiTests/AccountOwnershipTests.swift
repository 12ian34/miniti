import Foundation
import XCTest
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

/// The app side of account ownership (3.11.0, AO2.6 and AO4.3): Pro only from the server, App
/// Store changes reaching the server and the four states that follow, the account-change
/// wording by `account_owns`, and update required. No StoreKit and no network: the server is
/// a stub and the rules are value types.
final class AccountOwnershipTests: XCTestCase {
    private typealias Sync = AppleEntitlementSync

    private var session: URLSession!
    private var server: FakeVerifyServer!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        session = TestSupport.stubbedSession()
        server = FakeVerifyServer()
        server.install()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Fixtures

    private static func usage(_ fields: [String: Any]) throws -> MinitiAPIService.UsageInfo {
        var json: [String: Any] = [
            "minutes_used": 100, "minutes_limit": 500, "tier": "free", "resets_at": "2026-12-01T00:00:00Z",
        ]
        for (key, value) in fields { json[key] = value }
        return try decodeUsage(JSONSerialization.data(withJSONObject: json))
    }

    private static func decodeUsage(_ data: Data) throws -> MinitiAPIService.UsageInfo {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MinitiAPIService.UsageInfo.self, from: data)
    }

    private func work(_ signed: String = "signed-1", account: String = "acct_a", generation: Int = 1) -> AppleEntitlementSync.Work {
        .init(signedTransaction: signed, accountID: account, signInGeneration: generation)
    }

    // MARK: - Each verify answer to its state

    func testSuccessIsProcessedOnAnyAttempt() {
        for attempt in 1...Sync.maxAttempts {
            XCTAssertEqual(Sync.state(after: .success, attempt: attempt), .processed)
        }
    }

    func testOwnedElsewhereEndsAtOnceWithoutAnotherAttempt() {
        for attempt in 1...Sync.maxAttempts {
            XCTAssertEqual(
                Sync.state(after: .refused(status: 409, code: "subscription_owned_elsewhere"), attempt: attempt),
                .ownedElsewhere
            )
        }
    }

    func testEveryOtherAnswerIsTriedAgainAndFailsAfterThreeAttempts() {
        let others: [AppleEntitlementSync.Answer] = [
            .refused(status: 409, code: "subscription_not_eligible"),
            .refused(status: 409, code: "something_new"),
            // The code alone is not enough: it is the 409 that says "owned elsewhere".
            .refused(status: 403, code: "subscription_owned_elsewhere"),
            .refused(status: 400, code: "invalid_transaction"),
            .refused(status: 500, code: "internal_error"),
            .refused(status: 503, code: "maintenance"),
            .unreachable,
        ]
        for answer in others {
            XCTAssertNil(Sync.state(after: answer, attempt: 1), "\(answer): a second attempt is due")
            XCTAssertNil(Sync.state(after: answer, attempt: 2), "\(answer): a third attempt is due")
            XCTAssertEqual(Sync.state(after: answer, attempt: 3), .failed, "\(answer)")
        }
    }

    func testThreeAttemptsAtGrowingIntervalsAndNoMore() {
        XCTAssertEqual(Sync.maxAttempts, 3)
        XCTAssertEqual(Sync.retryDelays.count, Sync.maxAttempts - 1)
        XCTAssertEqual(Sync.retryDelays, Sync.retryDelays.sorted(), "the intervals grow")
        XCTAssertLessThan(Sync.retryDelays[0], Sync.retryDelays[1])
        let longest = Double(Sync.maxAttempts) * Sync.attemptTimeout + Sync.retryDelays.reduce(0, +)
        XCTAssertLessThanOrEqual(longest, Sync.confirmingLimit, "three attempts and their waits fit in the confirming limit")
        XCTAssertEqual(Sync.confirmingLimit, 30)
    }

    @MainActor
    func testRunStopsAfterThreeFailuresWithTheTwoWaitsBetween() async {
        var attempts: [Int] = []
        var pauses: [TimeInterval] = []
        let result = await Sync.run(
            attempt: { attempts.append($0); return .unreachable },
            pause: { pauses.append($0) },
            isCurrent: { true }
        )
        XCTAssertEqual(result, .failed)
        XCTAssertEqual(attempts, [1, 2, 3])
        XCTAssertEqual(pauses, Sync.retryDelays, "no wait after the last attempt")
    }

    @MainActor
    func testRunEndsOnTheFirstFinalAnswer() async {
        var attempts = 0
        var pauses: [TimeInterval] = []
        let owned = await Sync.run(
            attempt: { _ in attempts += 1; return .refused(status: 409, code: Sync.ownedElsewhereCode) },
            pause: { pauses.append($0) },
            isCurrent: { true }
        )
        XCTAssertEqual(owned, .ownedElsewhere)
        XCTAssertEqual(attempts, 1, "owned elsewhere is not retried")
        XCTAssertEqual(pauses, [])

        attempts = 0
        let recovered = await Sync.run(
            attempt: { number in attempts += 1; return number == 2 ? .success : .refused(status: 500, code: "internal_error") },
            pause: { pauses.append($0) },
            isCurrent: { true }
        )
        XCTAssertEqual(recovered, .processed)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(pauses, [Sync.retryDelays[0]])
    }

    @MainActor
    func testNotEligibleIsOneOfAnythingElse() async {
        var attempts = 0
        let result = await Sync.run(
            attempt: { _ in attempts += 1; return .refused(status: 409, code: "subscription_not_eligible") },
            pause: { _ in },
            isCurrent: { true }
        )
        XCTAssertEqual(result, .failed, "the existing failure text, not the card")
        XCTAssertEqual(attempts, 3)
    }

    @MainActor
    func testRunStopsAtTheConfirmingLimit() async {
        var attempts = 0
        let result = await Sync.run(
            attempt: { _ in attempts += 1; return .unreachable },
            pause: { _ in },
            isCurrent: { true },
            hasExpired: { true }
        )
        XCTAssertEqual(result, .failed)
        XCTAssertEqual(attempts, 1, "no attempt starts after the limit")
    }

    // MARK: - Only identical work in progress is skipped

    func testIdenticalWorkInProgressIsSkipped() {
        var sync = Sync()
        XCTAssertTrue(sync.begin(work()))
        XCTAssertEqual(sync.state, .confirming)
        XCTAssertFalse(sync.begin(work()), "the same signed text for the same sign-in, still in progress")
        XCTAssertEqual(sync.inProgress.count, 1)
    }

    func testARenewalIsSentThoughItsOriginalTransactionIDWasSeen() {
        let first = Self.signedTransaction(originalID: "2000000123", transactionID: "2000000123", expires: 1_800_000_000)
        let renewal = Self.signedTransaction(originalID: "2000000123", transactionID: "2000000456", expires: 1_802_592_000)
        let revoked = Self.signedTransaction(originalID: "2000000123", transactionID: "2000000456", expires: 1_802_592_000, revoked: 1_801_000_000)
        XCTAssertNotEqual(first, renewal)
        XCTAssertNotEqual(renewal, revoked)

        var sync = Sync()
        XCTAssertTrue(sync.begin(work(first)))
        XCTAssertTrue(sync.begin(work(renewal)), "a renewal is other work even while the first is in progress")
        XCTAssertTrue(sync.begin(work(revoked)), "and so is a revocation")
        XCTAssertEqual(sync.inProgress.count, 3)

        // Seen and finished is not "in progress": the same text is sent again when reported again.
        XCTAssertTrue(sync.finish(work(first), with: .processed, currentAccountID: "acct_a", currentSignInGeneration: 1))
        XCTAssertTrue(sync.begin(work(first)))
    }

    func testTheSameTransactionIsSentAgainForAnotherSignIn() {
        var sync = Sync()
        XCTAssertTrue(sync.begin(work(account: "acct_a", generation: 1)))
        XCTAssertTrue(sync.begin(work(account: "acct_b", generation: 2)), "another account")
        XCTAssertTrue(sync.begin(work(account: "acct_a", generation: 3)), "the same account signed in again")
    }

    func testAnOlderTransactionAnsweringDoesNotSpeakForTheNewerOne() {
        var sync = Sync()
        XCTAssertTrue(sync.begin(work("old")))
        XCTAssertTrue(sync.begin(work("new")))
        XCTAssertTrue(sync.finish(work("old"), with: .ownedElsewhere, currentAccountID: "acct_a", currentSignInGeneration: 1))
        XCTAssertEqual(sync.state, .confirming, "the newer transaction is still being confirmed")
        XCTAssertTrue(sync.finish(work("new"), with: .processed, currentAccountID: "acct_a", currentSignInGeneration: 1))
        XCTAssertEqual(sync.state, .processed)
    }

    // MARK: - An answer for a previous account is discarded; the state resets

    func testAnAnswerForAPreviousAccountIsDiscarded() {
        var sync = Sync()
        XCTAssertTrue(sync.begin(work(account: "acct_a", generation: 1)))
        let applied = sync.finish(work(account: "acct_a", generation: 1), with: .ownedElsewhere,
                                  currentAccountID: "acct_b", currentSignInGeneration: 2)
        XCTAssertFalse(applied)
        XCTAssertEqual(sync.state, .idle, "the new account is not told its subscription is elsewhere")
        XCTAssertTrue(sync.inProgress.isEmpty)
    }

    func testAnAnswerForAnEarlierSignInOfTheSameAccountIsDiscarded() {
        var sync = Sync()
        XCTAssertTrue(sync.begin(work(account: "acct_a", generation: 1)))
        XCTAssertFalse(sync.finish(work(account: "acct_a", generation: 1), with: .processed,
                                   currentAccountID: "acct_a", currentSignInGeneration: 2))
        XCTAssertEqual(sync.state, .idle)
    }

    func testAnAnswerAfterSigningOutIsDiscarded() {
        var sync = Sync()
        XCTAssertTrue(sync.begin(work()))
        XCTAssertFalse(sync.finish(work(), with: .ownedElsewhere, currentAccountID: nil, currentSignInGeneration: 2))
        XCTAssertEqual(sync.state, .idle)
    }

    @MainActor
    func testRunDropsAnAnswerThatArrivesAfterTheAccountChanged() async {
        var current = true
        var attempts = 0
        let result = await Sync.run(
            attempt: { _ in attempts += 1; current = false; return .refused(status: 409, code: Sync.ownedElsewhereCode) },
            pause: { _ in },
            isCurrent: { current }
        )
        XCTAssertNil(result, "not owned elsewhere, not failed: nothing")
        XCTAssertEqual(attempts, 1, "and nothing more is sent for the previous account")
    }

    func testEveryStateResetsOnAnAccountChange() {
        for state in [Sync.State.confirming, .processed, .ownedElsewhere, .failed] {
            var sync = Sync()
            XCTAssertTrue(sync.begin(work()))
            if state != .confirming {
                XCTAssertTrue(sync.finish(work(), with: state, currentAccountID: "acct_a", currentSignInGeneration: 1))
            }
            XCTAssertEqual(sync.state, state)
            sync.signInChanged(accountID: "acct_b", signInGeneration: 2)
            XCTAssertEqual(sync.state, .idle, "\(state) described the previous account")
            XCTAssertTrue(sync.inProgress.isEmpty)
            XCTAssertNil(sync.subject)
        }
    }

    func testTheStateResetsOnSignOutAndOnSigningInAgain() {
        var sync = Sync()
        XCTAssertTrue(sync.begin(work()))
        XCTAssertTrue(sync.finish(work(), with: .ownedElsewhere, currentAccountID: "acct_a", currentSignInGeneration: 1))
        sync.signInChanged(accountID: nil, signInGeneration: 2)
        XCTAssertEqual(sync.state, .idle, "signed out")

        XCTAssertTrue(sync.begin(work()))
        XCTAssertTrue(sync.finish(work(), with: .failed, currentAccountID: "acct_a", currentSignInGeneration: 1))
        sync.signInChanged(accountID: "acct_a", signInGeneration: 2)
        XCTAssertEqual(sync.state, .idle, "the same account signed in again")
    }

    func testWorkAlreadyStartedForTheNewSignInSurvivesTheReset() {
        var sync = Sync()
        XCTAssertTrue(sync.begin(work(account: "acct_a", generation: 1)))
        XCTAssertTrue(sync.begin(work(account: "acct_b", generation: 2)))
        sync.signInChanged(accountID: "acct_b", signInGeneration: 2)
        XCTAssertEqual(sync.state, .confirming)
        XCTAssertEqual(sync.inProgress, [work(account: "acct_b", generation: 2)])
    }

    func testTheConfirmingLimitEndsAsFailedAndALateAnswerStillCounts() {
        var sync = Sync()
        XCTAssertTrue(sync.begin(work()))
        sync.expire(work())
        XCTAssertEqual(sync.state, .failed, "confirming lasts 30 seconds at most")
        XCTAssertTrue(sync.expired.contains(work()))
        XCTAssertFalse(sync.begin(work()), "still in progress, so not sent a second time")
        XCTAssertTrue(sync.finish(work(), with: .processed, currentAccountID: "acct_a", currentSignInGeneration: 1))
        XCTAssertEqual(sync.state, .processed)
        XCTAssertTrue(sync.expired.isEmpty)

        var other = Sync()
        other.expire(work())
        XCTAssertEqual(other.state, .idle, "nothing in progress, nothing to expire")
    }

    // MARK: - A pending state never reads as confirmed Pro

    func testNoStateIsProAndEachShowsItsOwnNotice() {
        XCTAssertEqual(Sync.notice(state: .idle, serverSaysPro: false), .none)
        XCTAssertEqual(Sync.notice(state: .confirming, serverSaysPro: false), .confirming)
        XCTAssertEqual(Sync.notice(state: .processed, serverSaysPro: false), .none, "whatever the refreshed usage says")
        XCTAssertEqual(Sync.notice(state: .ownedElsewhere, serverSaysPro: false), .ownedElsewhere)
        XCTAssertEqual(Sync.notice(state: .failed, serverSaysPro: false), .failed)
        for state in [Sync.State.idle, .confirming, .processed, .ownedElsewhere, .failed] {
            XCTAssertEqual(Sync.notice(state: state, serverSaysPro: true), .none, "\(state): the server says Pro, nothing to add")
        }
    }

    func testTheTextsShownForConfirmingAndFailed() {
        XCTAssertEqual(Sync.confirmingText, "Confirming your subscription…")
        XCTAssertEqual(Sync.failedText, "Purchase verified by Apple, but backend sync failed. Please try Restore Purchases.")
    }

    // MARK: - Wording by accountOwns

    private static let today = (
        switchByRecoveryKey: "Enter the recovery key of the account to switch to. This device keeps its meetings, usage, calendar and CRM connections. If that account has a Pro plan, this device gets it too. It leaves its current account; if that account is then empty, it is closed.",
        switchSummary: "Switch account signs this device in to another account by email or recovery key. It keeps its meetings; if that account has Pro, this device gets it too.",
        joinByEmail: "Enter the email on the account to join. miniti sends it a link; open it anywhere and press Approve. This device keeps its meetings, usage and connections and joins that account.",
        signOut: "This device can sign back in with the account's email or recovery key. Meetings stored on this device are not affected."
    )

    func testOwnershipFromAccountOwns() {
        XCTAssertEqual(AccountOwnership(accountOwns: nil), .device)
        XCTAssertEqual(AccountOwnership(accountOwns: 1), .account)
        for unknown in [2, 3, 7, 100, Int.max, 0, -1] {
            XCTAssertEqual(AccountOwnership(accountOwns: unknown), .unknown, "\(unknown) is a number this version does not know")
        }
    }

    func testWithoutAccountOwnsTheWordingIsExactlyTodays() {
        XCTAssertEqual(AccountChangeCopy.switchByRecoveryKey(.device), Self.today.switchByRecoveryKey)
        XCTAssertEqual(AccountChangeCopy.switchSummary(.device), Self.today.switchSummary)
        XCTAssertEqual(AccountChangeCopy.joinByEmail(.device), Self.today.joinByEmail)
        XCTAssertEqual(AccountChangeCopy.signOut(.device), Self.today.signOut)

        let model = AccountSectionModel.make(AccountSectionModel.Inputs())
        XCTAssertEqual(model.signOutMessage, Self.today.signOut)
        XCTAssertEqual(model.switchAccountSummary, Self.today.switchSummary)
    }

    func testWithAccountOwnsOneTheFourNewTexts() {
        XCTAssertEqual(
            AccountChangeCopy.switchByRecoveryKey(.account),
            "Enter the recovery key of the account to switch to. This device keeps its meetings and its calendar and CRM connections. Pro and minutes used stay with the account you are leaving, and you can sign back in to it. If the other account has Pro, this device gets it too."
        )
        XCTAssertEqual(
            AccountChangeCopy.switchSummary(.account),
            "Switch account signs this device in to another account by email or recovery key. It keeps its meetings. Pro and minutes used stay with the account you leave."
        )
        XCTAssertEqual(
            AccountChangeCopy.joinByEmail(.account),
            "Enter the email on the account to join. miniti sends it a link; open it anywhere and press Approve. This device keeps its meetings and connections and joins that account. Pro and minutes used stay with the account you leave."
        )
        XCTAssertEqual(
            AccountChangeCopy.signOut(.account),
            "This device can sign back in with the account's email or recovery key. Meetings stored on this device are not affected. Pro and minutes used stay with the account."
        )

        var inputs = AccountSectionModel.Inputs()
        inputs.accountOwns = 1
        let model = AccountSectionModel.make(inputs)
        XCTAssertEqual(model.signOutMessage, AccountChangeCopy.signOut(.account))
        XCTAssertEqual(model.switchAccountSummary, AccountChangeCopy.switchSummary(.account))
    }

    func testAnUnknownAccountOwnsPromisesNothingNew() {
        // The switch and join sheets are replaced by the update-required state; the texts
        // that stay on screen make no promise this version cannot know to be true.
        XCTAssertEqual(AccountChangeCopy.signOut(.unknown), Self.today.signOut)
        XCTAssertEqual(AccountChangeCopy.switchSummary(.unknown), Self.today.switchSummary)
        var inputs = AccountSectionModel.Inputs()
        inputs.accountOwns = 2
        XCTAssertEqual(AccountSectionModel.make(inputs).signOutMessage, Self.today.signOut)
    }

    func testTheNewWordingHasNoDashesAmpersandsOrCapitalisedName() {
        let texts = [AccountOwnership.device, .account, .unknown].flatMap { ownership in
            [AccountChangeCopy.switchByRecoveryKey(ownership), AccountChangeCopy.switchSummary(ownership),
             AccountChangeCopy.joinByEmail(ownership), AccountChangeCopy.signOut(ownership)]
        } + [AccountChangeCopy.updateRequired, Sync.confirmingText, Sync.failedText]
        for text in texts {
            XCTAssertFalse(text.contains("—"), text)
            XCTAssertFalse(text.contains("–"), text)
            XCTAssertFalse(text.contains("&"), text)
            XCTAssertFalse(text.contains("Miniti"), text)
        }
    }

    @MainActor
    func testTheAppReadsOwnershipFromTheLastUsageAnswer() throws {
        let app = AppState()
        app.usageInfo = nil
        XCTAssertEqual(app.accountOwnership, .device, "no answer yet: today's wording")
        XCTAssertNil(app.accountSectionInputs.accountOwns)

        app.usageInfo = try Self.usage([:])
        XCTAssertEqual(app.accountOwnership, .device)

        app.usageInfo = try Self.usage(["account_owns": 1])
        XCTAssertEqual(app.accountOwnership, .account)
        XCTAssertEqual(app.accountSectionInputs.accountOwns, 1)
        XCTAssertEqual(AccountSectionModel.make(app.accountSectionInputs).signOutMessage, AccountChangeCopy.signOut(.account))

        app.usageInfo = try Self.usage(["account_owns": 2])
        XCTAssertEqual(app.accountOwnership, .unknown, "update required in place of the switch and join sheets")
    }

    func testAppStorePlatformNoticeRequiresAnExplicitServerBoolean() throws {
        XCTAssertTrue(try Self.usage(["app_store_subscription_ios_only": true]).appStoreSubscriptionIOSOnly)
        XCTAssertFalse(try Self.usage([:]).appStoreSubscriptionIOSOnly)
        for value in [false, "true", 1, NSNull(), ["active": true]] as [Any] {
            XCTAssertFalse(try Self.usage(["app_store_subscription_ios_only": value]).appStoreSubscriptionIOSOnly)
        }
    }

    // MARK: - UsageInfo decoding

    func testUsageDecodesWithAccountOwnsAbsent() throws {
        let usage = try Self.usage([:])
        XCTAssertNil(usage.accountOwns)
        XCTAssertEqual(usage.minutesLimit, 500)
        XCTAssertEqual(usage.tier, "free")
    }

    func testUsageDecodesAccountOwnsOneAndTwo() throws {
        XCTAssertEqual(try Self.usage(["account_owns": 1]).accountOwns, 1)
        XCTAssertEqual(try Self.usage(["account_owns": 2]).accountOwns, 2)
        XCTAssertEqual(try Self.usage(["account_owns": 1.0]).accountOwns, 1, "a whole number written as a float")
    }

    func testUsageDecodesAccountOwnsAsAString() throws {
        // Vercel KV can hand numbers back as strings, as it does for the minutes.
        XCTAssertEqual(try Self.usage(["account_owns": "1"]).accountOwns, 1)
        XCTAssertEqual(try Self.usage(["account_owns": "2"]).accountOwns, 2)
        let words = try Self.usage(["account_owns": "account"])
        XCTAssertNil(words.accountOwns, "a string that is not a number is unreadable, not a failure")
        XCTAssertEqual(words.minutesUsed, 100, "and the rest of the answer still decodes")
        XCTAssertNil(try Self.usage(["account_owns": ""]).accountOwns)
    }

    func testUsageDecodesAccountOwnsNull() throws {
        let usage = try Self.usage(["account_owns": NSNull()])
        XCTAssertNil(usage.accountOwns)
        XCTAssertEqual(usage.minutesLimit, 500)
    }

    func testUsageDecodesAnythingElseInAccountOwnsWithoutFailing() throws {
        XCTAssertNil(try Self.usage(["account_owns": true]).accountOwns)
        XCTAssertNil(try Self.usage(["account_owns": ["a": 1]]).accountOwns)
        XCTAssertNil(try Self.usage(["account_owns": [1, 2]]).accountOwns)
        XCTAssertNil(try Self.usage(["account_owns": 1.5]).accountOwns)
        let huge = try Self.decodeUsage(Data(#"{"minutes_used":1,"minutes_limit":500,"tier":"free","account_owns":1e300}"#.utf8))
        XCTAssertEqual(AccountOwnership(accountOwns: huge.accountOwns), .unknown, "a number too large to hold is still a number it does not know")
    }

    func testAccountOwnsDoesNotChangeProOrTheLimit() throws {
        let free = try Self.usage(["account_owns": 1])
        XCTAssertFalse(free.isPro)
        let pro = try Self.usage(["account_owns": 1, "tier": "pro", "minutes_limit": 5000, "minutes_used": 0])
        XCTAssertTrue(pro.isPro)
        XCTAssertEqual(pro.minutesLimit, 5000)
        XCTAssertEqual(pro.minutesUsed, 0, "a figure that drops to zero is accepted")
    }

    // MARK: - 426 to update required

    private func manager() -> ClientAuthManager {
        TestSupport.enrolledAuthManager(session: session)
    }

    func testUpdateRequiredText() {
        XCTAssertEqual(ClientAuthError.updateRequired.errorDescription, "Update miniti to change accounts.")
        XCTAssertEqual(ClientAuthError.updateRequired.localizedDescription, "Update miniti to change accounts.")
        XCTAssertEqual(AccountChangeCopy.updateRequired, "Update miniti to change accounts.")
    }

    func testA426OnAttachIsUpdateRequired() async {
        StubURLProtocol.script = { _ in StubURLProtocol.json(426, #"{"error":"update_miniti_to_change_account"}"#) }
        do {
            _ = try await manager().attachToAccount(recoveryKeyInput: ClientAuthCrypto.formatRecoveryKey(ClientAuthCrypto.generateRecoveryKey()))
            XCTFail("expected updateRequired")
        } catch {
            XCTAssertEqual(error as? ClientAuthError, .updateRequired)
        }
    }

    func testAny426IsUpdateRequiredWhateverTheBody() async {
        for body in ["", "not json", #"{"error":"something_else","message":"x"}"#, #"{}"#] {
            StubURLProtocol.script = { _ in StubURLProtocol.json(426, body) }
            do {
                _ = try await manager().attachToAccount(recoveryKeyInput: ClientAuthCrypto.formatRecoveryKey(ClientAuthCrypto.generateRecoveryKey()))
                XCTFail("expected updateRequired for body \(body)")
            } catch {
                XCTAssertEqual(error as? ClientAuthError, .updateRequired, "body: \(body)")
            }
        }
    }

    func testA426OnRestoreIsUpdateRequiredAndOtherRefusalsAreUnchanged() async {
        let unenrolled = TestSupport.unenrolledAuthManager(session: session)
        StubURLProtocol.script = { request in
            request.url?.path.hasSuffix("/auth/challenge") == true
                ? StubURLProtocol.json(200, #"{"challenge_id":"c1","nonce":"n1","expires_in":120}"#)
                : StubURLProtocol.json(426, #"{"error":"update_miniti_to_change_account"}"#)
        }
        do {
            try await unenrolled.restoreAccount(recoveryKeyInput: ClientAuthCrypto.formatRecoveryKey(ClientAuthCrypto.generateRecoveryKey()), label: "iPhone")
            XCTFail("expected updateRequired")
        } catch {
            XCTAssertEqual(error as? ClientAuthError, .updateRequired)
        }

        // The pause still reads as it did, and an unknown refusal still carries its code.
        StubURLProtocol.script = { _ in StubURLProtocol.json(503, #"{"error":"maintenance"}"#) }
        do {
            _ = try await manager().attachToAccount(recoveryKeyInput: ClientAuthCrypto.formatRecoveryKey(ClientAuthCrypto.generateRecoveryKey()))
            XCTFail("expected unavailable")
        } catch {
            XCTAssertEqual(error as? ClientAuthError, .unavailable)
            XCTAssertEqual(error.localizedDescription, "Device authorization is temporarily unavailable. Try again shortly.")
        }
        StubURLProtocol.script = { _ in StubURLProtocol.json(418, #"{"error":"teapot"}"#) }
        do {
            _ = try await manager().attachToAccount(recoveryKeyInput: ClientAuthCrypto.formatRecoveryKey(ClientAuthCrypto.generateRecoveryKey()))
            XCTFail("expected server error")
        } catch {
            XCTAssertEqual(error as? ClientAuthError, .server(code: "teapot", status: 418))
        }
    }

    func testTheSheetsReceiveTheUpdateTextFromEveryAccountChange() {
        // What `managedEnrollmentError` holds after a 426, by each path that sets it: the
        // sheets compare it with this text to show the Update button.
        XCTAssertEqual(AppState.joinFailure(for: ClientAuthError.updateRequired, keyWasUnusable: false).message, AccountChangeCopy.updateRequired)
        XCTAssertEqual(AppState.joinFailure(for: ClientAuthError.updateRequired, keyWasUnusable: true).message, AccountChangeCopy.updateRequired)
        XCTAssertEqual(AppState.emailStartFailure(for: ClientAuthError.updateRequired).message, AccountChangeCopy.updateRequired)
    }

    @MainActor
    func testA426WhileSwitchingLeavesTheUpdateTextAndTheAccountUnchanged() async throws {
        let app = AppState()
        app.appModeRaw = AppMode.managed.rawValue
        let auth = manager()
        app.clientAuthManager = auth
        app.minitiAPIService = MinitiAPIService(session: session, auth: auth)
        app.refreshClientAuthStatus()
        StubURLProtocol.script = { request in
            request.url?.path.hasSuffix("/auth/account/attach") == true
                ? StubURLProtocol.json(426, #"{"error":"update_miniti_to_change_account"}"#)
                : StubURLProtocol.json(404, #"{"error":"not_found"}"#)
        }
        let moved = await app.attachManagedDevice(recoveryKey: ClientAuthCrypto.formatRecoveryKey(ClientAuthCrypto.generateRecoveryKey()))
        XCTAssertFalse(moved)
        XCTAssertEqual(app.managedEnrollmentError, "Update miniti to change accounts.")
        XCTAssertEqual(app.clientAuthStatus.accountID, "acct_test", "a refused move changes nothing")
        XCTAssertFalse(app.accountTransitionInFlight)
    }

    // MARK: - Fixtures for signed transactions

    /// Shaped like a signed App Store transaction: three base64url parts, the middle one the
    /// payload. Never verified here; only its text matters.
    private static func signedTransaction(originalID: String, transactionID: String, expires: Int, revoked: Int? = nil) -> String {
        var payload: [String: Any] = [
            "originalTransactionId": originalID, "transactionId": transactionID,
            "productId": "com.miniti.mobile.pro.monthlysub", "expiresDate": expires,
        ]
        if let revoked { payload["revocationDate"] = revoked }
        let body = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let part: (Data) -> String = {
            $0.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        return [part(Data(#"{"alg":"ES256"}"#.utf8)), part(body), part(Data(transactionID.utf8))].joined(separator: ".")
    }
}

/// `/api/apple/verify` and `/api/usage` behind the stub. Every other path is not found.
final class FakeVerifyServer: @unchecked Sendable {
    private let lock = NSLock()
    private var verifyAnswers: [StubURLProtocol.Reply] = []
    private var usageBody = #"{"minutes_used":10,"minutes_limit":500,"tier":"free","resets_at":"2026-12-01T00:00:00Z"}"#
    private var sent: [String] = []
    private var usageReads = 0

    static let processed = StubURLProtocol.json(200, #"{"success":true,"tier":"pro","minutes_limit":5000,"resets_at":"2026-12-01T00:00:00Z"}"#)
    static let ownedElsewhere = StubURLProtocol.json(409, #"{"error":"subscription_owned_elsewhere"}"#)
    static let notEligible = StubURLProtocol.json(409, #"{"error":"subscription_not_eligible"}"#)
    static let serverError = StubURLProtocol.json(500, #"{"error":"internal_error","message":"down"}"#)
    static let freeUsage = #"{"minutes_used":10,"minutes_limit":500,"tier":"free","resets_at":"2026-12-01T00:00:00Z","account_owns":1}"#
    static let proUsage = #"{"minutes_used":10,"minutes_limit":5000,"tier":"pro","resets_at":"2026-12-01T00:00:00Z","account_owns":1}"#

    /// The answers `/api/apple/verify` gives, in order; the last one repeats.
    func answer(_ replies: StubURLProtocol.Reply...) { lock.withLock { verifyAnswers = replies } }
    func usage(_ body: String) { lock.withLock { usageBody = body } }
    /// The signed transactions the server answered, in order.
    var transactions: [String] { lock.withLock { sent } }
    var usageCount: Int { lock.withLock { usageReads } }

    /// Requests that left the device for verify, answered or still held by a gate.
    static var verifyRequests: Int {
        StubURLProtocol.requests.filter { $0.url?.path.hasSuffix("/apple/verify") == true }.count
    }

    func install() {
        StubURLProtocol.script = { [self] request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/apple/verify") {
                let body = (try? JSONSerialization.jsonObject(with: TestSupport.bodyData(of: request))) as? [String: Any]
                return lock.withLock {
                    sent.append(body?["signed_transaction_jws"] as? String ?? "")
                    let reply = verifyAnswers.count > 1 ? verifyAnswers.removeFirst() : (verifyAnswers.first ?? Self.serverError)
                    return reply
                }
            }
            if path.hasSuffix("/usage") {
                return lock.withLock {
                    usageReads += 1
                    return StubURLProtocol.json(200, usageBody)
                }
            }
            return StubURLProtocol.json(404, #"{"error":"not_found"}"#)
        }
    }
}

#if os(iOS)
/// The same rules through `AppState`, with the server stubbed: what is sent, what is shown,
/// and that the local App Store flag grants nothing.
@MainActor
final class AppStoreEntitlementSyncTests: XCTestCase {
    private var session: URLSession!
    private var server: FakeVerifyServer!
    private var pauses: [TimeInterval] = []

    override func setUp() async throws {
        StubURLProtocol.reset()
        session = TestSupport.stubbedSession()
        server = FakeVerifyServer()
        server.install()
        pauses = []
    }

    override func tearDown() async throws {
        StubURLProtocol.reset()
    }

    private func manager(_ account: String) -> ClientAuthManager {
        var credentials = TestSupport.enrolledCredentials(accessToken: account)
        credentials.accountID = account
        return TestSupport.enrolledAuthManager(session: session, credentials: credentials)
    }

    /// A signed-in managed app whose every request goes to the stub and whose waits between
    /// verify attempts take no time.
    private func makeApp(account: String = "acct_a") -> AppState {
        let app = AppState()
        app.appModeRaw = AppMode.managed.rawValue
        let auth = manager(account)
        app.clientAuthManager = auth
        app.minitiAPIService = MinitiAPIService(session: session, auth: auth)
        app.refreshClientAuthStatus()
        // Under XCTest the usage read skips enrolment unless a test says the device is enrolled.
        app.managedEnrollmentTestResult = true
        app.appleVerifyPause = { [weak self] seconds in self?.pauses.append(seconds) }
        return app
    }

    private func switchAccount(_ app: AppState, to account: String) {
        let auth = manager(account)
        app.clientAuthManager = auth
        app.minitiAPIService = MinitiAPIService(session: session, auth: auth)
        app.refreshClientAuthStatus()
    }

    private static func usage(tier: String = "free", used: Double = 100, limit: Double = 500, extra: [String: Any] = [:]) throws -> MinitiAPIService.UsageInfo {
        var json: [String: Any] = ["minutes_used": used, "minutes_limit": limit, "tier": tier, "resets_at": "2026-12-01T00:00:00Z"]
        for (key, value) in extra { json[key] = value }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MinitiAPIService.UsageInfo.self, from: JSONSerialization.data(withJSONObject: json))
    }

    // MARK: The six places the local flag is removed

    func testTheLocalFlagDoesNotLiftTheLimit() throws {
        let app = AppState()
        app.appModeRaw = AppMode.managed.rawValue
        app.hasActiveAppStoreSubscription = true
        app.usageInfo = try Self.usage(used: 500, limit: 500)
        XCTAssertTrue(app.isLimitReached, "the server's answer only")
        app.usageInfo = try Self.usage(used: 100, limit: 500)
        XCTAssertFalse(app.isLimitReached)
        app.usageInfo = nil
        XCTAssertFalse(app.isLimitReached)
    }

    func testTheLocalFlagIsNotPro() throws {
        let app = AppState()
        app.appModeRaw = AppMode.managed.rawValue
        app.hasActiveAppStoreSubscription = true
        app.usageInfo = nil
        XCTAssertFalse(app.isPro, "no answer from the server is not Pro")
        XCTAssertFalse(app.planShowsPro)
        XCTAssertFalse(app.accountSectionInputs.isPro)
        app.usageInfo = try Self.usage(tier: "free")
        XCTAssertFalse(app.isPro)
        XCTAssertFalse(app.canAutoLookupDocs)
        app.usageInfo = try Self.usage(tier: "pro", limit: 5000)
        XCTAssertTrue(app.isPro, "server Pro is Pro")
        app.hasActiveAppStoreSubscription = false
        XCTAssertTrue(app.isPro, "with or without the flag")
    }

    func testThePlanPlaceholderFollowsTheServer() throws {
        let app = AppState()
        app.appModeRaw = AppMode.managed.rawValue
        app.hasActiveAppStoreSubscription = true
        app.usageInfo = nil
        app.isLoadingUsage = true
        XCTAssertTrue(app.shouldShowManagedSubscriptionPlaceholder, "still checking, whatever StoreKit says")
        app.usageInfo = try Self.usage()
        XCTAssertFalse(app.shouldShowManagedSubscriptionPlaceholder)
    }

    func testTheMinutesLimitIsTheServers() throws {
        let app = AppState()
        app.appModeRaw = AppMode.managed.rawValue
        app.hasActiveAppStoreSubscription = true
        app.usageInfo = nil
        XCTAssertEqual(app.displayMinutesLimit, 500, "no hard-coded 5,000 from the flag")
        app.usageInfo = try Self.usage(tier: "free", limit: 500)
        XCTAssertEqual(app.displayMinutesLimit, 500)
        app.usageInfo = try Self.usage(tier: "pro", limit: 3000)
        XCTAssertEqual(app.displayMinutesLimit, 3000, "the server's minutes_limit, not a constant")
    }

    func testALimitRefusalShowsTheNormalLimitMessage() async throws {
        let app = makeApp()
        app.hasActiveAppStoreSubscription = true
        StubURLProtocol.script = { _ in StubURLProtocol.json(402, #"{"error":"limit_reached","minutes_used":500}"#) }
        let started = await app.refreshManagedDeepgramCredential(trigger: "start")
        XCTAssertFalse(started)
        XCTAssertEqual(app.managedSessionError, "Monthly limit reached (500 min used).")
        XCTAssertEqual(app.recordingErrorMessage, "Monthly limit reached (500 min used).")
        XCTAssertFalse(app.managedSessionError?.contains("catching up") ?? false)
    }

    func testComplimentaryProFollowsTheServer() throws {
        let app = AppState()
        app.appModeRaw = AppMode.managed.rawValue
        app.hasActiveAppStoreSubscription = true
        app.usageInfo = try Self.usage(tier: "pro", limit: 5000, extra: ["entitlement_source": "comp", "comp_until": "2099-01-01T00:00:00Z"])
        XCTAssertNotNil(app.compPro, "the grant the server describes is shown, with or without the flag")
        XCTAssertNil(app.endedCompPro)
        app.usageInfo = try Self.usage(tier: "pro", limit: 5000, extra: ["entitlement_source": "comp", "comp_until": "2020-01-01T00:00:00Z"])
        XCTAssertNil(app.compPro)
        XCTAssertNotNil(app.endedCompPro, "an ended grant shows as ended")
        XCTAssertFalse(app.planShowsPro)
    }

    // MARK: Each verify answer through the app

    func testSuccessIsProcessedAndProIsWhatTheUsageAnswerSays() async {
        let app = makeApp()
        server.answer(FakeVerifyServer.processed)
        server.usage(FakeVerifyServer.freeUsage)
        let state = await app.syncAppleEntitlementToBackend(signedTransaction: "signed-1")
        XCTAssertEqual(state, .processed)
        XCTAssertEqual(app.appleEntitlementSync.state, .processed)
        XCTAssertEqual(server.transactions, ["signed-1"])
        XCTAssertEqual(server.usageCount, 1, "the usage refresh that follows")
        XCTAssertFalse(app.isPro, "the verify answer said pro; only the usage answer counts")
        XCTAssertFalse(app.planShowsPro)
        XCTAssertEqual(app.displayMinutesLimit, 500)
        XCTAssertEqual(app.appleEntitlementNotice, .none)

        server.usage(FakeVerifyServer.proUsage)
        let again = await app.syncAppleEntitlementToBackend(signedTransaction: "signed-2")
        XCTAssertEqual(again, .processed)
        XCTAssertTrue(app.isPro, "now the usage answer says so")
        XCTAssertEqual(app.displayMinutesLimit, 5000)
        XCTAssertEqual(pauses, [], "nothing was retried")
    }

    func testOwnedElsewhereShowsTheCardOnceAndKeepsFreeRecording() async throws {
        let app = makeApp()
        app.hasActiveAppStoreSubscription = true
        app.usageInfo = try Self.usage(tier: "free", used: 100, limit: 500)
        server.answer(FakeVerifyServer.ownedElsewhere)
        let state = await app.syncAppleEntitlementToBackend(signedTransaction: "signed-1")
        XCTAssertEqual(state, .ownedElsewhere)
        XCTAssertEqual(app.appleEntitlementNotice, .ownedElsewhere)
        XCTAssertEqual(FakeVerifyServer.verifyRequests, 1, "no retry loop")
        XCTAssertEqual(pauses, [])
        XCTAssertFalse(app.isPro)
        XCTAssertFalse(app.isLimitReached, "the free plan still records")
        XCTAssertTrue(app.canStartRecording)
        XCTAssertNil(app.appStorePurchaseFailureMessage(fallback: "Purchase not completed."), "the card says it; no second message")

        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(FakeVerifyServer.verifyRequests, 1, "and nothing is sent later by itself")
    }

    func testNotEligibleAndOtherFailuresEndAsFailedAfterThreeAttempts() async {
        for answer in [FakeVerifyServer.notEligible, FakeVerifyServer.serverError] {
            StubURLProtocol.reset()
            session = TestSupport.stubbedSession()
            server = FakeVerifyServer()
            server.install()
            pauses = []
            let app = makeApp()
            server.answer(answer)
            let state = await app.syncAppleEntitlementToBackend(signedTransaction: "signed-1")
            XCTAssertEqual(state, .failed)
            XCTAssertEqual(app.appleEntitlementNotice, .failed, "today's message with Restore Purchases, not the card")
            XCTAssertEqual(server.transactions, ["signed-1", "signed-1", "signed-1"], "three attempts")
            XCTAssertEqual(pauses, AppleEntitlementSync.retryDelays, "at growing intervals")
            XCTAssertEqual(server.usageCount, 0)
            XCTAssertFalse(app.isPro)
        }
    }

    func testAFailureThenSuccessIsProcessed() async {
        let app = makeApp()
        server.answer(FakeVerifyServer.serverError, FakeVerifyServer.processed)
        server.usage(FakeVerifyServer.proUsage)
        let state = await app.syncAppleEntitlementToBackend(signedTransaction: "signed-1")
        XCTAssertEqual(state, .processed)
        XCTAssertEqual(server.transactions.count, 2)
        XCTAssertEqual(pauses, [AppleEntitlementSync.retryDelays[0]])
        XCTAssertTrue(app.isPro)
    }

    func testNothingIsSentWithoutAnAccount() async {
        let app = AppState()
        app.appModeRaw = AppMode.managed.rawValue
        let auth = TestSupport.unenrolledAuthManager(session: session)
        app.clientAuthManager = auth
        app.minitiAPIService = MinitiAPIService(session: session, auth: auth)
        let state = await app.syncAppleEntitlementToBackend(signedTransaction: "signed-1")
        XCTAssertNil(state)
        XCTAssertEqual(FakeVerifyServer.verifyRequests, 0)
        XCTAssertEqual(app.appleEntitlementSync.state, .idle, "no failure shown at launch for a device with no account yet")
    }

    // MARK: Pending is never Pro

    func testWhileConfirmingNothingReadsAsPro() async throws {
        let app = makeApp()
        app.hasActiveAppStoreSubscription = true
        app.usageInfo = try Self.usage(tier: "free", used: 500, limit: 500)
        let gate = StubURLProtocol.ResponseGate()
        StubURLProtocol.context.gate = gate
        server.answer(FakeVerifyServer.processed)
        server.usage(FakeVerifyServer.proUsage)
        let sending = Task { await app.syncAppleEntitlementToBackend(signedTransaction: "signed-1") }
        try await TestSupport.waitUntil { FakeVerifyServer.verifyRequests == 1 }

        XCTAssertEqual(app.appleEntitlementSync.state, .confirming)
        XCTAssertEqual(app.appleEntitlementNotice, .confirming)
        XCTAssertFalse(app.isPro)
        XCTAssertFalse(app.planShowsPro)
        XCTAssertEqual(app.displayMinutesLimit, 500)
        XCTAssertTrue(app.isLimitReached, "the limit is the server's until the server says otherwise")
        XCTAssertNil(app.compPro)

        gate.release()
        let state = await sending.value
        XCTAssertEqual(state, .processed)
        XCTAssertTrue(app.isPro)
        XCTAssertFalse(app.isLimitReached)
    }

    // MARK: Only identical work in progress is skipped

    func testTheSameTransactionInProgressIsSentOnce() async throws {
        let app = makeApp()
        let gate = StubURLProtocol.ResponseGate()
        StubURLProtocol.context.gate = gate
        server.answer(FakeVerifyServer.processed)
        let first = Task { await app.syncAppleEntitlementToBackend(signedTransaction: "signed-1") }
        try await TestSupport.waitUntil { FakeVerifyServer.verifyRequests == 1 }
        let second = Task { await app.syncAppleEntitlementToBackend(signedTransaction: "signed-1") }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(FakeVerifyServer.verifyRequests, 1, "identical work in progress is not sent again")
        gate.release()
        let (a, b) = (await first.value, await second.value)
        XCTAssertEqual(a, .processed)
        XCTAssertEqual(b, .processed, "the second caller gets the first one's answer")
        XCTAssertEqual(server.transactions, ["signed-1"])
    }

    func testARenewalAndARevocationAreBothSent() async throws {
        let app = makeApp()
        server.answer(FakeVerifyServer.processed)
        // One original transaction id throughout; only the signed text differs.
        let purchase = "header.eyJvcmlnaW5hbFRyYW5zYWN0aW9uSWQiOiIyMDAwMDAwMTIzIiwidCI6MX0.sig1"
        let renewal = "header.eyJvcmlnaW5hbFRyYW5zYWN0aW9uSWQiOiIyMDAwMDAwMTIzIiwidCI6Mn0.sig2"
        let revocation = "header.eyJvcmlnaW5hbFRyYW5zYWN0aW9uSWQiOiIyMDAwMDAwMTIzIiwidCI6MiwiciI6MX0.sig3"
        for signed in [purchase, renewal, revocation] {
            let state = await app.syncAppleEntitlementToBackend(signedTransaction: signed)
            XCTAssertEqual(state, .processed)
        }
        XCTAssertEqual(server.transactions, [purchase, renewal, revocation], "each whole signed text reaches verify")

        // And a renewal is not held back by the purchase still being in progress.
        let gate = StubURLProtocol.ResponseGate()
        StubURLProtocol.context.gate = gate
        let first = Task { await app.syncAppleEntitlementToBackend(signedTransaction: purchase) }
        try await TestSupport.waitUntil { FakeVerifyServer.verifyRequests == 4 }
        let second = Task { await app.syncAppleEntitlementToBackend(signedTransaction: renewal) }
        try await TestSupport.waitUntil { FakeVerifyServer.verifyRequests == 5 }
        gate.release()
        _ = await (first.value, second.value)
        XCTAssertEqual(server.transactions.count, 5)
    }

    // MARK: Account changes

    func testAnAnswerForThePreviousAccountIsDiscarded() async throws {
        let app = makeApp(account: "acct_a")
        app.hasActiveAppStoreSubscription = false
        let gate = StubURLProtocol.ResponseGate()
        StubURLProtocol.context.gate = gate
        server.answer(FakeVerifyServer.ownedElsewhere)
        let sending = Task { await app.syncAppleEntitlementToBackend(signedTransaction: "signed-1") }
        try await TestSupport.waitUntil { FakeVerifyServer.verifyRequests == 1 }
        XCTAssertEqual(app.appleEntitlementSync.state, .confirming)

        switchAccount(app, to: "acct_b")
        XCTAssertEqual(app.appleEntitlementSync.state, .idle, "the state resets with the account")
        gate.release()
        let state = await sending.value
        XCTAssertNil(state, "the answer belonged to acct_a")
        XCTAssertEqual(app.appleEntitlementSync.state, .idle)
        XCTAssertEqual(app.appleEntitlementNotice, .none, "acct_b is not shown acct_a's card")
        XCTAssertEqual(FakeVerifyServer.verifyRequests, 1, "nothing more is sent for the previous account")
    }

    func testTheCardGoesAwayWhenTheAccountChanges() async throws {
        let app = makeApp(account: "acct_a")
        server.answer(FakeVerifyServer.ownedElsewhere)
        _ = await app.syncAppleEntitlementToBackend(signedTransaction: "signed-1")
        XCTAssertEqual(app.appleEntitlementNotice, .ownedElsewhere)

        switchAccount(app, to: "acct_b")
        XCTAssertEqual(app.appleEntitlementSync.state, .idle)
        XCTAssertEqual(app.appleEntitlementNotice, .none)

        // The same transaction for the account signed in now is new work, and its answer is its own.
        server.answer(FakeVerifyServer.processed)
        server.usage(FakeVerifyServer.proUsage)
        let state = await app.syncAppleEntitlementToBackend(signedTransaction: "signed-1")
        XCTAssertEqual(state, .processed)
        XCTAssertEqual(server.transactions, ["signed-1", "signed-1"])
        XCTAssertTrue(app.isPro, "signed in to the owning account, the usage answer says Pro")
    }

    func testAFailedStateDoesNotOutliveASignOut() async {
        let app = makeApp()
        server.answer(FakeVerifyServer.serverError)
        _ = await app.syncAppleEntitlementToBackend(signedTransaction: "signed-1")
        XCTAssertEqual(app.appleEntitlementNotice, .failed)
        let auth = TestSupport.unenrolledAuthManager(session: session)
        app.clientAuthManager = auth
        app.minitiAPIService = MinitiAPIService(session: session, auth: auth)
        app.refreshClientAuthStatus()
        XCTAssertEqual(app.appleEntitlementSync.state, .idle)
        XCTAssertEqual(app.appleEntitlementNotice, .none)
    }

    // MARK: The card

    func testTheCardSaysExactlyWhatTheDesignGives() {
        XCTAssertEqual(SubscriptionElsewhereCard.title, "This App Store subscription belongs to another miniti account")
        XCTAssertEqual(SubscriptionElsewhereCard.message, "Sign in to that account to use Pro here. You can keep recording on the free plan.")
        XCTAssertEqual(SubscriptionElsewhereCard.emailAction, "Sign in with email")
        XCTAssertEqual(SubscriptionElsewhereCard.recoveryKeyAction, "Use recovery key")
        XCTAssertEqual(SubscriptionElsewhereCard.manageAction, "Manage subscription")
    }

    func testAPurchaseFailureMessageDoesNotRepeatTheNotice() async {
        let app = makeApp()
        XCTAssertEqual(app.appStorePurchaseFailureMessage(fallback: "Purchase not completed."), "Purchase not completed.")
        server.answer(FakeVerifyServer.ownedElsewhere)
        _ = await app.syncAppleEntitlementToBackend(signedTransaction: "signed-1")
        XCTAssertNil(app.appStorePurchaseFailureMessage(fallback: "Purchase not completed."))
        XCTAssertEqual(
            app.appStorePurchaseFailureMessage(fallback: "Purchase not completed.", noticeIsVisible: false),
            SubscriptionElsewhereCard.title,
            "where the card is not on screen, its title is the message"
        )
    }
}
#endif
