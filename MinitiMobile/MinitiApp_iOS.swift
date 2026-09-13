import SwiftUI
import SwiftData
import UIKit
import UserNotifications

@MainActor
private final class MobileAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var appState: AppState?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        AppState.registerSmartMeetingNotificationCategory()
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        let categoryIdentifier = response.notification.request.content.categoryIdentifier
        let eventID = response.notification.request.content.userInfo["eventID"] as? String
        Task { @MainActor [weak self] in
            self?.appState?.handleNotificationResponse(
                actionIdentifier: actionIdentifier,
                categoryIdentifier: categoryIdentifier,
                eventID: eventID
            )
        }
        completionHandler()
    }
}

@MainActor
private final class MeetingBackgroundSaveLease {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private var hasEnded = false

    static func begin() -> MeetingBackgroundSaveLease {
        let lease = MeetingBackgroundSaveLease()
        lease.identifier = UIApplication.shared.beginBackgroundTask(
            withName: "Persist meeting transcript"
        ) { [weak lease] in
            Task { @MainActor in
                DebugLogger.shared.log(.app, "Background save time expired")
                lease?.end()
            }
        }
        return lease
    }

    func end() {
        guard !hasEnded else { return }
        hasEnded = true
        if identifier != .invalid {
            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }
    }
}

@main
struct MinitiMobileApp: App {
    @UIApplicationDelegateAdaptor(MobileAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @AppStorage(InterfaceScale.storageKey) private var interfaceScaleRaw = InterfaceScale.standard.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var systemDynamicTypeSize

    private var interfaceScale: InterfaceScale {
        InterfaceScale(rawValue: interfaceScaleRaw) ?? .standard
    }
    
    /// Opened once at launch and again on "try again" from the recovery screen. The store is
    /// never deleted or recreated on failure (roadmap P0.2).
    @State private var storeState: PersistentStoreState = PersistentStore.open()

    private static let fallbackContainer: ModelContainer? = PersistentStore.makeInMemoryFallback()

    private var activeContainer: ModelContainer? {
        storeState.container ?? Self.fallbackContainer
    }

    private func retryStoreOpen() {
        let next = PersistentStore.open()
        storeState = next
        appState.notePersistentStore(next)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if case .failed(let failure, let readOnly) = storeState {
                    StoreRecoveryView(failure: failure, readOnlyContainer: readOnly, retry: retryStoreOpen)
                } else if appState.requiresForceUpdate {
                    ForceUpdateView()
                } else if !appState.hasAcceptedTerms {
                    TermsAcceptanceView()
                } else if appState.hasCompletedOnboarding {
                    MainTabView()
                        .persistenceIssueOverlay()
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(appState)
            .environment(\.interfaceScale, interfaceScale)
            .dynamicTypeSize(interfaceScale.dynamicTypeSize(from: systemDynamicTypeSize))
            .minitiReduceMotionAware()
            .preferredColorScheme(.dark)
            .onAppear {
                appDelegate.appState = appState
                appState.notePersistentStore(storeState)
                #if DEBUG
                ScreenshotMode.scheduleIOSReadyMarker()
                #endif
            }
            .onOpenURL { url in
                switch url.scheme?.lowercased() {
                case "miniti-google":
                    Task { @MainActor in
                        await appState.handleGoogleOAuthCallback(url)
                    }
                case "miniti" where url.host?.lowercased() == "meeting":
                    NotificationCenter.default.post(name: .minitiOpenActiveMeeting, object: nil)
                default:
                    break
                }
            }
            .modifier(OptionalModelContainer(container: activeContainer))
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                let saveLease = MeetingBackgroundSaveLease.begin()
                Task { @MainActor in
                    let didSave = await appState.saveCurrentMeetingAndWait()
                    if !didSave {
                        DebugLogger.shared.log(.app, "Background save did not reach SwiftData")
                    }
                    saveLease.end()
                }
            } else if newPhase == .active && appState.appMode == .managed {
                Task {
                    await appState.refreshUsage()
                    await appState.retryPendingSessionEndReports()
                }
            }
        }
    }
}
