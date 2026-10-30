import Foundation
import Combine

enum PurchaseConfirmationError: Error {
    case differentAccount
    case missing
    case throttled(TimeInterval)
    case unavailable
}

/// A return URL is only a request to check. This object never grants an entitlement,
/// restores a license, or changes account membership.
@MainActor
final class PurchaseReturnController: ObservableObject {
    enum State: Equatable {
        case idle, checking, ready
        case retry(String)
        case signIn

        var message: String? {
            switch self {
            case .idle: return nil
            case .checking: return "Confirming your purchase…"
            case .ready: return "Pro is ready"
            case .retry(let message): return message
            case .signIn: return "Sign in to the account you used to start this purchase, then try again."
            }
        }
    }

    @Published private(set) var state: State = .idle
    private(set) var checkoutID: UUID?
    private var worker: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var operation = UUID()
    var authority: () -> String? = { nil }
    var check: (UUID) async throws -> String = { _ in throw PurchaseConfirmationError.unavailable }
    var refreshEntitlement: (String) async throws -> Void = { _ in }
    var sleep: (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    var now: () -> Date = Date.init
    var maximumWait: TimeInterval = 30
    private var retryAfter: Date?

    nonisolated static func checkoutID(from url: URL) -> UUID? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "miniti-billing", parts.host == "return",
              parts.path.isEmpty || parts.path == "/", parts.user == nil, parts.password == nil,
              parts.port == nil, parts.fragment == nil,
              let items = parts.queryItems, items.count == 1, items[0].name == "checkout_id",
              let value = items[0].value else { return nil }
        return UUID(uuidString: value)
    }

    func receive(_ url: URL) {
        guard let id = Self.checkoutID(from: url) else { return }
        if checkoutID == id, state == .checking || state == .ready { return }
        if checkoutID != id { retryAfter = nil }
        checkoutID = id
        DiagnosticTimeline.shared.record(.purchaseReturned)
        retry()
    }

    func cancelForIdentityChange() {
        operation = UUID()
        worker?.cancel(); worker = nil
        timeout?.cancel(); timeout = nil
        if checkoutID != nil { state = .signIn }
    }

    func retry() {
        guard let id = checkoutID else { return }
        if let retryAfter, now() < retryAfter {
            state = .retry("Too many checks. Try again in \(Int(ceil(retryAfter.timeIntervalSince(now())))) seconds.")
            return
        }
        guard let owner = authority() else {
            DiagnosticTimeline.shared.record(.purchaseFailed, fields: ["outcome": "sign_in"])
            state = .signIn; return
        }
        worker?.cancel(); timeout?.cancel()
        let request = UUID(); operation = request
        state = .checking
        DiagnosticTimeline.shared.record(.purchaseChecking, fields: ["attempt_id": request.uuidString])
        let deadline = now().addingTimeInterval(maximumWait)
        timeout = Task { [weak self] in
            guard let self else { return }
            do { try await self.sleep(self.maximumWait) } catch { return }
            guard self.operation == request, self.state == .checking else { return }
            DiagnosticTimeline.shared.record(.purchasePending, fields: ["attempt_id": request.uuidString, "outcome": "timeout"])
            self.operation = UUID()
            self.worker?.cancel(); self.worker = nil
            self.state = .retry("Your purchase is still being confirmed. Try again shortly. You do not need to buy again.")
        }
        worker = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.operation == request { self.timeout?.cancel(); self.worker = nil }
            }
            do {
                while !Task.isCancelled, self.operation == request, self.now() < deadline {
                    guard self.authority() == owner else { self.cancelForIdentityChange(); return }
                    let result = try await self.check(id)
                    guard self.operation == request, !Task.isCancelled else { return }
                    guard self.authority() == owner else { self.cancelForIdentityChange(); return }
                    switch result {
                    case "ready":
                        try await self.refreshEntitlement(owner)
                        guard self.operation == request, !Task.isCancelled else { return }
                        guard self.authority() == owner else { self.cancelForIdentityChange(); return }
                        DiagnosticTimeline.shared.record(.purchaseReady, fields: ["attempt_id": request.uuidString])
                        self.state = .ready
                        return
                    case "expired", "failed":
                        DiagnosticTimeline.shared.record(.purchaseFailed, fields: ["attempt_id": request.uuidString, "outcome": result])
                        self.state = .retry("This checkout did not complete. If you were charged, use your receipt or contact support before buying again.")
                        return
                    case "pending":
                        DiagnosticTimeline.shared.record(.purchasePending, fields: ["attempt_id": request.uuidString])
                        try await self.sleep(2)
                    default: throw PurchaseConfirmationError.unavailable
                    }
                }
                if self.operation == request {
                    self.state = .retry("Your purchase is still being confirmed. Try again shortly. You do not need to buy again.")
                }
            } catch {
                guard self.operation == request, !Task.isCancelled else { return }
                guard self.authority() == owner else { self.cancelForIdentityChange(); return }
                DiagnosticTimeline.shared.record(.purchaseFailed, fields: DiagnosticTimeline.errorFields(error).merging(["attempt_id": request.uuidString]) { _, new in new })
                switch error {
                case PurchaseConfirmationError.differentAccount:
                    DiagnosticTimeline.shared.record(.purchaseFailed, fields: ["attempt_id": request.uuidString, "outcome": "sign_in"])
                    self.state = .signIn
                case PurchaseConfirmationError.missing:
                    self.state = .retry("This purchase return is unavailable on this installation. Use the license key in your receipt to restore Pro.")
                case PurchaseConfirmationError.throttled(let seconds):
                    DiagnosticTimeline.shared.record(.purchaseFailed, fields: ["attempt_id": request.uuidString, "outcome": "throttled"])
                    self.retryAfter = self.now().addingTimeInterval(max(1, seconds))
                    self.state = .retry("Too many checks. Wait \(Int(ceil(max(1, seconds)))) seconds, then try again.")
                default:
                    self.state = .retry("Could not confirm your purchase. Check your connection and try again. You do not need to buy again.")
                }
            }
        }
    }
}

extension AppState {
    /// Two generation reads make the account/generation pair coherent without exposing keys.
    var purchaseAuthority: String? {
        let generation = clientAuthManager.credentialGeneration
        guard appMode == .managed, let account = clientAuthManager.status.accountID,
              generation == clientAuthManager.credentialGeneration else { return nil }
        return "\(account):\(generation)"
    }

    func handlePurchaseReturn(_ url: URL) {
        guard PurchaseReturnController.checkoutID(from: url) != nil else { return }
        jumpToSetting("account.subscription")
        purchaseReturn.authority = { [weak self] in self?.purchaseAuthority }
        purchaseReturn.check = { [weak self] id in
            guard let api = self?.minitiAPIService else { throw PurchaseConfirmationError.unavailable }
            return try await api.purchaseStatus(checkoutID: id)
        }
        purchaseReturn.refreshEntitlement = { [weak self] owner in
            guard let self, self.purchaseAuthority == owner, let api = self.minitiAPIService else { throw PurchaseConfirmationError.differentAccount }
            let usage = try await api.checkUsage(deviceId: DeviceIdentifier.getOrCreateDeviceId())
            guard self.purchaseAuthority == owner else { throw PurchaseConfirmationError.differentAccount }
            self.usageInfo = usage
            self.applyAccountCloudFlag()
        }
        purchaseReturn.receive(url)
    }
}
