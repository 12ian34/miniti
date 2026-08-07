import SwiftUI
import SwiftData

@main
struct MinitiMobileApp: App {
    @StateObject private var appState = AppState()
    @AppStorage(InterfaceScale.storageKey) private var interfaceScaleRaw = InterfaceScale.standard.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var systemDynamicTypeSize

    private var interfaceScale: InterfaceScale {
        InterfaceScale(rawValue: interfaceScaleRaw) ?? .standard
    }
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Meeting.self,
            TranscriptSegment.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            Group {
                if appState.requiresForceUpdate {
                    ForceUpdateView()
                } else if !appState.hasAcceptedTerms {
                    TermsAcceptanceView()
                } else if appState.hasCompletedOnboarding {
                    MainTabView()
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(appState)
            .environment(\.interfaceScale, interfaceScale)
            .dynamicTypeSize(interfaceScale.dynamicTypeSize(from: systemDynamicTypeSize))
            .minitiReduceMotionAware()
            .preferredColorScheme(.dark)
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
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                appState.saveCurrentMeetingIfNeeded()
            } else if newPhase == .active && appState.appMode == .managed {
                Task {
                    await appState.refreshUsage()
                    await appState.retryPendingSessionEndReports()
                }
            }
        }
    }
}
