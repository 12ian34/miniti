import SwiftUI
import SwiftData

extension Notification.Name {
    static let minitiOpenActiveMeeting = Notification.Name("minitiOpenActiveMeeting")
}

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Meeting.startTime, order: .reverse) private var meetings: [Meeting]
    @State private var selectedTab: MobileTab = .record
    @State private var coachingPath: [UUID] = []
    @StateObject private var coachingOverviewStore = CoachingOverviewStore()

    enum MobileTab: String, CaseIterable, Identifiable {
        case record = "Record"
        case training = "Coaching"
        case history = "History"

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .record: return "waveform"
            case .training: return "chart.bar.fill"
            case .history: return "clock"
            }
        }
    }

    var body: some View {
        tabContent
            .tint(ColorPalette.Accent.green)
            .onAppear {
                appState.modelContext = modelContext
                appState.resumeInterruptedMeeting()
                coachingOverviewStore.refreshIfNeeded(meetings: meetings)
            }
            .onChange(of: meetings.count) { _, _ in
                coachingOverviewStore.refreshIfNeeded(meetings: meetings)
            }
            .onChange(of: meetings.map(\.transcriptRevision)) { _, _ in
                coachingOverviewStore.refreshIfNeeded(meetings: meetings)
            }
            .onChange(of: appState.finalizingInsightMeetingIDs) { _, _ in
                coachingOverviewStore.refreshIfNeeded(meetings: meetings)
            }
            .onReceive(NotificationCenter.default.publisher(for: .minitiOpenActiveMeeting)) { _ in
                selectedTab = .record
            }
            .sheet(isPresented: $appState.showSettings) {
                SettingsView_iOS()
                    .preferredColorScheme(.dark)
            }
    }

    @ViewBuilder
    private var tabContent: some View {
        if #available(iOS 18.0, *) {
            if horizontalSizeClass == .regular {
                modernTabView
                    .tabViewStyle(.sidebarAdaptable)
            } else {
                modernTabView
                    .tabViewStyle(.tabBarOnly)
                    .defaultAdaptableTabBarPlacement(.tabBar)
            }
        } else if horizontalSizeClass == .regular {
            legacyRegularWidthNavigation
        } else {
            legacyCompactTabView
        }
    }

    @available(iOS 18.0, *)
    private var modernTabView: some View {
        TabView(selection: $selectedTab) {
            ForEach(MobileTab.allCases) { tab in
                Tab(tab.rawValue, systemImage: tab.systemImage, value: tab) {
                    content(for: tab)
                }
            }
        }
    }

    private var legacyCompactTabView: some View {
        TabView(selection: $selectedTab) {
            ForEach(MobileTab.allCases) { tab in
                content(for: tab)
                    .tabItem {
                        Label(tab.rawValue, systemImage: tab.systemImage)
                    }
                    .tag(tab)
            }
        }
    }

    private var legacyRegularWidthNavigation: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                Text("miniti")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ColorPalette.Text.primary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)

                List(MobileTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.rawValue, systemImage: tab.systemImage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedTab == tab ? ColorPalette.Accent.green : ColorPalette.Text.muted)
                    .listRowBackground(
                        selectedTab == tab
                            ? ColorPalette.Accent.green.opacity(0.12)
                            : Color.clear
                    )
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            content(for: selectedTab)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func content(for tab: MobileTab) -> some View {
        switch tab {
        case .record:
            MeetingView_iOS()
        case .training:
            NavigationStack(path: $coachingPath) {
                TrainingMainView(meetings: meetings, store: coachingOverviewStore) { meetingID in
                    coachingPath.append(meetingID)
                }
                .navigationDestination(for: UUID.self) { meetingID in
                    if let meeting = meetings.first(where: { $0.id == meetingID }) {
                        MeetingDetail_iOS(meeting: meeting, backLabel: "Coaching")
                    } else {
                        ContentUnavailableView("Meeting unavailable", systemImage: "clock.badge.questionmark")
                    }
                }
            }
        case .history:
            HistoryView_iOS()
        }
    }
}
