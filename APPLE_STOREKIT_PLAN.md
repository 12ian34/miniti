# Apple StoreKit 2 Subscription for iOS

## Architecture

Two independent payment systems (Apple for iOS, Polar for macOS) both write to the same backend Redis device records. Cross-platform restore uses link codes.

**Key constraint**: macOS is a direct DMG distribution (not App Store), so it cannot use StoreKit. Cross-platform bridging requires a backend-generated "link code" that Apple subscribers can enter on macOS.

## App Store Connect Setup (manual, before coding)

1. Create a **subscription group** (e.g. "Miniti Pro")
2. Create an **auto-renewable subscription product**: `com.miniti.mobile.pro.monthly`, $4.99/month
3. Set **App Store Server Notifications v2** URL: `https://miniti-api.vercel.app/api/webhooks/apple`
4. Generate an **App Store Server API key** (Issuer ID + Key ID + .p8 file) for server-side transaction verification
5. Add these env vars to Vercel: `APPLE_ISSUER_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY` (contents of .p8)

## iOS App Changes

### StoreKit 2 Service (new file: `Shared/StoreKitService.swift`)

Shared service that handles StoreKit 2 on iOS (compiled out on macOS with `#if os(iOS)`):

- `@Published var proSubscription: Product?` -- the Pro product
- `@Published var purchaseState: PurchaseState` -- idle/purchasing/purchased/failed
- `@Published var isSubscribed: Bool` -- has active entitlement
- `init()`: load products via `Product.products(for: ["com.miniti.mobile.pro.monthly"])`
- `purchase()`: call `product.purchase()`, send JWS to backend on success
- `checkEntitlements()`: iterate `Transaction.currentEntitlements` to set `isSubscribed`
- `listenForUpdates()`: background `Task` listening to `Transaction.updates` for renewals/cancellations
- Send transaction to backend: `POST /api/apple/verify` with `{ transaction_id, original_transaction_id, jws_representation }`

### AppState Integration

In `Miniti/Models/AppState.swift`:

- Add `#if os(iOS)` property: `var storeKitService: StoreKitService?`
- On launch (iOS, managed mode): call `storeKitService.checkEntitlements()` -- if StoreKit says subscribed, no need to wait for backend
- After successful Apple purchase: call `verifyAppleTransaction()` on backend, then `refreshUsage()`
- `isPro` stays backend-driven (Redis is source of truth) but StoreKit entitlement check is an optimistic fast-path

### iOS UI Changes

In `MinitiMobile/Views/SettingsView_iOS.swift`:

- Add "Upgrade to Pro" button (only for free-tier managed users)
- Tapping triggers StoreKit 2 purchase flow (native Apple payment sheet)
- Show "Restore Purchase" button (calls `AppStore.sync()` to restore prior Apple purchases)
- If user has Apple subscription: show a "Link Code" they can use on macOS

In `MinitiMobile/Views/MeetingView_iOS.swift` / `Miniti/Views/UsageBanner.swift`:

- Show upgrade button on iOS (currently hidden behind `#if os(macOS)`)

In `Miniti/Views/LimitReachedView.swift`:

- Add Apple subscription purchase option alongside BYOK switch on iOS

### Xcode Project

- Add **StoreKit** capability to MinitiMobile target in Signing & Capabilities
- Add **In-App Purchase** capability
- Create `StoreKit.storekit` configuration file for Xcode testing (sandbox products)

## Backend Changes (miniti-api)

### New endpoint: `POST /api/apple/verify`

In `app/api/apple/verify/route.ts`:

- Receives `{ jws_representation, original_transaction_id }` + device headers
- Verifies the JWS signature using Apple's certificate chain (use `jose` npm library for JWS verification)
- Extracts transaction info: `productId`, `originalTransactionId`, `expiresDate`, `environment`
- Calls `linkDeviceToAppleSubscription(deviceId, originalTransactionId, expiresDate)` in usage.ts
- Generates a **link code** (random 8-char alphanumeric) and stores it: `apple_link:{code} -> { originalTransactionId, expiresAt }`
- Returns `{ success, tier, link_code }`

### New endpoint: `POST /api/webhooks/apple`

In `app/api/webhooks/apple/route.ts`:

- Receives App Store Server Notifications v2 (JWS signed payload)
- Verifies JWS signature (Apple's certificate chain)
- Handles notification types:
  - `SUBSCRIBED` / `DID_RENEW`: upgrade all devices linked to this `originalTransactionId`
  - `EXPIRED` / `REVOKE` / `DID_FAIL_TO_RENEW` + `GRACE_PERIOD_EXPIRED`: downgrade devices
- Uses `apple_sub:{originalTransactionId}:devices` Redis SET (same pattern as Polar's `polar_sub:{subId}:devices`)

### Extend restore endpoint: `POST /api/restore`

In `app/api/restore/route.ts`:

- Currently only accepts `license_key` (Polar)
- Add: if `license_key` matches the format of a link code (8-char alphanumeric), try looking up `apple_link:{code}` in Redis
- If found, verify the Apple subscription is still active (via stored transaction ID), then link device

### New fields in Redis device record

In `lib/usage.ts` `DeviceData`:

- `appleOriginalTransactionId: string | null`
- `appleSubscriptionStatus: string | null` (active/expired/billing_retry)
- `subscriptionSource: string | null` ("polar" | "apple" | null) -- know which system granted Pro

### New helper: `lib/apple.ts`

- `verifyJWS(signedPayload: string)`: decode and verify Apple's JWS using their certificate chain (use `jose` library)
- `extractTransactionInfo(jws)`: parse product ID, expiry, original transaction ID
- `linkDeviceToAppleSubscription(deviceId, originalTransactionId, periodEnd)`: similar to `linkDeviceToSubscription` but for Apple
- `downgradeAppleSubscriptionDevices(originalTransactionId, status)`: mirror of `downgradeSubscriptionDevices`
- `generateLinkCode()`: random 8-char code, stored in Redis with TTL

## Cross-Platform Flow

### iOS subscriber wants Pro on macOS:

1. Subscribe on iOS via StoreKit 2
2. Backend validates, upgrades device, generates link code
3. iOS Settings shows: "Your link code: ABCD1234"
4. On macOS: Settings -> Restore -> enter link code
5. Backend looks up code, verifies Apple sub is active, upgrades macOS device

### macOS (Polar) subscriber wants Pro on iOS:

1. Subscribe on macOS via Polar checkout (already works)
2. Gets Polar license key from email/portal
3. On iOS: Settings -> Restore with License Key -> enter key
4. Backend validates via Polar API, upgrades iOS device (already works)

## Dependencies

- `jose` npm package for JWS verification (Apple's signed payloads)
- No iOS third-party dependencies (StoreKit 2 is a system framework)

## Billing Cycle Alignment

- Apple manages the billing cycle for Apple subscribers
- Backend extracts `expiresDate` from the transaction and uses it as `resetDate` (same pattern as Polar's `current_period_end`)
- On renewal webhook, minutes reset and `resetDate` advances

## Testing

- Use Xcode StoreKit sandbox for local testing (no real charges)
- App Store Connect sandbox accounts for end-to-end testing
- Test: purchase, renewal, cancellation, expiry, restore, cross-platform link code

## Pricing

- $4.99/month on iOS (same as macOS Polar price)
- Apple takes 15% (Small Business Program) = ~$0.75/transaction
- Net revenue per iOS subscriber: ~$4.24/month vs ~$4.72/month on macOS (Polar at 4% + 40c)
