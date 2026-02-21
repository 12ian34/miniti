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
        .tint(ColorPalette.Accent.green)
        .onAppear {
            appState.modelContext = modelContext
            appState.resumeInterruptedMeeting()
        }
    }
}
