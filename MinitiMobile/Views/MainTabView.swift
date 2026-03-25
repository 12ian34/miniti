import SwiftUI
import SwiftData

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: MobileTab = .record

    enum MobileTab: String {
        case record = "Record"
        case history = "History"
    }

    var body: some View {
        tabContent
            .tint(ColorPalette.Accent.green)
            .onAppear {
                appState.modelContext = modelContext
                appState.resumeInterruptedMeeting()
            }
    }

    @ViewBuilder
    private var tabContent: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: $selectedTab) {
                Tab("Record", systemImage: "waveform", value: .record) {
                    MeetingView_iOS()
                }
                Tab("History", systemImage: "clock", value: .history) {
                    HistoryView_iOS()
                }
            }
            .tabViewStyle(.tabBarOnly)
            .defaultAdaptableTabBarPlacement(.tabBar)
        } else {
            TabView(selection: $selectedTab) {
                MeetingView_iOS()
                    .tabItem {
                        Label("Record", systemImage: "waveform")
                    }
                    .tag(MobileTab.record)

                HistoryView_iOS()
                    .tabItem {
                        Label("History", systemImage: "clock")
                    }
                    .tag(MobileTab.history)
            }
        }
    }
}
