import SwiftUI
import SwiftData

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.startTime, order: .reverse) private var meetings: [Meeting]
    @State private var selectedTab: MobileTab = .record

    enum MobileTab: String {
        case record = "Record"
        case training = "Training"
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
                Tab("Training", systemImage: "chart.bar.fill", value: .training) {
                    TrainingMainView(meetings: meetings)
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

                TrainingMainView(meetings: meetings)
                    .tabItem {
                        Label("Training", systemImage: "chart.bar.fill")
                    }
                    .tag(MobileTab.training)

                HistoryView_iOS()
                    .tabItem {
                        Label("History", systemImage: "clock")
                    }
                    .tag(MobileTab.history)
            }
        }
    }
}
