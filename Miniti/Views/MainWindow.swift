import SwiftUI
import SwiftData
import AppKit
import Combine

// MARK: - Theme (using ColorPalette)
/// Theme struct provides convenient access to the global color palette.
/// All colors reference ColorPalette for consistency.
struct Theme {
    // Backgrounds
    static let bg = ColorPalette.Background.primary
    static let bgSecondary = ColorPalette.Background.secondary
    static let bgTertiary = ColorPalette.Background.tertiary
    
    // Borders
    static let border = ColorPalette.Border.primary
    static let borderLight = ColorPalette.Border.light
    
    // Text
    static let text = ColorPalette.Text.primary
    static let textMuted = ColorPalette.Text.muted
    static let textDim = ColorPalette.Text.dim
    
    // Accents
    static let accent = ColorPalette.Accent.green
    static let accentRed = ColorPalette.Accent.red
    static let accentBlue = ColorPalette.Accent.blue
}

enum MainNavigationDestination: Equatable {
    case home
    case coaching
    case meeting(UUID)
}

struct MainNavigationHistory: Equatable {
    private(set) var current: MainNavigationDestination
    private(set) var backStack: [MainNavigationDestination] = []
    private(set) var forwardStack: [MainNavigationDestination] = []

    mutating func visit(_ destination: MainNavigationDestination) {
        guard destination != current else { return }
        backStack.append(current)
        current = destination
        forwardStack.removeAll()
    }

    mutating func goBack() -> MainNavigationDestination? {
        guard let destination = backStack.popLast() else { return nil }
        forwardStack.append(current)
        current = destination
        return destination
    }

    mutating func goForward() -> MainNavigationDestination? {
        guard let destination = forwardStack.popLast() else { return nil }
        backStack.append(current)
        current = destination
        return destination
    }

    mutating func retainMeetings(_ availableMeetingIDs: Set<UUID>) {
        backStack.removeAll { $0.referencesMissingMeeting(in: availableMeetingIDs) }
        forwardStack.removeAll { $0.referencesMissingMeeting(in: availableMeetingIDs) }
        if current.referencesMissingMeeting(in: availableMeetingIDs) {
            current = .home
        }
    }
}

struct MainWindowNavigationSwipePolicy {
    private static let presentationDominanceRatio: CGFloat = 1.15
    private static let minimumPresentationTravel: CGFloat = 6

    static func presentationProgress(horizontal: CGFloat, vertical: CGFloat) -> CGFloat? {
        let horizontalTravel = abs(horizontal)
        let verticalTravel = abs(vertical)
        guard horizontalTravel >= minimumPresentationTravel,
              horizontalTravel > verticalTravel * presentationDominanceRatio else { return nil }
        let distanceProgress = horizontalTravel / MinitiDesignSystem.NavigationGesture.commitDistance
        let dominanceDistance = max(
            verticalTravel * MinitiDesignSystem.NavigationGesture.horizontalDominanceRatio,
            1
        )
        let dominanceProgress = horizontalTravel / dominanceDistance
        let readiness = min(distanceProgress, dominanceProgress)
        let signedReadiness = horizontal < 0 ? -readiness : readiness
        return min(max(signedReadiness, -1.12), 1.12)
    }

    static func shouldCommit(horizontal: CGFloat, vertical: CGFloat) -> Bool {
        let horizontalTravel = abs(horizontal)
        let verticalTravel = abs(vertical)
        return horizontalTravel >= MinitiDesignSystem.NavigationGesture.commitDistance
            && horizontalTravel >= verticalTravel * MinitiDesignSystem.NavigationGesture.horizontalDominanceRatio
    }

    static func allowsGestureWhileEditing(
        isEditingText: Bool,
        isMeetingSearchFocused: Bool
    ) -> Bool {
        !isEditingText || isMeetingSearchFocused
    }
}

private extension MainNavigationDestination {
    func referencesMissingMeeting(in availableMeetingIDs: Set<UUID>) -> Bool {
        guard case .meeting(let id) = self else { return false }
        return !availableMeetingIDs.contains(id)
    }
}

struct MainWindow: View {
    private static let historySearchDebounceNanoseconds: UInt64 = 200_000_000
    private static let expandedSidebarMinimumWindowWidth: CGFloat = 940

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var keyboardService: KeyboardShortcutsService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var meetings: [Meeting] = []
    @State private var selectedMeetingID: UUID?
    @AppStorage("mainWindow.sidebarCollapsed") private var sidebarCollapsed = false
    @AppStorage("mainWindow.historyCollapsed") private var historyCollapsed = true
    @State private var didInitialize = false
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var isSearchActive = false
    @State private var searchFocusRequest = 0
    @State private var searchBlurRequest = 0
    @State private var isMeetingSearchFocused = false
    @State private var showTraining = false
    @State private var coachingOriginMeetingID: UUID?
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var navigationHistory = MainNavigationHistory(current: .home)
    @State private var isApplyingNavigationHistory = false
    @State private var navigationSwipeProgress: CGFloat = 0
    @State private var isCompactSidebarMode = false
    @State private var isCompactSidebarPresented = false
    @StateObject private var coachingOverviewStore = CoachingOverviewStore()

    private var selectedMeeting: Meeting? {
        guard let selectedMeetingID else { return nil }
        return meetings.first(where: { $0.id == selectedMeetingID })
    }

    private var currentNavigationDestination: MainNavigationDestination {
        if let selectedMeetingID { return .meeting(selectedMeetingID) }
        if showTraining { return .coaching }
        return .home
    }

    private var canNavigateBack: Bool { !navigationHistory.backStack.isEmpty }
    private var canNavigateForward: Bool { !navigationHistory.forwardStack.isEmpty }

    private var historicalMeetings: [Meeting] {
        meetings
            .filter { $0.id != appState.currentMeeting?.id }
            .sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return $0.startTime > $1.startTime
            }
    }

    private var searchResults: [MeetingSearchResult] {
        guard isSearchActive, !debouncedSearchText.isEmpty else { return [] }
        return MeetingSearchResult.search(query: debouncedSearchText, in: historicalMeetings)
    }

    private var displayedMeetings: [Meeting] {
        if isSearchActive && !debouncedSearchText.isEmpty {
            return searchResults.map(\.meeting)
        }
        return historicalMeetings
    }

    private var searchSnippets: [UUID: String] {
        var dict: [UUID: String] = [:]
        for result in searchResults {
            if let snippet = result.snippet {
                dict[result.meeting.id] = snippet
            }
        }
        return dict
    }

    private var searchMatchCounts: [UUID: Int] {
        var dict: [UUID: Int] = [:]
        for result in searchResults {
            dict[result.meeting.id] = result.matchCount
        }
        return dict
    }
    
    var body: some View {
        GeometryReader { geometry in
            let usesCompactSidebar = geometry.size.width < Self.expandedSidebarMinimumWindowWidth
            let sidebarIsEffectivelyCollapsed = usesCompactSidebar || sidebarCollapsed

            ZStack {
                HStack(spacing: 0) {
                    // Sidebar
                    terminalSidebar(
                        isCollapsed: Binding(
                            get: { sidebarIsEffectivelyCollapsed },
                            set: { newValue in
                                if usesCompactSidebar {
                                    if !newValue { isCompactSidebarPresented = true }
                                } else {
                                    sidebarCollapsed = newValue
                                }
                            }
                        ),
                        closesAfterNavigation: false
                    )
                    .frame(width: sidebarIsEffectivelyCollapsed ? 52 : 220)
                    .animation(.easeInOut(duration: 0.2), value: sidebarIsEffectivelyCollapsed)

                    // Subtle gradient divider
                    ZStack {
                        Rectangle()
                            .fill(Theme.border)
                            .frame(width: 1)

                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [Theme.border.opacity(0), Theme.borderLight.opacity(0.5), Theme.border.opacity(0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 1)
                    }

                    // Main content
                    if let meeting = selectedMeeting {
                        MeetingDetailView(
                            meeting: meeting,
                            showsBackToCoaching: coachingOriginMeetingID == meeting.id,
                            onBackToCoaching: backToCoaching
                        )
                        .id(meeting.id)
                    } else if showTraining {
                        TrainingMainView(meetings: meetings, store: coachingOverviewStore) { meetingID in
                            coachingOriginMeetingID = meetingID
                            selectedMeetingID = meetingID
                        }
                    } else {
                        MeetingView(meetings: meetings)
                    }
                }

                // Keyboard shortcuts help overlay
                if keyboardService.showingHelp {
                    KeyboardShortcutsOverlay()
                }

                if abs(navigationSwipeProgress) > 0.01 {
                    MainWindowNavigationSwipeCue(signedProgress: navigationSwipeProgress)
                        .allowsHitTesting(false)
                        .zIndex(10)
                }

                if usesCompactSidebar && isCompactSidebarPresented {
                    Button {
                        isCompactSidebarPresented = false
                    } label: {
                        Color.black.opacity(0.32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("close navigation sidebar")
                    .zIndex(20)

                    HStack(spacing: 0) {
                        terminalSidebar(
                            isCollapsed: Binding(
                                get: { false },
                                set: { newValue in
                                    if newValue { isCompactSidebarPresented = false }
                                }
                            ),
                            closesAfterNavigation: true
                        )
                        .frame(width: 220)
                        .shadow(color: .black.opacity(0.45), radius: 18, x: 8)

                        Spacer(minLength: 0)
                    }
                    .transition(
                        reduceMotion
                            ? .identity
                            : .move(edge: .leading).combined(with: .opacity)
                    )
                    .zIndex(21)
                }
            }
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.18),
                value: isCompactSidebarPresented
            )
            .onAppear {
                isCompactSidebarMode = usesCompactSidebar
            }
            .onChange(of: usesCompactSidebar) { _, isCompact in
                isCompactSidebarMode = isCompact
                if !isCompact { isCompactSidebarPresented = false }
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(Theme.bg)
        .background(
            MainWindowNavigationSwipeObserver(
                canGoBack: canNavigateBack,
                canGoForward: canNavigateForward,
                isMeetingSearchFocused: isMeetingSearchFocused,
                onProgress: updateNavigationSwipeProgress,
                onBack: navigateBack,
                onForward: navigateForward
            )
        )
        .onAppear {
            initializeIfNeeded()
            refreshMeetings()
            selectPendingSavedMeetingIfNeeded()
            debouncedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .onChange(of: appState.currentMeeting) { oldMeeting, newMeeting in
            // When starting a new meeting, deselect historical meeting
            if newMeeting != nil {
                selectedMeetingID = nil
            } else if oldMeeting != nil {
                // Leaving a session (save, discard, or Home) restores full navigation.
                sidebarCollapsed = false
            }
            isCompactSidebarPresented = false
            refreshMeetings()
        }
        .onChange(of: appState.isRecording) { _, isRecording in
            // Collapse once when recording begins. A manual reopen remains respected
            // until recording is resumed or a new recording starts.
            if isRecording {
                sidebarCollapsed = true
                isCompactSidebarPresented = false
            }
        }
        .onChange(of: appState.pendingOpenSavedMeetingID) { _, _ in
            refreshMeetings()
            selectPendingSavedMeetingIfNeeded()
        }
        .onChange(of: appState.finalizingInsightMeetingIDs) { _, _ in
            coachingOverviewStore.refreshIfNeeded(meetings: meetings)
        }
        .onChange(of: meetings.map(\.id)) { _, _ in
            selectPendingSavedMeetingIfNeeded()
        }
        .onChange(of: selectedMeetingID) { _, newValue in
            dismissMeetingSearchFocus()
            isCompactSidebarPresented = false
            if newValue != coachingOriginMeetingID {
                coachingOriginMeetingID = nil
            }
            recordNavigationDestinationChange()
        }
        .onChange(of: showTraining) { _, _ in
            dismissMeetingSearchFocus()
            isCompactSidebarPresented = false
            recordNavigationDestinationChange()
        }
        .onChange(of: searchText) { _, newValue in
            scheduleSearchDebounce(for: newValue)
        }
        .onChange(of: isSearchActive) { _, active in
            if active {
                scheduleSearchDebounce(for: searchText)
            } else {
                searchDebounceTask?.cancel()
                debouncedSearchText = ""
            }
        }
        .onDisappear {
            searchDebounceTask?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .minitiGoogleOAuthCallback)) { notification in
            guard let callbackURL = notification.userInfo?["url"] as? URL else { return }
            Task { @MainActor in
                await appState.handleGoogleOAuthCallback(callbackURL)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshMeetings()
            if appState.appMode == .managed {
                Task { await appState.refreshUsage() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .minitiMeetingsImported)) { _ in
            // Settings-window imports (Granola CSV) insert meetings without any of the
            // main window's refresh triggers firing — the app never resigns active.
            refreshMeetings()
        }
    }

    private func terminalSidebar(
        isCollapsed: Binding<Bool>,
        closesAfterNavigation: Bool
    ) -> some View {
        TerminalSidebar(
            meetings: meetings,
            displayedMeetings: displayedMeetings,
            selectedMeetingID: Binding(
                get: { selectedMeetingID },
                set: { newValue in
                    selectedMeetingID = newValue
                    if closesAfterNavigation { isCompactSidebarPresented = false }
                }
            ),
            isCollapsed: isCollapsed,
            isSearchActive: $isSearchActive,
            searchText: $searchText,
            showTraining: Binding(
                get: { showTraining },
                set: { newValue in
                    showTraining = newValue
                    if closesAfterNavigation { isCompactSidebarPresented = false }
                }
            ),
            historyCollapsed: $historyCollapsed,
            searchFocusRequest: searchFocusRequest,
            searchBlurRequest: searchBlurRequest,
            searchSnippets: searchSnippets,
            searchMatchCounts: searchMatchCounts,
            onSearchFocusChange: { focused in
                isMeetingSearchFocused = focused
            },
            onDeleteMeeting: { meeting in
                deleteMeeting(meeting)
            },
            onTogglePin: { meeting in
                meeting.isPinned.toggle()
                try? modelContext.save()
                refreshMeetings()
            }
        )
    }

    private func initializeIfNeeded() {
        guard !didInitialize else { return }
        didInitialize = true
        appState.modelContext = modelContext
        appState.resumeInterruptedMeeting()
        navigationHistory = MainNavigationHistory(current: currentNavigationDestination)
        setupNavigationHandlers()
    }
    
    private func setupNavigationHandlers() {
        keyboardService.onNewSession = { [self] in
            appState.createNewSession()
            showTraining = false
            selectedMeetingID = nil
        }

        keyboardService.onNavigateUp = { [self] in
            navigateHistory(direction: -1)
        }
        
        keyboardService.onNavigateDown = { [self] in
            navigateHistory(direction: 1)
        }

        keyboardService.onToggleSidebarCollapse = { [self] in
            if isCompactSidebarMode {
                isCompactSidebarPresented.toggle()
            } else {
                sidebarCollapsed.toggle()
            }
        }

        keyboardService.onFocusSearch = { [self] in
            if isCompactSidebarMode {
                isCompactSidebarPresented = true
            } else {
                sidebarCollapsed = false
            }
            historyCollapsed = false
            isSearchActive = true
            searchFocusRequest += 1
        }

        keyboardService.onDismissSearch = { [self] in
            guard isSearchActive else { return false }
            isSearchActive = false
            searchText = ""
            return true
        }

        keyboardService.onToggleInsightsCollapse = { [self] in
            withAnimation(.easeInOut(duration: 0.16)) {
                appState.isLiveInsightsCollapsed.toggle()
            }
        }
        
    }
    
    private func navigateHistory(direction: Int) {
        let navMeetings = displayedMeetings
        guard !navMeetings.isEmpty else { return }

        if let selectedMeetingID,
           let currentIndex = navMeetings.firstIndex(where: { $0.id == selectedMeetingID }) {
            let newIndex = currentIndex + direction
            if newIndex >= 0 && newIndex < navMeetings.count {
                self.selectedMeetingID = navMeetings[newIndex].id
            }
        } else {
            if direction > 0 {
                selectedMeetingID = navMeetings.first?.id
            } else {
                selectedMeetingID = navMeetings.last?.id
            }
        }
    }

    private func recordNavigationDestinationChange() {
        guard !isApplyingNavigationHistory else { return }
        navigationHistory.visit(currentNavigationDestination)
    }

    private func navigateBack() {
        guard let destination = navigationHistory.goBack() else { return }
        dismissMeetingSearchFocus()
        applyNavigationDestination(destination)
    }

    private func navigateForward() {
        guard let destination = navigationHistory.goForward() else { return }
        dismissMeetingSearchFocus()
        applyNavigationDestination(destination)
    }

    private func dismissMeetingSearchFocus() {
        guard isMeetingSearchFocused else { return }
        isMeetingSearchFocused = false
        searchBlurRequest += 1
    }

    private func updateNavigationSwipeProgress(_ progress: CGFloat) {
        if progress == 0, !reduceMotion {
            withAnimation(.easeOut(duration: MinitiDesignSystem.Motion.navigationCueDismissDuration)) {
                navigationSwipeProgress = 0
            }
        } else {
            navigationSwipeProgress = progress
        }
    }

    private func applyNavigationDestination(_ destination: MainNavigationDestination) {
        if case .meeting(let id) = destination,
           !meetings.contains(where: { $0.id == id }) {
            navigationHistory.retainMeetings(Set(meetings.map(\.id)))
            return
        }

        isApplyingNavigationHistory = true
        coachingOriginMeetingID = nil

        switch destination {
        case .home:
            showTraining = false
            selectedMeetingID = nil
        case .coaching:
            selectedMeetingID = nil
            showTraining = true
        case .meeting(let id):
            showTraining = false
            selectedMeetingID = id
        }

        DispatchQueue.main.async {
            isApplyingNavigationHistory = false
        }
    }

    private func backToCoaching() {
        if navigationHistory.backStack.last == .coaching {
            navigateBack()
            return
        }
        coachingOriginMeetingID = nil
        selectedMeetingID = nil
        showTraining = true
    }
    
    private func deleteMeeting(_ meeting: Meeting) {
        // Deselect if this was selected
        if selectedMeetingID == meeting.id {
            selectedMeetingID = nil
        }
        // Delete from context
        appState.noteMeetingDeleted(meeting)
        modelContext.delete(meeting)
        try? modelContext.save()
        refreshMeetings()
    }

    private func selectPendingSavedMeetingIfNeeded() {
        guard let pendingID = appState.pendingOpenSavedMeetingID else { return }
        guard let meeting = meetings.first(where: { $0.id == pendingID }) else { return }
        showTraining = false
        selectedMeetingID = meeting.id
        appState.pendingOpenSavedMeetingID = nil
    }

    private func refreshMeetings() {
        let descriptor = FetchDescriptor<Meeting>()
        guard let fetched = try? modelContext.fetch(descriptor) else { return }
        meetings = fetched.sorted { $0.startTime > $1.startTime }
        coachingOverviewStore.refreshIfNeeded(meetings: meetings)
        navigationHistory.retainMeetings(Set(fetched.map(\.id)))

        if let selectedMeetingID, !fetched.contains(where: { $0.id == selectedMeetingID }) {
            self.selectedMeetingID = nil
        }
    }

    private func scheduleSearchDebounce(for query: String) {
        searchDebounceTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSearchActive, !trimmed.isEmpty else {
            debouncedSearchText = ""
            return
        }

        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.historySearchDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            guard isSearchActive else { return }
            debouncedSearchText = trimmed
        }
    }
}

private struct MainWindowNavigationSwipeObserver: NSViewRepresentable {
    let canGoBack: Bool
    let canGoForward: Bool
    let isMeetingSearchFocused: Bool
    let onProgress: (CGFloat) -> Void
    let onBack: () -> Void
    let onForward: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = SwipePassthroughView()
        view.canGoBack = canGoBack
        view.canGoForward = canGoForward
        view.isMeetingSearchFocused = isMeetingSearchFocused
        view.onProgress = onProgress
        view.onBack = onBack
        view.onForward = onForward
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? SwipePassthroughView else { return }
        view.canGoBack = canGoBack
        view.canGoForward = canGoForward
        view.isMeetingSearchFocused = isMeetingSearchFocused
        view.onProgress = onProgress
        view.onBack = onBack
        view.onForward = onForward
    }

    private final class SwipePassthroughView: NSView {
        var canGoBack = false
        var canGoForward = false
        var isMeetingSearchFocused = false
        var onProgress: ((CGFloat) -> Void)?
        var onBack: (() -> Void)?
        var onForward: (() -> Void)?

        private var scrollEventMonitor: Any?
        private var accumulatedX: CGFloat = 0
        private var accumulatedY: CGFloat = 0
        private var isTrackingGesture = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard scrollEventMonitor == nil, window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                self?.installScrollEventMonitor()
            }
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil {
                removeScrollEventMonitor()
            }
            super.viewWillMove(toWindow: newWindow)
        }

        override func removeFromSuperview() {
            removeScrollEventMonitor()
            super.removeFromSuperview()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private func installScrollEventMonitor() {
            guard scrollEventMonitor == nil else { return }
            scrollEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                handleScrollEvent(event)
                return event
            }
        }

        private func handleScrollEvent(_ event: NSEvent) {
            let isEditingText = isEditingText(in: event.window)
            guard event.window?.attachedSheet == nil,
                  event.window?.sheetParent == nil,
                  event.hasPreciseScrollingDeltas,
                  event.momentumPhase.isEmpty,
                  !event.phase.isEmpty,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                  MainWindowNavigationSwipePolicy.allowsGestureWhileEditing(
                      isEditingText: isEditingText,
                      isMeetingSearchFocused: isMeetingSearchFocused
                  ) else {
                resetGesture()
                return
            }

            if event.phase.contains(.mayBegin) || event.phase.contains(.began) {
                resetGesture()
                isTrackingGesture = true
            }

            if isTrackingGesture &&
               (event.phase.contains(.began) || event.phase.contains(.changed)) {
                // Normalize natural/reversed scrolling so physical swipe direction
                // remains stable: right goes back and left goes forward.
                let deviceDirection: CGFloat = event.isDirectionInvertedFromDevice ? -1 : 1
                accumulatedX += event.scrollingDeltaX * deviceDirection
                accumulatedY += event.scrollingDeltaY * deviceDirection
                presentGestureProgress()
            }

            if event.phase.contains(.cancelled) {
                resetGesture()
            } else if event.phase.contains(.ended) {
                finishGesture()
            }
        }

        private func finishGesture() {
            defer { resetGesture() }
            guard MainWindowNavigationSwipePolicy.shouldCommit(
                horizontal: accumulatedX,
                vertical: accumulatedY
            ) else { return }

            if accumulatedX < 0 {
                guard canGoBack else { return }
                onBack?()
            } else {
                guard canGoForward else { return }
                onForward?()
            }
        }

        private func presentGestureProgress() {
            guard let progress = MainWindowNavigationSwipePolicy.presentationProgress(
                horizontal: accumulatedX,
                vertical: accumulatedY
            ) else {
                onProgress?(0)
                return
            }

            let isAvailable = progress < 0 ? canGoBack : canGoForward
            onProgress?(isAvailable ? progress : 0)
        }

        private func resetGesture() {
            accumulatedX = 0
            accumulatedY = 0
            isTrackingGesture = false
            onProgress?(0)
        }

        private func isEditingText(in window: NSWindow?) -> Bool {
            guard let textView = window?.firstResponder as? NSTextView else { return false }
            return textView.isEditable || textView.isFieldEditor
        }

        private func removeScrollEventMonitor() {
            if let scrollEventMonitor {
                NSEvent.removeMonitor(scrollEventMonitor)
                self.scrollEventMonitor = nil
            }
            resetGesture()
        }
    }
}

private struct MainWindowNavigationSwipeCue: View {
    let signedProgress: CGFloat

    private var isBack: Bool { signedProgress < 0 }
    private var progress: CGFloat { min(abs(signedProgress), 1) }
    private var opacity: Double {
        Double(min(max((progress - 0.06) / 0.24, 0), 1))
    }
    private var horizontalOffset: CGFloat {
        let remainingTravel = MinitiDesignSystem.NavigationGesture.cueTravel * (1 - progress)
        return isBack ? -remainingTravel : remainingTravel
    }

    var body: some View {
        HStack(spacing: 0) {
            if !isBack { Spacer(minLength: 0) }

            ZStack {
                Circle()
                    .fill(ColorPalette.Background.card)
                    .overlay(
                        Circle()
                            .stroke(ColorPalette.Border.light, lineWidth: 1)
                    )

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        progress >= 1 ? ColorPalette.Text.primary : ColorPalette.Text.muted,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Image(systemName: isBack ? "arrow.left" : "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(progress >= 1 ? ColorPalette.Text.primary : ColorPalette.Text.muted)
            }
            .frame(
                width: MinitiDesignSystem.NavigationGesture.cueDiameter,
                height: MinitiDesignSystem.NavigationGesture.cueDiameter
            )
            .scaleEffect(0.84 + (0.16 * progress))
            .offset(x: horizontalOffset)
            .opacity(opacity)

            if isBack { Spacer(minLength: 0) }
        }
        .padding(.horizontal, MinitiDesignSystem.NavigationGesture.cueEdgeInset)
        .accessibilityHidden(true)
    }
}

struct TerminalSidebar: View {
    @EnvironmentObject var appState: AppState
    let meetings: [Meeting]
    let displayedMeetings: [Meeting]
    @Binding var selectedMeetingID: UUID?
    @Binding var isCollapsed: Bool
    @Binding var isSearchActive: Bool
    @Binding var searchText: String
    @Binding var showTraining: Bool
    @Binding var historyCollapsed: Bool
    var searchFocusRequest: Int = 0
    var searchBlurRequest: Int = 0
    let searchSnippets: [UUID: String]
    let searchMatchCounts: [UUID: Int]
    let onSearchFocusChange: (Bool) -> Void
    let onDeleteMeeting: (Meeting) -> Void
    let onTogglePin: (Meeting) -> Void
    @State private var collapsedStatusPulse = false
    @State private var searchFocusGeneration = 0
    @FocusState private var searchFieldFocused: Bool

    private var historicalMeetings: [Meeting] {
        meetings.filter { $0.id != appState.currentMeeting?.id }
    }

    private var historySections: [(title: String, meetings: [Meeting])] {
        if isSearchActive && !searchText.isEmpty {
            return [("results", displayedMeetings)]
        }
        let calendar = Calendar.current
        let pinned = displayedMeetings.filter(\.isPinned)
        let unpinned = displayedMeetings.filter { !$0.isPinned }
        var result: [(String, [Meeting])] = []
        if !pinned.isEmpty { result.append(("pinned", pinned)) }
        let today = unpinned.filter { calendar.isDateInToday($0.startTime) }
        let yesterday = unpinned.filter { calendar.isDateInYesterday($0.startTime) }
        let week = unpinned.filter {
            !calendar.isDateInToday($0.startTime) &&
            !calendar.isDateInYesterday($0.startTime) &&
            calendar.isDate($0.startTime, equalTo: Date(), toGranularity: .weekOfYear)
        }
        let used = Set((today + yesterday + week).map(\.id))
        let older = unpinned.filter { !used.contains($0.id) }
        if !today.isEmpty { result.append(("today", today)) }
        if !yesterday.isEmpty { result.append(("yesterday", yesterday)) }
        if !week.isEmpty { result.append(("this week", week)) }
        if !older.isEmpty { result.append(("older", older)) }
        return result
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            expandedSidebar
                .frame(width: 220)
                .opacity(isCollapsed ? 0 : 1)

            collapsedSidebar
                .frame(maxWidth: .infinity)
                .opacity(isCollapsed ? 1 : 0)
        }
        .clipped()
    }
    
    private var collapsedSidebar: some View {
        VStack(alignment: .center, spacing: 0) {
            // Logo
            Text("⬢")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .padding(.vertical, 18)

            GradientDivider()

            VStack(spacing: 4) {
                // Home
                collapsedNavButton(
                    icon: appState.currentMeeting != nil ? "record.circle" : "house.fill",
                    color: appState.currentMeeting != nil ? (appState.isRecording ? Theme.accentRed : Theme.accentBlue) : Theme.accent,
                    isSelected: selectedMeetingID == nil && !showTraining
                ) {
                    showTraining = false
                    selectedMeetingID = nil
                }

                // Coaching
                collapsedNavButton(
                    icon: "chart.bar.fill",
                    color: ColorPalette.Text.primary,
                    isSelected: showTraining && selectedMeetingID == nil
                ) {
                    showTraining = true
                    selectedMeetingID = nil
                }

                // History
                if !historicalMeetings.isEmpty {
                    collapsedNavButton(
                        icon: "clock.fill",
                        color: Theme.textMuted,
                        isSelected: selectedMeetingID != nil
                    ) {
                        historyCollapsed = false
                        isCollapsed = false
                    }
                }
            }
            .padding(.top, 10)

            Spacer()

            VStack(spacing: 0) {
                GradientDivider()

                Button {
                    isCollapsed = false
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textDim)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Theme.bgTertiary)
                        )
                }
                .buttonStyle(.plain)
                .focusable(false)
                .padding(.vertical, 14)
            }
        }
        .background(Theme.bgSecondary)
        .onAppear {
            updateCollapsedStatusPulse()
        }
        .onChange(of: appState.isRecording) { _, _ in
            updateCollapsedStatusPulse()
        }
        .onChange(of: appState.currentMeeting?.id) { _, _ in
            updateCollapsedStatusPulse()
        }
    }
    
    private var expandedSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Logo/Title
            HStack(spacing: 10) {
                Button {
                    selectedMeetingID = nil
                } label: {
                    HStack(spacing: 10) {
                        Text("⬢")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                        Text("miniti")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.text)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            
            // Gradient divider
            GradientDivider()
            
            // Navigation items
            VStack(alignment: .leading, spacing: 4) {
                if let meeting = appState.currentMeeting {
                    SidebarSessionItem(
                        title: meeting.displayTitle,
                        isRecording: appState.isRecording,
                        isSelected: selectedMeetingID == nil && !showTraining
                    ) {
                        showTraining = false
                        selectedMeetingID = nil
                    }
                } else {
                    SidebarIconItem(
                        systemIcon: "house.fill",
                        label: "home",
                        isSelected: selectedMeetingID == nil && !showTraining,
                        shortcut: "⌘N"
                    ) {
                        showTraining = false
                        selectedMeetingID = nil
                    }
                }

                SidebarIconItem(
                    systemIcon: "chart.bar.fill",
                    label: "coaching",
                    isSelected: showTraining && selectedMeetingID == nil
                ) {
                    showTraining = true
                    selectedMeetingID = nil
                }

                if !historicalMeetings.isEmpty {
                    SidebarIconItem(
                        systemIcon: "clock.fill",
                        label: "history",
                        isSelected: selectedMeetingID != nil,
                        trailing: {
                            AnyView(
                                HStack(spacing: 4) {
                                    Text("\(historicalMeetings.count)")
                                        .font(.system(size: 10, weight: .medium, design: .default))
                                        .foregroundStyle(Theme.textDim)

                                    Image(systemName: historyCollapsed ? "chevron.right" : "chevron.down")
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundStyle(Theme.textDim.opacity(0.6))
                                }
                            )
                        }
                    ) {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            historyCollapsed.toggle()
                        }
                    }
                }
            }
            .padding(.top, 10)
            .padding(.horizontal, 10)

            // History list
            if !historicalMeetings.isEmpty && !historyCollapsed {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Spacer()

                        HStack(spacing: 4) {
                            Text("/")
                                .font(.system(size: 10, weight: .medium, design: .default))
                                .foregroundStyle(Theme.textDim.opacity(0.6))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Theme.bgTertiary)
                                )

                            HStack(spacing: 2) {
                                    Text("↑")
                                        .font(.system(size: 10, weight: .medium, design: .default))
                                    Text("K")
                                        .font(.system(size: 10, weight: .medium, design: .default))
                                }
                                .foregroundStyle(Theme.textDim.opacity(0.6))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Theme.bgTertiary)
                                )

                                HStack(spacing: 2) {
                                    Text("↓")
                                        .font(.system(size: 10, weight: .medium, design: .default))
                                    Text("J")
                                        .font(.system(size: 10, weight: .medium, design: .default))
                                }
                                .foregroundStyle(Theme.textDim.opacity(0.6))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Theme.bgTertiary)
                                )
                            }
                        }
                    .padding(.horizontal, 10)

                    // Search field
                    HStack(spacing: 6) {
                        Text("/")
                            .font(.system(size: 11, weight: .semibold, design: .default))
                            .foregroundStyle(searchFieldFocused ? Theme.accent : Theme.textDim)

                        TextField("search meetings", text: $searchText)
                            .font(.system(size: 11, weight: .medium, design: .default))
                            .foregroundStyle(Theme.text)
                            .textFieldStyle(.plain)
                            .focused($searchFieldFocused)

                        if !searchText.isEmpty {
                            Text("\(displayedMeetings.count)")
                                .font(.system(size: 10, weight: .medium, design: .default))
                                .foregroundStyle(Theme.textDim)

                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.textDim)
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Theme.bg)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(searchFieldFocused ? Theme.accent.opacity(0.5) : Theme.border.opacity(0.5), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 10)
                    .onChange(of: isSearchActive) { _, active in
                        if active {
                            scheduleSearchFocus()
                        } else {
                            cancelPendingSearchFocus()
                        }
                    }
                    .onChange(of: searchFocusRequest) { _, _ in
                        scheduleSearchFocus()
                    }
                    .onChange(of: searchBlurRequest) { _, _ in
                        cancelPendingSearchFocus()
                    }
                    .onChange(of: searchFieldFocused) { _, focused in
                        onSearchFocusChange(focused)
                        if focused { isSearchActive = true }
                    }
                    .onDisappear {
                        searchFocusGeneration += 1
                        if searchFieldFocused {
                            onSearchFocusChange(false)
                        }
                    }

                    if isSearchActive && !searchText.isEmpty && displayedMeetings.isEmpty {
                        VStack(spacing: 6) {
                            Text("no results")
                                .font(.system(size: 11, weight: .medium, design: .default))
                                .foregroundStyle(Theme.textDim)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(historySections, id: \.title) { section in
                                    Text(section.title)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Theme.textDim)
                                        .textCase(.uppercase)
                                        .padding(.horizontal, 8)
                                        .padding(.top, 8)
                                    ForEach(section.meetings) { meeting in
                                        SidebarHistoryItem(
                                            meeting: meeting,
                                            isSelected: selectedMeetingID == meeting.id,
                                            searchQuery: isSearchActive ? searchText : nil,
                                            matchSnippet: searchSnippets[meeting.id],
                                            matchCount: searchMatchCounts[meeting.id],
                                            action: {
                                                showTraining = false
                                                selectedMeetingID = meeting.id
                                            },
                                            onTogglePin: {
                                                onTogglePin(meeting)
                                            },
                                            onDelete: {
                                                onDeleteMeeting(meeting)
                                            }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
            }

            Spacer()

            // Status bar
            VStack(alignment: .leading, spacing: 0) {
                GradientDivider()
                
                HStack(spacing: 8) {
                    if appState.appMode != .managed {
                        // BYOK mode status
                        Circle()
                            .fill(appState.deepgramApiKey.isEmpty ? ColorPalette.Status.noApiKey : Theme.accent)
                            .frame(width: 6, height: 6)
                            .shadow(color: appState.deepgramApiKey.isEmpty ? ColorPalette.Status.noApiKey.opacity(0.5) : Theme.accent.opacity(0.5), radius: 4)
                        
                        Text(appState.deepgramApiKey.isEmpty ? "byok • no_api_key" : "byok • connected")
                            .font(.system(size: 10, weight: .medium, design: .default))
                            .foregroundStyle(Theme.textDim)
                    }
                    
                    Spacer(minLength: 8)
                    
                    Button {
                        isCollapsed = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("⌘[")
                                .font(.system(size: 10, weight: .medium, design: .default))
                                .foregroundStyle(Theme.textDim.opacity(0.5))
                            Image(systemName: "sidebar.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.textDim)
                                .frame(width: 26, height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Theme.bgTertiary)
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .background(Theme.bgSecondary)
    }

    private func collapsedNavButton(icon: String, color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? color : Theme.textDim)
                .frame(width: 36, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isSelected ? Theme.bgTertiary : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func updateCollapsedStatusPulse() {
        guard appState.currentMeeting != nil, appState.isRecording else {
            collapsedStatusPulse = false
            return
        }

        collapsedStatusPulse = false
        withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
            collapsedStatusPulse = true
        }
    }

    private func scheduleSearchFocus() {
        searchFocusGeneration += 1
        let generation = searchFocusGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard searchFocusGeneration == generation else { return }
            searchFieldFocused = true
        }
    }

    private func cancelPendingSearchFocus() {
        searchFocusGeneration += 1
        searchFieldFocused = false
    }
}

// MARK: - Gradient Divider
struct GradientDivider: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Theme.border.opacity(0), Theme.borderLight, Theme.border.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }
}

// MARK: - Sidebar History Item
struct SidebarHistoryItem: View {
    @EnvironmentObject private var appState: AppState
    let meeting: Meeting
    let isSelected: Bool
    var searchQuery: String? = nil
    var matchSnippet: String? = nil
    var matchCount: Int? = nil
    let action: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var showDeleteConfirm = false
    
    private var titleText: String {
        meeting.displayTitle
    }

    private var highlightColor: Color { ColorPalette.Accent.amber }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 3) {
                    if meeting.isPinned {
                        Label("pinned", systemImage: "pin.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(ColorPalette.Accent.amber)
                    }
                    if let query = searchQuery, !query.isEmpty {
                        highlightedText(
                            titleText,
                            query: query,
                            baseColor: isSelected ? Theme.text : Theme.textMuted,
                            highlightColor: highlightColor,
                            font: .system(size: 11, weight: isSelected ? .semibold : .medium, design: .default)
                        )
                        .lineLimit(1)
                    } else {
                        Text(titleText)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .default))
                            .foregroundStyle(isSelected ? Theme.text : Theme.textMuted)
                            .lineLimit(1)
                    }

                    // Match snippet
                    if let snippet = matchSnippet, let query = searchQuery, !query.isEmpty {
                        highlightedText(
                            snippet,
                            query: query,
                            baseColor: Theme.textDim,
                            highlightColor: highlightColor,
                            font: .system(size: 10, weight: .medium, design: .default)
                        )
                        .lineLimit(2)
                    }

                    HStack(spacing: 6) {
                        Text(formatDate(meeting.startTime))
                            .font(.system(size: 10, weight: .medium, design: .default))
                            .foregroundStyle(Theme.textDim)
                            .layoutPriority(1)
                        Text("•")
                            .foregroundStyle(Theme.textDim.opacity(0.6))
                        Text(meeting.formattedDuration)
                            .font(.system(size: 10, weight: .medium, design: .default))
                            .foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: true, vertical: false)

                        if let lang = TranscriptionLanguage(rawValue: meeting.language), lang != .english {
                            Text("•")
                                .foregroundStyle(Theme.textDim.opacity(0.6))
                            Text("\(lang.flag) \(lang.rawValue.uppercased())")
                                .font(.system(size: 10, weight: .semibold, design: .default))
                                .foregroundStyle(Theme.textDim)
                        }

                        if let provenance = meeting.provenanceDisplayName {
                            Text("•")
                                .foregroundStyle(Theme.textDim.opacity(0.6))
                            Text(provenance.lowercased())
                                .font(.system(size: 10, weight: .semibold, design: .default))
                                .foregroundStyle(Theme.textDim)
                        }

                        if let count = matchCount, count > 0 {
                            Text("•")
                                .foregroundStyle(Theme.textDim.opacity(0.6))
                            Text("\(count) match\(count == 1 ? "" : "es")")
                                .font(.system(size: 10, weight: .medium, design: .default))
                                .foregroundStyle(highlightColor)
                        }
                    }
                    .lineLimit(1)

                    if appState.finalizingInsightMeetingIDs.contains(meeting.id) {
                        HStack(spacing: 5) {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(ColorPalette.Accent.blue)
                            Text("finishing insights…")
                                .font(.system(size: 10, weight: .medium, design: .default))
                                .foregroundStyle(ColorPalette.Accent.blue)
                                .lineLimit(1)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Finishing insights")
                        .help("Final insights are being generated in the background")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)

            // Overlay hover actions on the title instead of reserving permanent
            // trailing space or compressing the metadata row.
            HStack(spacing: 0) {
                Button(action: onTogglePin) {
                    Image(systemName: meeting.isPinned ? "pin.slash" : "pin")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(meeting.isPinned ? ColorPalette.Accent.amber : Theme.textDim)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(meeting.isPinned ? "Unpin meeting" : "Pin meeting")

                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.textDim)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            .background(isSelected ? Theme.bgTertiary : Theme.bgSecondary)
            .padding(.top, meeting.isPinned ? 14 : 0)
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
            .accessibilityHidden(!isHovering)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Theme.bgTertiary : (isHovering ? Theme.bgSecondary : Color.clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Theme.border : Color.clear, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .alert("Delete Meeting", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete \"\(titleText)\"? This cannot be undone.")
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        if Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: Date()) {
            return date.formatted(
                .dateTime
                    .day()
                    .month(.abbreviated)
                    .hour()
                    .minute()
            )
        }

        return date.formatted(
            .dateTime
                .day()
                .month(.abbreviated)
                .year()
                .hour()
                .minute()
        )
    }
}

struct SidebarIconItem: View {
    let systemIcon: String
    let label: String
    let isSelected: Bool
    var shortcut: String? = nil
    var trailing: (() -> AnyView)? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? ColorPalette.Text.primary : Theme.textDim)
                    .frame(width: 20)

                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium, design: .default))
                    .foregroundStyle(isSelected ? Theme.text : Theme.textMuted)

                Spacer()

                if let trailing = trailing {
                    trailing()
                } else if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .foregroundStyle(Theme.textDim)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Theme.bgTertiary : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

struct SidebarSessionItem: View {
    let title: String
    let isRecording: Bool
    let isSelected: Bool
    let action: () -> Void
    
    private var statusColor: Color {
        isRecording ? Theme.accentRed : Theme.accentBlue
    }
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                // Status row
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                        .shadow(color: statusColor.opacity(0.6), radius: isRecording ? 4 : 2)
                    
                    Text(isRecording ? "recording" : "session")
                        .font(.system(size: 10, weight: .semibold, design: .default))
                        .foregroundStyle(statusColor)
                    
                    Spacer()
                }
                
                // Title
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .default))
                    .foregroundStyle(isSelected ? Theme.text : Theme.textMuted)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Theme.bgTertiary : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Theme.border : Color.clear, lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

// MARK: - Meeting Detail View (for historical meetings)

struct MeetingDetailView: View {
    @Bindable var meeting: Meeting
    var showsBackToCoaching = false
    var onBackToCoaching: () -> Void = {}
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.interfaceScale) private var interfaceScale
    @AppStorage("attioExportEnabled") private var attioExportEnabled: Bool = false
    @AppStorage("twentyExportEnabled") private var twentyExportEnabled: Bool = false
    @State private var showingAttioSheet = false
    @State private var showingTwentySheet = false
    @State private var showExportedConfirmation = false
    @State private var renamingSpeaker: Int? = nil
    
    private let speakerColors: [Color] = [
        ColorPalette.Accent.blue,
        ColorPalette.Accent.purple,
        ColorPalette.Accent.green,
        ColorPalette.Accent.amber,
        ColorPalette.Accent.pink,
        ColorPalette.Accent.cyan,
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    meetingTitleNavigation
                        .frame(minWidth: 140)
                    Spacer(minLength: 0)
                    meetingMetadata(compact: false)
                    headerActions(compact: false)
                }

                VStack(alignment: .leading, spacing: 10) {
                    meetingTitleNavigation
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            meetingMetadata(compact: false)
                            Spacer(minLength: 0)
                            headerActions(compact: false)
                        }

                        HStack(spacing: 12) {
                            meetingMetadata(compact: true)
                            Spacer(minLength: 0)
                            headerActions(compact: true)
                        }
                    }
                }
            }
            .padding(16)
            .background(Theme.bgSecondary)
            
            GradientDivider()
            
            // Side by side content
            HSplitView {
                // Left side - transcript and notes
                ResizableNotesLayout {
                    // Transcript - takes most of the space
                    VStack(spacing: 0) {
                        DetailSectionHeader(title: "transcript", icon: "¶", onCopy: {
                            meeting.transcriptAsMarkdown()
                        })
                        
                        transcriptContent
                    }
                } notes: {
                    // Notes - compact, resizable
                    VStack(spacing: 0) {
                        DetailSectionHeader(title: "notes", icon: "✎", onCopy: {
                            meeting.notesAsMarkdown()
                        })
                        
                        SavedNotesView(meeting: meeting)
                    }
                }
                .frame(minWidth: 400)
                
                // Insights (right)
                Group {
                    if appState.isLiveInsightsCollapsed {
                        HistoricalCollapsedInsightsRail()
                    } else {
                        VStack(spacing: 0) {
                            DetailSectionHeader(title: "insights", icon: "◇", onCopy: {
                                meeting.insightsAsMarkdown()
                            })
                            
                            HistoricalInsightsModeSelector()
                            GradientDivider()
                            
                            ScrollView {
                                insightsContent
                            }
                            
                            GradientDivider()
                            
                            HStack {
                                HStack(spacing: 4) {
                                    HistoricalInsightsPaneToggleButton(direction: .collapse) {
                                        withAnimation(.easeInOut(duration: 0.16)) {
                                            appState.isLiveInsightsCollapsed = true
                                        }
                                    }
                                    Text("⌘]")
                                        .font(.system(size: 10, weight: .medium, design: .default))
                                        .foregroundStyle(Theme.textDim.opacity(0.5))
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Theme.bgSecondary)
                        }
                    }
                }
                .frame(minWidth: appState.isLiveInsightsCollapsed ? 44 : 280,
                       maxWidth: appState.isLiveInsightsCollapsed ? 44 : 600)
            }
        }
        .background(Theme.bg)
        .onDisappear {
            saveTitle()
        }
        .sheet(isPresented: $showingAttioSheet) {
            AttioSendSheet(meeting: meeting)
        }
        .sheet(isPresented: $showingTwentySheet) {
            TwentySendSheet(meeting: meeting)
        }
        .sheet(item: Binding(
            get: { renamingSpeaker.map { SpeakerRenameTarget(id: $0) } },
            set: { renamingSpeaker = $0?.id }
        )) { target in
            let key = String(target.id)
            let currentName = meeting.speakerNames[key]
            let defaultName = resolvedSpeakerLabel(for: target.id, names: nil, selfIDs: meeting.speakerLabelSelfIDs)
            let isSelf = meeting.effectiveSelfSpeakerIDs.contains(target.id)
            let hasOtherSelves = meeting.effectiveSelfSpeakerIDs.subtracting([target.id]).isEmpty == false
            RenameSpeakerView(
                speakerID: target.id,
                currentName: currentName,
                defaultName: defaultName,
                isSelf: isSelf,
                hasOtherSelves: hasOtherSelves,
                onSave: { newName in
                    meeting.setSpeakerName(id: key, name: newName)
                    renamingSpeaker = nil
                },
                onClear: {
                    meeting.setSpeakerName(id: key, name: nil)
                    renamingSpeaker = nil
                },
                onMarkAsSelf: {
                    meeting.setSelfSpeaker(id: target.id, isSelf: true)
                    try? modelContext.save()
                    renamingSpeaker = nil
                },
                onUnmarkAsSelf: {
                    meeting.setSelfSpeaker(id: target.id, isSelf: false)
                    try? modelContext.save()
                    renamingSpeaker = nil
                },
                onCancel: {
                    renamingSpeaker = nil
                }
            )
        }
    }

    private var meetingTitleNavigation: some View {
        HStack(spacing: 10) {
            if showsBackToCoaching {
                Button(action: onBackToCoaching) {
                    MinitiControlLabel(role: .secondary) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 9, weight: .bold))
                            Text("coaching")
                                .font(.system(size: 11, weight: .semibold, design: .default))
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("Back to Coaching")
            }

            meetingTitleField
        }
    }

    private var meetingTitleField: some View {
        TextField("meeting_title", text: $meeting.title)
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .bold, design: .default))
            .foregroundStyle(Theme.text)
            .lineLimit(1)
            .onSubmit {
                saveTitle()
            }
    }

    private func meetingMetadata(compact: Bool) -> some View {
        HStack(spacing: compact ? 10 : 16) {
            HStack(spacing: 4) {
                Text("◷")
                if compact {
                    Text(meeting.startTime.formatted(
                        .dateTime
                            .day()
                            .month(.abbreviated)
                            .hour()
                            .minute()
                    ))
                } else {
                    Text(meeting.startTime.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .help(meeting.startTime.formatted(date: .long, time: .shortened))
            .accessibilityLabel(meeting.startTime.formatted(date: .long, time: .shortened))
            HStack(spacing: 4) {
                Text("⏱")
                Text(meeting.formattedDuration)
            }
            HStack(spacing: 4) {
                Text("¶")
                Text("\(meeting.segments.count)")
            }
            if let provenance = meeting.provenanceDisplayName {
                HStack(spacing: 4) {
                    Image(systemName: "tray.and.arrow.down")
                    if !compact {
                        Text("Imported from \(provenance)")
                    }
                }
                .help("Imported from \(provenance)")
                .accessibilityLabel("Imported from \(provenance)")
            }
        }
        .font(.system(size: 11, weight: .regular, design: .default))
        .foregroundStyle(Theme.textDim)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func headerActions(compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 12) {
            Button(action: exportMeeting) {
                HStack(spacing: 6) {
                    Image(systemName: showExportedConfirmation ? "checkmark" : "arrow.down.doc")
                        .font(.system(size: 11))
                    if !compact {
                        Text(showExportedConfirmation ? "exported" : "export")
                            .font(.system(size: 11, weight: .semibold, design: .default))
                    }
                }
                .foregroundStyle(showExportedConfirmation ? ColorPalette.Status.success : ColorPalette.Accent.blue)
                .frame(minWidth: compact ? 30 : nil, minHeight: 28)
                .padding(.horizontal, compact ? 0 : 12)
                .background((showExportedConfirmation ? ColorPalette.Status.success : ColorPalette.Accent.blue).opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke((showExportedConfirmation ? ColorPalette.Status.success : ColorPalette.Accent.blue).opacity(0.22), lineWidth: 1)
                )
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Export meeting as Markdown")
            .accessibilityLabel(showExportedConfirmation ? "Meeting exported" : "Export meeting as Markdown")

            if attioExportEnabled {
                Button {
                    showingAttioSheet = true
                } label: {
                    HStack(spacing: 8) {
                        AttioLogoMark()
                            .frame(width: 14, height: 14)
                        if !compact {
                            Text("send to attio")
                                .font(.system(size: 11, weight: .semibold, design: .default))
                        }
                    }
                    .foregroundStyle(ColorPalette.Integrations.attio)
                    .frame(minWidth: compact ? 30 : nil, minHeight: 28)
                    .padding(.horizontal, compact ? 0 : 12)
                    .background(ColorPalette.Integrations.attio.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(ColorPalette.Integrations.attio.opacity(0.22), lineWidth: 1)
                    )
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Send meeting to Attio")
                .accessibilityLabel("Send meeting to Attio")
            }

            if twentyExportEnabled {
                Button {
                    showingTwentySheet = true
                } label: {
                    HStack(spacing: 8) {
                        TwentyLogoMark()
                            .frame(width: 14, height: 14)
                        if !compact {
                            Text("send to twenty")
                                .font(.system(size: 11, weight: .semibold, design: .default))
                        }
                    }
                    .foregroundStyle(ColorPalette.Integrations.twenty)
                    .frame(minWidth: compact ? 30 : nil, minHeight: 28)
                    .padding(.horizontal, compact ? 0 : 12)
                    .background(ColorPalette.Integrations.twenty.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(ColorPalette.Integrations.twenty.opacity(0.22), lineWidth: 1)
                    )
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Send meeting to Twenty")
                .accessibilityLabel("Send meeting to Twenty")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func exportMeeting() {
        let markdown = meeting.fullMeetingAsMarkdown()
        let filename = AppState.exportFilename(for: meeting)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        let exportPath = appState.markdownExportFolderPath
        if !exportPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: exportPath)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            showExportedConfirmation = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showExportedConfirmation = false
            }
        } catch {
            DebugLogger.shared.log(.app, "Manual export FAILED: \(error.localizedDescription)")
        }
    }

    private var transcriptContent: some View {
        let effectiveSelves = meeting.effectiveSelfSpeakerIDs
        let uniqueSpeakers = Set(meeting.segments.map(\.speaker))
            .sorted { a, b in
                let aSelf = effectiveSelves.contains(a)
                let bSelf = effectiveSelves.contains(b)
                if aSelf != bSelf { return aSelf }
                return a < b
            }
        return VStack(alignment: .leading, spacing: 12) {
            if !uniqueSpeakers.isEmpty {
                SpeakerLegend(
                    speakers: uniqueSpeakers,
                    isRecording: false,
                    speakerNames: meeting.speakerNames,
                    selfIDs: meeting.speakerLabelSelfIDs,
                    onRename: { renamingSpeaker = $0 }
                )
            }
            TranscriptTrimView(meeting: meeting)
        }
        .frame(maxHeight: .infinity)
    }
    
    private func saveTitle() {
        meeting.title = meeting.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if meeting.title.isEmpty {
            meeting.title = "untitled"
        }
        try? modelContext.save()
    }
    
    private var insightsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !meeting.segments.isEmpty && appState.insightsMode != .training && appState.insightsMode != .docs {
                HStack(spacing: 8) {
                    Button {
                        Task {
                            await appState.generateInsightsForMeeting(meeting)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9, weight: .semibold))
                            Text(meeting.needsInsightsAfterTranscriptEdit ? "regenerate" : "update")
                                .font(.system(size: 10, weight: .semibold, design: .default))
                            if appState.insightsMode == .meddpicc && !meeting.hasMEDDPICC {
                                Text("sales")
                                    .font(.system(size: 10, weight: .medium, design: .default))
                                    .foregroundStyle(Theme.textDim)
                            } else if appState.insightsMode == .questions && !meeting.hasQuestions {
                                Text("questions")
                                    .font(.system(size: 10, weight: .medium, design: .default))
                                    .foregroundStyle(Theme.textDim)
                            }
                        }
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Theme.bgTertiary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .disabled(appState.isGeneratingInsights)
                    .opacity(appState.isGeneratingInsights ? 0.5 : 1.0)
                    
                    if appState.isGeneratingInsights {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("updating...")
                                .font(.system(size: 10, weight: .medium, design: .default))
                                .foregroundStyle(Theme.textDim)
                        }
                    }
                    
                    Spacer()
                }
                if meeting.needsInsightsAfterTranscriptEdit {
                    Text("transcript edits cleared prior insights; regenerate to analyze the trimmed transcript")
                        .font(.system(size: 10, weight: .regular, design: .default))
                        .foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, 2)
                }
            }

            if appState.insightsMode == .standard {
                if meeting.hasInsights {
                // Summary
                if let summary = meeting.summaryText {
                    DetailInsightBlock(title: "summary", color: Theme.accentBlue) {
                        Text(summary)
                            .font(.system(size: interfaceScale.insightBodySize, weight: .regular, design: .default))
                            .foregroundStyle(Theme.text)
                            .lineSpacing(interfaceScale.insightLineSpacing)
                    }
                }
                
                // Discussion Flow
                if !meeting.discussionFlow.isEmpty {
                    DetailInsightBlock(title: "discussion", color: ColorPalette.Accent.yellow) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(meeting.discussionFlow.enumerated()), id: \.offset) { index, item in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(index + 1).")
                                        .font(.system(size: 10, weight: .medium, design: .default))
                                        .foregroundStyle(ColorPalette.Accent.yellow.opacity(0.7))
                                        .frame(width: 16, alignment: .trailing)
                                    Text(item)
                                        .font(.system(size: interfaceScale.insightSecondarySize, weight: .regular, design: .default))
                                        .foregroundStyle(Theme.text)
                                }
                            }
                        }
                    }
                }
                
                // Actions
                if !meeting.actionItems.isEmpty {
                    DetailInsightBlock(title: "actions", color: Theme.accent) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(meeting.actionItems, id: \.self) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("→")
                                        .foregroundStyle(Theme.accent)
                                    Text(item)
                                        .foregroundStyle(Theme.text)
                                }
                                .font(.system(size: interfaceScale.insightSecondarySize, weight: .regular, design: .default))
                            }
                        }
                    }
                }
                
                // Topics
                if !meeting.topics.isEmpty {
                    DetailInsightBlock(title: "topics", color: ColorPalette.Accent.purple) {
                        FlowLayout(spacing: 6) {
                            ForEach(meeting.topics, id: \.self) { topic in
                                Text("#\(topic.lowercased().replacingOccurrences(of: "_", with: " "))")
                                    .font(.system(size: 10, weight: .medium, design: .default))
                                    .foregroundStyle(ColorPalette.Accent.purple)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(ColorPalette.Accent.purple.opacity(0.15))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
                } else {
                    VStack(spacing: 10) {
                        Spacer()
                        Text("◇")
                            .font(.system(size: 28, weight: .ultraLight, design: .default))
                            .foregroundStyle(Theme.textDim)
                        Text("no insights yet")
                            .font(.system(size: 11, weight: .medium, design: .default))
                            .foregroundStyle(Theme.textMuted)
                        Text("use update above to generate")
                            .font(.system(size: 10, weight: .regular, design: .default))
                            .foregroundStyle(Theme.textDim)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            } else if appState.insightsMode == .questions {
                if meeting.hasQuestions {
                    QuestionsContent(questions: meeting.suggestedQuestions)
                } else {
                    QuestionsEmptyState(variant: .noQuestions)
                }
            } else if appState.insightsMode == .docs {
                DocsTabContent(
                    topics: meeting.docTopics,
                    isExtracting: appState.isExtractingDocsTopics,
                    hasMCPURL: appState.validatedDocsMCPURL != nil,
                    autoLookup: appState.canAutoLookupDocs,
                    lookupsRemaining: appState.docsLookupsRemaining,
                    canRefresh: !meeting.segments.isEmpty,
                    errorMessage: appState.docsLookupError,
                    onRefresh: {
                        Task { await appState.refreshDocsTopics(for: meeting) }
                    },
                    onLookup: { topicID in
                        Task { await appState.lookupDocTopic(id: topicID, for: meeting) }
                    }
                )
            } else if appState.insightsMode == .meddpicc {
                if meeting.hasMEDDPICC {
                    SavedMEDDPICCBlocks(meeting: meeting)
                } else {
                    VStack(spacing: 10) {
                        Spacer()
                        Text("◇")
                            .font(.system(size: 28, weight: .ultraLight, design: .default))
                            .foregroundStyle(Theme.textDim)
                        Text("no sales insights yet")
                            .font(.system(size: 11, weight: .medium, design: .default))
                            .foregroundStyle(Theme.textMuted)
                        Text("use update above to generate")
                            .font(.system(size: 10, weight: .regular, design: .default))
                            .foregroundStyle(Theme.textDim)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                if !meeting.segments.isEmpty {
                    SavedTrainingSection(meeting: meeting)
                } else {
                VStack(spacing: 10) {
                    Spacer()
                    Text("◇")
                        .font(.system(size: 28, weight: .ultraLight, design: .default))
                        .foregroundStyle(Theme.textDim)
                    Text("no transcript")
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .foregroundStyle(Theme.textMuted)
                    Text("record a meeting to see coaching stats")
                        .font(.system(size: 10, weight: .regular, design: .default))
                        .foregroundStyle(Theme.textDim)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
    }
}

private struct HistoricalInsightsPaneToggleButton: View {
    enum Direction { case collapse, expand }
    let direction: Direction
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: direction == .collapse ? "sidebar.right" : "sidebar.left")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textDim)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.bgTertiary)
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

private struct HistoricalCollapsedInsightsRail: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            Text("insights")
                .font(.system(size: 10, weight: .semibold, design: .default))
                .foregroundStyle(Theme.textMuted)
                .rotationEffect(.degrees(-90))
                .fixedSize()
                .frame(height: 120)
                .padding(.top, 12)
            
            Spacer()
            
            GradientDivider()
            
            HStack {
                Spacer()
                VStack(spacing: 3) {
                    Text("⌘]")
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .foregroundStyle(Theme.textDim.opacity(0.5))
                    HistoricalInsightsPaneToggleButton(direction: .expand) {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            appState.isLiveInsightsCollapsed = false
                        }
                    }
                }
                Spacer()
            }
            .padding(.vertical, 10)
            .background(Theme.bgSecondary)
        }
        .background(Theme.bg)
    }
}

// MARK: - Detail Section Header

struct DetailSectionHeader: View {
    let title: String
    let icon: String
    var onCopy: (() -> String)? = nil
    
    @State private var showCopied = false
    
    var body: some View {
        HStack(spacing: 8) {
            Text(icon)
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundStyle(Theme.textDim)
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .default))
                .foregroundStyle(Theme.textMuted)
            Spacer()
            
            // Copy button
            if let onCopy = onCopy {
                Button {
                    let markdown = onCopy()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCopied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showCopied = false
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9, weight: .medium))
                        Text(showCopied ? "copied" : "copy")
                            .font(.system(size: 10, weight: .medium, design: .default))
                    }
                    .foregroundStyle(showCopied ? Theme.accent : Theme.textDim)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.bgTertiary)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.bgSecondary)
    }
}

struct HistoricalInsightsModeSelector: View {
    var body: some View {
        InsightsModeTabs()
    }
}

// MARK: - Saved Notes View

struct SavedNotesView: View {
    @Bindable var meeting: Meeting
    @FocusState private var isFocused: Bool
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Placeholder
            if meeting.notes.isEmpty && !isFocused {
                Text("No notes for this meeting")
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(Theme.textDim)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            
            // Editable text editor
            TextEditor(text: $meeting.notes)
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundStyle(Theme.text)
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .background(Theme.bg)
    }
}

// MARK: - Detail Insight Block

struct DetailInsightBlock<Content: View>: View {
    let title: String
    let color: Color
    let info: TerminalSectionInfo?
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        color: Color,
        info: TerminalSectionInfo? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.color = color
        self.info = info
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(color)
                    .frame(width: 3, height: 12)
                    .cornerRadius(1.5)
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .default))
                    .foregroundStyle(color)
                if let info {
                    TerminalSectionInfoButton(info: info, accent: color)
                }
            }
            
            content()
                .padding(.leading, 12)
        }
    }
}

// MARK: - Saved MEDDPICC Blocks

struct SavedMEDDPICCBlocks: View {
    let meeting: Meeting
    
    private var fields: [(title: String, color: Color, value: String?)] {
        [
            ("metrics", ColorPalette.MEDDPICC.metrics, meeting.meddpiccMetrics),
            ("economic buyer", ColorPalette.MEDDPICC.economicBuyer, meeting.meddpiccEconomicBuyer),
            ("decision criteria", ColorPalette.MEDDPICC.decisionCriteria, meeting.meddpiccDecisionCriteria),
            ("decision process", ColorPalette.MEDDPICC.decisionProcess, meeting.meddpiccDecisionProcess),
            ("paper process", ColorPalette.MEDDPICC.paperProcess, meeting.meddpiccPaperProcess),
            ("identified pain", ColorPalette.MEDDPICC.identifiedPain, meeting.meddpiccIdentifiedPain),
            ("champion", ColorPalette.MEDDPICC.champion, meeting.meddpiccChampion),
            ("competition", ColorPalette.MEDDPICC.competition, meeting.meddpiccCompetition),
        ]
    }
    
    private func hasValue(_ value: String?) -> Bool {
        guard let value else { return false }
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !t.isEmpty && t != "null" && t != "n/a" && t != "none"
    }
    
    var body: some View {
        ForEach(fields.filter { hasValue($0.value) }, id: \.title) { field in
            DetailInsightBlock(title: field.title, color: field.color) {
                MEDDPICCBulletText(field.value!, fontSize: 12, color: Theme.text)
            }
        }
    }
}

// MARK: - Saved Training Section

struct SavedTrainingSection: View {
    let meeting: Meeting
    @State private var expandedPresentationIDs: Set<String> = []
    
    private var metrics: TrainingMetrics {
        let segments = meeting.segments.map {
            TrainingMetrics.Segment(
                text: $0.text,
                speaker: $0.speaker,
                isFinal: $0.isFinal,
                timestamp: $0.timestamp
            )
        }
        let duration = meeting.endTime?.timeIntervalSince(meeting.startTime) ?? 0
        return TrainingMetrics.compute(from: segments, duration: duration, language: meeting.language, names: meeting.speakerNames, selfIDs: meeting.speakerLabelSelfIDs)
    }

    private var speakerPresentations: [TrainingMetrics.SpeakerPresentation] {
        metrics.speakerPresentations()
    }

    private var displaySpeakers: [TrainingMetrics.SpeakerStats] {
        speakerPresentations.map(\.summary)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(speakerPresentations) { presentation in
                let speaker = presentation.summary
                if speaker.totalFillers > 0 || speaker.isLocalMic {
                    DetailInsightBlock(
                        title: "fillers: \(speaker.speakerLabel.lowercased())",
                        color: speaker.isLocalMic ? ColorPalette.Coaching.fillers : ColorPalette.Text.meta,
                        info: .fillers
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                Text("total \(speaker.totalFillers)")
                                    .font(.system(size: 10, weight: .medium, design: .default))
                                    .foregroundStyle(Theme.text)
                                Text("per min \(String(format: "%.1f", speaker.fillersPerMinute))")
                                    .font(.system(size: 10, weight: .medium, design: .default))
                                    .foregroundStyle(Theme.textDim)
                            }
                            
                            if presentation.hasMultipleDetails {
                                Button {
                                    toggleDetails(for: presentation.id)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: expandedPresentationIDs.contains(presentation.id) ? "chevron.down" : "chevron.right")
                                            .font(.system(size: 8, weight: .bold))
                                        Text(expandedPresentationIDs.contains(presentation.id) ? "hide speaker details" : "show speaker details")
                                            .font(.system(size: 10, weight: .semibold, design: .default))
                                    }
                                    .foregroundStyle(ColorPalette.Accent.blue)
                                }
                                .buttonStyle(.plain)

                                if expandedPresentationIDs.contains(presentation.id) {
                                    VStack(alignment: .leading, spacing: 10) {
                                        ForEach(Array(presentation.details.enumerated()), id: \.offset) { _, detail in
                                            savedFillerDetail(for: detail)
                                        }
                                    }
                                }
                            } else if !speaker.fillers.isEmpty {
                                savedFillerEntries(speaker.fillers)
                            }
                        }
                    }
                }
            }
            
            if metrics.speakers.count > 1 {
                DetailInsightBlock(title: "talk ratio", color: ColorPalette.Coaching.talkRatio, info: .talkRatio) {
                    HStack(spacing: 8) {
                        Text("you \(Int(metrics.talkRatioYou * 100))%")
                            .font(.system(size: 10, weight: .medium, design: .default))
                            .foregroundStyle(Theme.text)
                        Text("•")
                            .foregroundStyle(Theme.textDim)
                        Text("others \(Int((1 - metrics.talkRatioYou) * 100))%")
                            .font(.system(size: 10, weight: .medium, design: .default))
                            .foregroundStyle(Theme.textDim)
                    }
                }
            }
            
            DetailInsightBlock(title: "pace", color: ColorPalette.Coaching.pace, info: .pace) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(displaySpeakers) { speaker in
                        SavedTrainingMetricRow(
                            speaker: speaker,
                            value: "\(Int(speaker.wordsPerMinute)) wpm",
                            trailing: "\(speaker.wordCount) words"
                        )
                    }
                }
            }
            
            DetailInsightBlock(title: "longest monologue", color: ColorPalette.Coaching.monologue, info: .longestMonologue) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(displaySpeakers) { speaker in
                        if speaker.longestMonologueWords > 0 {
                            SavedTrainingMetricRow(
                                speaker: speaker,
                                value: "\(speaker.longestMonologueWords) words"
                            )
                        }
                    }
                }
            }
            
            DetailInsightBlock(title: "questions asked", color: ColorPalette.Coaching.questions, info: .questionsAsked) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(displaySpeakers) { speaker in
                        SavedTrainingMetricRow(
                            speaker: speaker,
                            value: "\(speaker.questionsAsked)"
                        )
                    }
                }
            }
            
            DetailInsightBlock(title: "clarity", color: ColorPalette.Coaching.clarity, info: .clarity) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(displaySpeakers) { speaker in
                        SavedTrainingMetricRow(
                            speaker: speaker,
                            value: String(format: "%.1f", speaker.avgWordsPerTurn),
                            trailing: "avg words/turn"
                        )
                    }
                    Text("lower = clearer = better")
                        .font(.system(size: 10, weight: .regular, design: .default))
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
    }

    private func toggleDetails(for id: String) {
        if expandedPresentationIDs.contains(id) {
            expandedPresentationIDs.remove(id)
        } else {
            expandedPresentationIDs.insert(id)
        }
    }

    private func savedFillerDetail(for speaker: TrainingMetrics.SpeakerStats) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(speaker.speakerLabel.lowercased()) · \(speaker.totalFillers)")
                .font(.system(size: 10, weight: .semibold, design: .default))
                .foregroundStyle(speaker.isLocalMic ? Theme.accent : Theme.text)
            if speaker.fillers.isEmpty {
                Text("no fillers detected")
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(Theme.textDim)
            } else {
                savedFillerEntries(speaker.fillers)
            }
        }
    }

    private func savedFillerEntries(_ entries: [TrainingMetrics.FillerEntry]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(entries) { entry in
                HStack(spacing: 6) {
                    Text(entry.word)
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .foregroundStyle(Theme.text)
                        .frame(width: 60, alignment: .trailing)
                    Text("\(entry.count)")
                        .font(.system(size: 10, weight: .semibold, design: .default))
                        .foregroundStyle(ColorPalette.Coaching.fillers)
                }
            }
        }
    }
}

private struct SavedTrainingMetricRow: View {
    let speaker: TrainingMetrics.SpeakerStats
    let value: String
    var trailing: String? = nil
    
    var body: some View {
        HStack(spacing: 8) {
            Text(speaker.speakerLabel.lowercased())
                .font(.system(size: 10, weight: .semibold, design: .default))
                .foregroundStyle(speaker.isLocalMic ? Theme.accent : Theme.textDim)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .default))
                .foregroundStyle(Theme.text)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(Theme.textDim)
            }
        }
    }
}

// MARK: - Visual Effect View (keep for compatibility)

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Keyboard Shortcuts Overlay

struct KeyboardShortcutsOverlay: View {
    @EnvironmentObject var keyboardService: KeyboardShortcutsService
    
    private var groupedShortcuts: [String: [KeyboardShortcut]] {
        Dictionary(grouping: allKeyboardShortcuts, by: { $0.category })
    }
    
    private let categoryOrder = ["Recording", "Navigation", "Insights", "App"]
    
    private func keycap(_ text: String, minWidth: CGFloat = 86, compact: Bool = false) -> some View {
        Text(text)
            .font(.system(size: compact ? 11 : 14, weight: .bold, design: .default))
            .foregroundStyle(Theme.text)
            .frame(minWidth: minWidth, alignment: .center)
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.vertical, compact ? 4 : 7)
            .background(
                RoundedRectangle(cornerRadius: compact ? 6 : 8)
                    .fill(Theme.bgSecondary.opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 6 : 8)
                    .stroke(Theme.border.opacity(0.9), lineWidth: 1)
            )
    }
    
    var body: some View {
        ZStack {
            // Dim background
            LinearGradient(
                colors: [
                    Color.black.opacity(0.82),
                    Color.black.opacity(0.68)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
                .ignoresSafeArea()
                .onTapGesture {
                    keyboardService.showingHelp = false
                }
            
            // Shortcuts panel
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("⌨")
                        .font(.system(size: 18))
                    Text("Keyboard Shortcuts")
                        .font(.system(size: 14, weight: .bold, design: .default))
                        .foregroundStyle(Theme.text)
                    
                    Spacer()
                    
                    Button {
                        keyboardService.showingHelp = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textDim)
                            .frame(width: 24, height: 24)
                            .background(Theme.bgSecondary)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .background(Theme.bgSecondary.opacity(0.9))
                
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)
                
                // Shortcuts grid
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(categoryOrder, id: \.self) { category in
                            if let shortcuts = groupedShortcuts[category] {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(category.uppercased())
                                        .font(.system(size: 10, weight: .bold, design: .default))
                                        .foregroundStyle(Theme.accent)
                                        .padding(.bottom, 4)
                                    
                                    ForEach(shortcuts) { shortcut in
                                        HStack(alignment: .center, spacing: 12) {
                                            keycap(shortcut.keys, minWidth: 96)
                                            
                                            Text(shortcut.description)
                                                .font(.system(size: 12, weight: .regular, design: .default))
                                                .foregroundStyle(Theme.textMuted)
                                            
                                            Spacer(minLength: 0)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                .frame(maxHeight: 420)
                
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)
                
                // Footer
                HStack {
                    Text("Press")
                        .font(.system(size: 10, weight: .regular, design: .default))
                        .foregroundStyle(Theme.textDim)
                    keycap("Esc", minWidth: 0, compact: true)
                    Text("or")
                        .font(.system(size: 10, weight: .regular, design: .default))
                        .foregroundStyle(Theme.textDim)
                    keycap("⌘/", minWidth: 0, compact: true)
                    Text("to close")
                        .font(.system(size: 10, weight: .regular, design: .default))
                        .foregroundStyle(Theme.textDim)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Theme.bgSecondary.opacity(0.9))
            }
            .frame(width: 460)
            .frame(maxHeight: 560)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Theme.bg.opacity(0.98))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Theme.border.opacity(0.95), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.04), lineWidth: 1)
                    .padding(1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.42), radius: 28, y: 10)
            .shadow(color: Theme.accent.opacity(0.08), radius: 40, y: 0)
            .padding(.horizontal, 28)
            .padding(.vertical, 32)
        }
    }
}

// MARK: - CRM Send (macOS history detail only)

enum CRMProvider: String, Sendable {
    case attio
    case twenty

    var displayName: String {
        switch self {
        case .attio: return "Attio"
        case .twenty: return "Twenty"
        }
    }

    var callbackScheme: String { "miniti-\(rawValue)" }
    var notificationName: Notification.Name {
        switch self {
        case .attio: return .minitiAttioOAuthCallback
        case .twenty: return .minitiTwentyOAuthCallback
        }
    }
    var accentColor: Color {
        switch self {
        case .attio: return ColorPalette.Integrations.attio
        case .twenty: return ColorPalette.Integrations.twenty
        }
    }
    var searchScopes: [CRMSearchScope] {
        switch self {
        case .attio: return [.people, .companies, .both]
        case .twenty: return [.people, .companies, .opportunities, .all]
        }
    }
    var defaultSearchScope: CRMSearchScope { self == .attio ? .both : .all }

    func connectStart(using api: MinitiAPIService, deviceId: String) async throws -> MinitiAPIService.AttioConnectStartResponse {
        switch self {
        case .attio: return try await api.attioConnectStart(deviceId: deviceId)
        case .twenty: return try await api.twentyConnectStart(deviceId: deviceId)
        }
    }

    func status(using api: MinitiAPIService, deviceId: String) async throws -> MinitiAPIService.AttioStatusResponse {
        switch self {
        case .attio: return try await api.attioStatus(deviceId: deviceId)
        case .twenty: return try await api.twentyStatus(deviceId: deviceId)
        }
    }

    func search(
        using api: MinitiAPIService,
        deviceId: String,
        query: String,
        objects: [String]
    ) async throws -> [MinitiAPIService.AttioSearchRecord] {
        switch self {
        case .attio: return try await api.attioSearch(deviceId: deviceId, query: query, objects: objects)
        case .twenty: return try await api.twentySearch(deviceId: deviceId, query: query, objects: objects)
        }
    }

    func send(
        using api: MinitiAPIService,
        deviceId: String,
        meetingPayload: AttioMeetingPayload,
        targetObject: String,
        targetRecordID: String,
        tasks: [CRMTaskPayload]
    ) async throws -> MinitiAPIService.AttioSendResponse {
        switch self {
        case .attio:
            return try await api.attioSendMeeting(
                deviceId: deviceId,
                meetingPayload: meetingPayload,
                targetObject: targetObject,
                targetRecordID: targetRecordID,
                createTasksFromActionItems: false,
                tasks: tasks
            )
        case .twenty:
            return try await api.twentySendMeeting(
                deviceId: deviceId,
                meetingPayload: meetingPayload,
                targetObject: targetObject,
                targetRecordID: targetRecordID,
                createTasksFromActionItems: false,
                tasks: tasks
            )
        }
    }

    func taskPayloads(from actionItems: [String], now: Date = Date()) -> [CRMTaskPayload] {
        let deadline = self == .attio ? CRMTaskPayload.localISODate(for: now) : nil
        return CRMTaskPayload.fromActionItems(actionItems, deadlineAt: deadline)
    }

    var taskAssigneePreview: String {
        switch self {
        case .attio: return "connected user; unassigned if unavailable"
        case .twenty: return "workspace default"
        }
    }
}

struct AttioLogoMark: View {
    var body: some View {
        Image("AttioLogo")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .foregroundStyle(ColorPalette.Integrations.attio)
            .accessibilityHidden(true)
    }
}

struct TwentyLogoMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(ColorPalette.Integrations.twenty.opacity(0.14))
            .overlay {
                Text("20")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(ColorPalette.Integrations.twenty)
            }
    }
}

struct AttioSendSheet: View {
    let meeting: Meeting
    var body: some View { CRMSendSheet(meeting: meeting, provider: .attio) }

    nonisolated static func parseOAuthCallback(_ url: URL) -> CRMSendSheet.OAuthCallbackPayload? {
        CRMSendSheet.parseOAuthCallback(url, provider: .attio)
    }
}

struct TwentySendSheet: View {
    let meeting: Meeting
    var body: some View { CRMSendSheet(meeting: meeting, provider: .twenty) }

    nonisolated static func parseOAuthCallback(_ url: URL) -> CRMSendSheet.OAuthCallbackPayload? {
        CRMSendSheet.parseOAuthCallback(url, provider: .twenty)
    }
}

struct CRMSendSheet: View {
    struct OAuthCallbackPayload: Equatable {
        let status: String?
        let message: String?
    }

    @Environment(\.dismiss) private var dismiss
    let meeting: Meeting
    let provider: CRMProvider
    @AppStorage("attioCreateTasksFromActionItems") private var attioCreateTasks: Bool = true
    @AppStorage("twentyCreateTasksFromActionItems") private var twentyCreateTasks: Bool = true

    @State private var api = MinitiAPIService()
    @State private var status: MinitiAPIService.AttioStatusResponse?
    @State private var isLoadingStatus = false
    @State private var isConnecting = false
    @State private var connectionError: String?

    @State private var query = ""
    @State private var selectedScope: CRMSearchScope
    @State private var results: [MinitiAPIService.AttioSearchRecord] = []
    @State private var selectedRecordID: String?
    @State private var selectedRecordObject: String?
    @State private var selectedRecordText: String?
    @State private var selectedRecordDetail: String?
    @State private var showSearchResults = false
    @State private var showPayloadDetails = false
    @State private var isSearching = false
    @State private var searchError: String?

    @State private var isSending = false
    @State private var sendMessage: String?
    @State private var sendError: String?
    @State private var localEscapeMonitor: Any?
    @State private var deviceId: String?
    @State private var taskPreviews: [CRMTaskPayload]
    @State private var selectedTaskContents: Set<String>

    init(meeting: Meeting, provider: CRMProvider) {
        self.meeting = meeting
        self.provider = provider
        let tasks = provider.taskPayloads(from: meeting.actionItems)
        _selectedScope = State(initialValue: provider.defaultSearchScope)
        _taskPreviews = State(initialValue: tasks)
        _selectedTaskContents = State(initialValue: Set(tasks.map(\.content)))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color(hex: "1C1C1F"))

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        connectionSection
                        searchSection
                        payloadPreviewSection
                        if createTasksFromActionItems, !taskPreviews.isEmpty {
                            taskPreviewSection
                                .id("crm-task-preview")
                        }
                    }
                    .padding(16)
                }
                .background(Color(hex: "09090B"))
                .onChange(of: createTasksFromActionItems) { _, enabled in
                    guard enabled, !taskPreviews.isEmpty else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo("crm-task-preview", anchor: .bottom)
                    }
                }
            }

            Divider().overlay(ColorPalette.Border.primary)
            sendSection
        }
        .frame(width: 640, height: 620)
        .background(Color(hex: "09090B"))
        .task {
            loadPersistedSelection()
            // Keychain can briefly block while macOS resolves access. Keep it off
            // the main actor so presenting this sheet never stalls the window.
            let resolvedDeviceID = await Task.detached(priority: .userInitiated) {
                DeviceIdentifier.getOrCreateDeviceId()
            }.value
            guard !Task.isCancelled else { return }
            deviceId = resolvedDeviceID
            await refreshStatus()
        }
        .onAppear {
            installLocalEscapeMonitor()
        }
        .onDisappear {
            removeLocalEscapeMonitor()
        }
        .onReceive(NotificationCenter.default.publisher(for: provider.notificationName)) { notification in
            guard let callbackURL = notification.userInfo?["url"] as? URL else { return }
            guard let payload = Self.parseOAuthCallback(callbackURL, provider: provider) else { return }
            DebugLogger.shared.log(.app, "[\(provider.rawValue)] oauth callback received status=\(payload.status ?? "nil")")
            Task { @MainActor in
                await handleOAuthCallback(payload)
            }
        }
#if os(macOS) || os(tvOS)
        .onExitCommand {
            dismiss()
        }
#endif
    }

    private var header: some View {
        HStack(spacing: 10) {
            providerLogo
                .frame(width: 18, height: 18)
            Text("send to \(provider.displayName.lowercased())")
                .font(.system(size: 13, weight: .bold, design: .default))
                .foregroundStyle(Color(hex: "E6EDF3"))
            Spacer()
            Button { dismiss() } label: {
                MinitiControlLabel(role: .secondary, height: 26, horizontalPadding: 8) {
                    Text("close")
                        .font(.system(size: 11, weight: .medium, design: .default))
                }
            }
                .buttonStyle(.plain)
                .focusable(false)
                .keyboardShortcut(.cancelAction)
        }
        .padding(14)
        .background(Color(hex: "0F0F11"))
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("\(provider.displayName.lowercased()) account")

            HStack(spacing: 10) {
                Circle()
                    .fill((status?.connected ?? false) ? ColorPalette.Status.connected : ColorPalette.Status.disconnected)
                    .frame(width: 8, height: 8)
                Text(connectionStatusText)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(Color(hex: "E6EDF3"))
                Spacer()
                if isLoadingStatus {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await startOAuth() }
                } label: {
                    MinitiControlLabel(role: .secondary, height: 28) {
                        Text((status?.connected ?? false) ? "reconnect" : "connect")
                            .font(.system(size: 11, weight: .semibold, design: .default))
                    }
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(deviceId == nil || isConnecting)
            }

            if let connectionError {
                errorLine(connectionError)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: "0F0F11"))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "1C1C1F"), lineWidth: 1))
        )
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("find \(provider.displayName.lowercased()) record")

            HStack(spacing: 8) {
                MinitiTabStripSurface {
                    HStack(spacing: 0) {
                        ForEach(provider.searchScopes, id: \.self) { scope in
                            Button {
                                selectedScope = scope
                            } label: {
                                MinitiTabLabel(
                                    title: scope.label,
                                    isSelected: selectedScope == scope,
                                    height: 26
                                )
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .accessibilityAddTraits(selectedScope == scope ? .isSelected : [])
                        }
                    }
                }
                Spacer()
            }

            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ColorPalette.Text.meta)

                    TextField(searchPlaceholder, text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundStyle(ColorPalette.Text.secondary)
                        .onSubmit {
                            Task { await runSearch() }
                        }

                    if !query.isEmpty {
                        Button {
                            query = ""
                            results = []
                            showSearchResults = false
                            searchError = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(ColorPalette.Text.meta)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .accessibilityLabel("Clear \(provider.displayName) search")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: 360)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(ColorPalette.Background.primary)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(ColorPalette.Border.primary, lineWidth: 1))
                )

                Button {
                    Task { await runSearch() }
                } label: {
                    MinitiControlLabel(role: .secondary, isEmphasized: searchIsEnabled, height: 30) {
                        HStack(spacing: 6) {
                            if isSearching {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            Text(isSearching ? "searching..." : "search \(provider.displayName.lowercased())")
                                .font(.system(size: 11, weight: .semibold, design: .default))
                        }
                    }
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(!searchIsEnabled)
                .opacity(searchIsEnabled ? 1 : 0.42)

                Spacer(minLength: 0)
            }

            if let searchError {
                errorLine(searchError)
            }

            if let selectedRecordID, selectedRecordObject != nil {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Image(systemName: "pin")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color(hex: "8B949E"))
                        Text(selectedRecordText ?? selectedRecordID)
                            .font(.system(size: 10, weight: .medium, design: .default))
                            .foregroundStyle(Color(hex: "E6EDF3"))
                            .lineLimit(1)
                        Text("· \(selectedObjectLabel)")
                            .font(.system(size: 10, weight: .regular, design: .default))
                            .foregroundStyle(Color(hex: "8B949E"))
                        Spacer()
                    }
                    if let selectedRecordDetail, !selectedRecordDetail.isEmpty {
                        Text(selectedRecordDetail)
                            .font(.system(size: 10, weight: .regular, design: .default))
                            .foregroundStyle(Color(hex: "8B949E"))
                            .padding(.leading, 18)
                            .textSelection(.enabled)
                    }
                }
            }

            if showSearchResults || !results.isEmpty {
                VStack(spacing: 6) {
                if results.isEmpty {
                    Text("no results yet")
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .foregroundStyle(ColorPalette.Text.disabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                } else {
                    ForEach(results) { record in
                        Button {
                            selectRecord(record)
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(color(for: record.objectSlug))
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.recordText)
                                        .font(.system(size: 12, weight: .medium, design: .default))
                                        .foregroundStyle(Color(hex: "E6EDF3"))
                                        .lineLimit(1)
                                    Text(record.detailLabel)
                                        .font(.system(size: 10, weight: .regular, design: .default))
                                        .foregroundStyle(Color(hex: "8B949E"))
                                        .textSelection(.enabled)
                                }
                                Spacer()
                                if selectedRecordID == record.idPayload.recordID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color(hex: "3FB950"))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedRecordID == record.idPayload.recordID ? Color(hex: "18181B") : Color(hex: "09090B"))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: "1C1C1F"), lineWidth: 1))
                            )
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                }
            }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: "0F0F11"))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "1C1C1F"), lineWidth: 1))
        )
    }

    private var payloadPreviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                sectionTitle("what will be sent")
                Text("\(includedPayloadCount) included")
                    .font(.system(size: 10, weight: .medium, design: .default))
                    .foregroundStyle(ColorPalette.Text.meta)
                Spacer()
                Button {
                    showPayloadDetails.toggle()
                } label: {
                    MinitiControlLabel(role: .secondary, height: 26, horizontalPadding: 8) {
                        HStack(spacing: 5) {
                            Text(showPayloadDetails ? "hide details" : "review details")
                            Image(systemName: showPayloadDetails ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .font(.system(size: 10, weight: .semibold, design: .default))
                    }
                }
                .buttonStyle(.plain)
                .focusable(false)
            }

            Text("A meeting note is added to the selected record. Transcript and coaching stay in Miniti.")
                .font(.system(size: 10, weight: .regular, design: .default))
                .foregroundStyle(ColorPalette.Text.meta)
                .fixedSize(horizontal: false, vertical: true)

            if showPayloadDetails {
                Divider().overlay(ColorPalette.Border.primary)
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading),
                    ],
                    alignment: .leading,
                    spacing: 6
                ) {
                    payloadLine("summary", hasValue(meeting.summaryText))
                    payloadLine("discussion", !meeting.discussionFlow.isEmpty)
                    payloadLine("action items", !normalizedActionItems.isEmpty)
                    payloadLine("decisions", !meeting.keyDecisions.isEmpty)
                    payloadLine("topics", !meeting.topics.isEmpty)
                    payloadLine("MEDDPICC", meeting.hasMEDDPICC)
                    payloadLine("notes", !meeting.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    payloadLine("transcript", false, note: "not sent")
                    payloadLine("coaching", false, note: "not sent")
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: "0F0F11"))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "1C1C1F"), lineWidth: 1))
        )
    }

    private var taskPreviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                sectionTitle("tasks to create")
                Text("\(selectedTaskPayloads.count) of \(taskPreviews.count) selected")
                    .font(.system(size: 10, weight: .medium, design: .default))
                    .foregroundStyle(ColorPalette.Text.meta)
                Spacer()
                Button {
                    selectedTaskContents = Set(taskPreviews.map(\.content))
                } label: {
                    MinitiControlLabel(role: .secondary, height: 26, horizontalPadding: 8) {
                        Text("select all")
                            .font(.system(size: 10, weight: .semibold, design: .default))
                    }
                }
                .buttonStyle(.plain)
                .disabled(selectedTaskPayloads.count == taskPreviews.count)

                Button {
                    selectedTaskContents.removeAll()
                } label: {
                    MinitiControlLabel(role: .secondary, height: 26, horizontalPadding: 8) {
                        Text("clear")
                            .font(.system(size: 10, weight: .semibold, design: .default))
                    }
                }
                .buttonStyle(.plain)
                .disabled(selectedTaskContents.isEmpty)
            }

            Text("Only checked tasks will be created. The meeting note still includes every action item.")
                .font(.system(size: 10, weight: .regular, design: .default))
                .foregroundStyle(ColorPalette.Text.meta)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(taskPreviews, id: \.content) { task in
                    Toggle(isOn: taskSelectionBinding(for: task.content)) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(task.content)
                                .font(.system(size: 11, weight: .medium, design: .default))
                                .foregroundStyle(ColorPalette.Text.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 12) {
                                    taskMetadataLabel(
                                        icon: "calendar",
                                        text: task.deadlineAt.map { "deadline \($0)" } ?? "no deadline"
                                    )
                                    taskMetadataLabel(icon: "circle", text: "status to do")
                                }
                                taskMetadataLabel(icon: "person", text: provider.taskAssigneePreview)
                                taskMetadataLabel(icon: "link", text: linkedRecordPreview)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(ColorPalette.Background.primary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(ColorPalette.Border.primary, lineWidth: 1)
                            )
                    )
                    .accessibilityHint("Uncheck to exclude this task from the CRM export")
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(ColorPalette.Background.panel)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ColorPalette.Border.primary, lineWidth: 1))
        )
    }

    private var sendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Toggle(isOn: createTasksBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("create \(provider.displayName.lowercased()) tasks")
                            .font(.system(size: 11, weight: .medium, design: .default))
                            .foregroundStyle(ColorPalette.Text.secondary)
                        Text(actionItemToggleDetail)
                            .font(.system(size: 10, weight: .regular, design: .default))
                            .foregroundStyle(ColorPalette.Text.meta)
                    }
                }
                .toggleStyle(.switch)
                .disabled(normalizedActionItems.isEmpty)

                Spacer(minLength: 12)

                Button {
                    Task { await sendToCRM() }
                } label: {
                    MinitiControlLabel(role: .primary, isEmphasized: true, height: 34, horizontalPadding: 14) {
                        HStack(spacing: 8) {
                            if isSending {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            Text(isSending ? "sending..." : "send meeting to \(provider.displayName.lowercased())")
                                .font(.system(size: 12, weight: .bold, design: .default))
                        }
                    }
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(!sendIsEnabled)
                .opacity(sendIsEnabled ? 1 : 0.42)
                .accessibilityHint(sendDisabledReason ?? "Adds this meeting to the selected \(provider.displayName) record")
            }

            if let sendMessage {
                Text(sendMessage)
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundStyle(ColorPalette.Status.success)
            }
            if let sendError {
                errorLine(sendError)
            }

            if sendMessage == nil, sendError == nil, let sendDisabledReason {
                Text(sendDisabledReason)
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(ColorPalette.Text.meta)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(ColorPalette.Background.panel)
    }

    @ViewBuilder
    private var providerLogo: some View {
        switch provider {
        case .attio: AttioLogoMark()
        case .twenty: TwentyLogoMark()
        }
    }

    private var createTasksBinding: Binding<Bool> {
        switch provider {
        case .attio: return $attioCreateTasks
        case .twenty: return $twentyCreateTasks
        }
    }

    private var createTasksFromActionItems: Bool {
        switch provider {
        case .attio: return attioCreateTasks
        case .twenty: return twentyCreateTasks
        }
    }

    private var connectionStatusText: String {
        if deviceId == nil { return "checking connection..." }
        if isConnecting { return "connecting..." }
        if let status, status.connected {
            if let label = status.accountLabel, !label.isEmpty {
                return "connected (\(label))"
            }
            return "connected"
        }
        return "not connected"
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .default))
            .foregroundStyle(ColorPalette.Text.secondary)
    }

    private func errorLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .default))
            .foregroundStyle(ColorPalette.Status.error)
    }

    private func payloadLine(_ label: String, _ included: Bool, note: String? = nil) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(included ? ColorPalette.Status.success : ColorPalette.Text.disabled)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .default))
                .foregroundStyle(ColorPalette.Text.secondary)
            if let note {
                Text("(\(note))")
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(ColorPalette.Text.meta)
            }
            Spacer()
        }
    }

    private func taskMetadataLabel(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 9, weight: .regular, design: .default))
            .foregroundStyle(ColorPalette.Text.meta)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func taskSelectionBinding(for content: String) -> Binding<Bool> {
        Binding(
            get: { selectedTaskContents.contains(content) },
            set: { isSelected in
                if isSelected {
                    selectedTaskContents.insert(content)
                } else {
                    selectedTaskContents.remove(content)
                }
            }
        )
    }

    private func color(for objectSlug: String) -> Color {
        switch objectSlug.lowercased() {
        case "people": return Color(hex: "58A6FF")
        case "companies": return Color(hex: "A371F7")
        case "opportunities": return ColorPalette.Integrations.twenty
        default: return Color(hex: "8B949E")
        }
    }

    private var searchPlaceholder: String {
        switch selectedScope {
        case .people:
            return "search people..."
        case .companies:
            return "search companies..."
        case .opportunities:
            return "search opportunities..."
        case .both:
            return "search people or companies..."
        case .all:
            return "search people, companies, or opportunities..."
        }
    }

    private var searchIsEnabled: Bool {
        !isSearching &&
        status?.connected == true &&
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    private var includedPayloadCount: Int {
        [
            hasValue(meeting.summaryText),
            !meeting.discussionFlow.isEmpty,
            !normalizedActionItems.isEmpty,
            !meeting.keyDecisions.isEmpty,
            !meeting.topics.isEmpty,
            meeting.hasMEDDPICC,
            !meeting.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        ].filter { $0 }.count
    }

    private var actionItemToggleDetail: String {
        guard !normalizedActionItems.isEmpty else { return "no action items in this meeting" }
        guard createTasksFromActionItems else {
            return "\(normalizedActionItems.count) available"
        }
        return "\(selectedTaskPayloads.count) of \(taskPreviews.count) selected"
    }

    private var sendIsEnabled: Bool {
        sendDisabledReason == nil && !isSending
    }

    private var sendDisabledReason: String? {
        if deviceId == nil || isLoadingStatus || status == nil {
            return "Checking your \(provider.displayName) connection..."
        }
        if status?.connected != true { return "Connect \(provider.displayName) above before sending." }
        if selectedRecordID == nil || selectedRecordObject == nil {
            return provider == .twenty
                ? "Select a person, company, or opportunity above to enable sending."
                : "Select a person or company above to enable sending."
        }
        return nil
    }

    private func hasValue(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var normalizedActionItems: [String] {
        AttioMeetingPayload.normalizedActionItems(from: meeting.actionItems)
    }

    private var selectedTaskPayloads: [CRMTaskPayload] {
        taskPreviews.filter { selectedTaskContents.contains($0.content) }
    }

    private func refreshStatus() async {
        guard let deviceId else { return }
        isLoadingStatus = true
        defer { isLoadingStatus = false }
        DebugLogger.shared.log(.app, "[\(provider.rawValue)] status refresh start")
        do {
            status = try await provider.status(using: api, deviceId: deviceId)
            connectionError = nil
            DebugLogger.shared.log(
                .app,
                "[\(provider.rawValue)] status refresh success connected=\(status?.connected == true) account=\(status?.accountLabel ?? "-")"
            )
        } catch {
            status = .init(connected: false, accountLabel: nil)
            if isMissingCRMBackend(error) {
                connectionError = "\(provider.displayName) backend endpoints are not deployed yet"
            }
            DebugLogger.shared.log(.app, "[\(provider.rawValue)] status refresh failed \(error.localizedDescription)")
        }
    }

    private func startOAuth() async {
        connectionError = nil
        guard let deviceId else {
            connectionError = "\(provider.displayName) connection is still loading"
            return
        }
        isConnecting = true
        defer { isConnecting = false }
        DebugLogger.shared.log(.app, "[\(provider.rawValue)] oauth start requested")

        do {
            let start = try await provider.connectStart(using: api, deviceId: deviceId)
            DebugLogger.shared.log(.app, "[\(provider.rawValue)] oauth start response callbackScheme=\(start.callbackScheme)")
            guard let authURL = URL(string: start.authURL) else {
                DebugLogger.shared.log(.app, "[\(provider.rawValue)] oauth start invalid auth URL")
                connectionError = "Invalid \(provider.displayName) auth URL from server"
                return
            }
            guard start.callbackScheme.lowercased() == provider.callbackScheme else {
                DebugLogger.shared.log(.app, "[\(provider.rawValue)] oauth start unexpected callback scheme=\(start.callbackScheme)")
                connectionError = "Unexpected callback scheme from server"
                return
            }
            guard NSWorkspace.shared.open(authURL) else {
                DebugLogger.shared.log(.app, "[\(provider.rawValue)] oauth browser open failed")
                connectionError = "Could not open browser for \(provider.displayName) login"
                return
            }
            DebugLogger.shared.log(.app, "[\(provider.rawValue)] oauth browser opened host=\(authURL.host ?? "-")")
        } catch {
            DebugLogger.shared.log(.app, "[\(provider.rawValue)] oauth start failed \(error.localizedDescription)")
            connectionError = userFacingCRMError(error)
        }
    }

    @MainActor
    private func handleOAuthCallback(_ payload: OAuthCallbackPayload) async {
        DebugLogger.shared.log(
            .app,
            "[\(provider.rawValue)] oauth callback parsed status=\(payload.status ?? "nil") message=\((payload.message ?? "").prefix(120))"
        )

        if payload.status != "success" {
            connectionError = payload.message ?? "\(provider.displayName) connection failed"
            DebugLogger.shared.log(.app, "[\(provider.rawValue)] oauth callback failed")
            return
        }

        connectionError = nil
        DebugLogger.shared.log(.app, "[\(provider.rawValue)] oauth callback success, refreshing status")
        await refreshStatus()
    }

    private func runSearch() async {
        searchError = nil
        sendMessage = nil
        guard let deviceId else {
            searchError = "\(provider.displayName) connection is still loading"
            return
        }
        guard status?.connected == true else {
            searchError = "Connect \(provider.displayName) first"
            DebugLogger.shared.log(.app, "[\(provider.rawValue)] search blocked not connected")
            return
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            DebugLogger.shared.log(.app, "[\(provider.rawValue)] search skipped query too short")
            return
        }

        isSearching = true
        showSearchResults = true
        defer { isSearching = false }
        DebugLogger.shared.log(
            .app,
            "[\(provider.rawValue)] search start scope=\(selectedScope.label.lowercased()) query='\(trimmed.prefix(80))'"
        )
        do {
            results = try await provider.search(
                using: api,
                deviceId: deviceId,
                query: trimmed,
                objects: selectedScope.objectSlugs
            )
            DebugLogger.shared.log(.app, "[\(provider.rawValue)] search success results=\(results.count)")
            if let selectedRecordID,
               let selectedRecordObject,
               !results.contains(where: { $0.idPayload.recordID == selectedRecordID && $0.objectSlug == selectedRecordObject }) {
                // Keep persisted target, but clear highlighted current search selection if missing.
                // (Selection remains sendable; this only affects visual matching in results list.)
            }
        } catch {
            searchError = userFacingCRMError(error)
            results = []
            DebugLogger.shared.log(.app, "[\(provider.rawValue)] search failed \(error.localizedDescription)")
        }
    }

    private func sendToCRM() async {
        sendError = nil
        sendMessage = nil
        guard let deviceId else {
            sendError = "\(provider.displayName) connection is still loading"
            return
        }
        guard let selectedRecordID, let selectedRecordObject else {
            sendError = "Select a \(provider.displayName) record first"
            return
        }
        isSending = true
        defer { isSending = false }
        do {
            let meetingPayload = AttioMeetingPayload.from(meeting: meeting)
            let tasksToCreate = createTasksFromActionItems ? selectedTaskPayloads : []
            DebugLogger.shared.log(
                .app,
                "[\(provider.rawValue)] send start object=\(selectedRecordObject) record=\(selectedRecordID) " +
                "notesPayload actionItems=\(meetingPayload.actionItems.count) selectedTasks=\(tasksToCreate.count)"
            )
            if !tasksToCreate.isEmpty {
                let previewItems = tasksToCreate.prefix(5).map(\.content).joined(separator: " | ")
                DebugLogger.shared.log(.app, "[\(provider.rawValue)] selected tasks: \(previewItems)")
            }
            let response = try await provider.send(
                using: api,
                deviceId: deviceId,
                meetingPayload: meetingPayload,
                targetObject: selectedRecordObject,
                targetRecordID: selectedRecordID,
                tasks: tasksToCreate
            )
            if response.success {
                let notePart = "\(response.noteIDs.count) note\(response.noteIDs.count == 1 ? "" : "s")"
                let createdTaskCount = response.taskCount ?? response.taskIDs.count
                let taskPart = !tasksToCreate.isEmpty
                    ? ", \(createdTaskCount) task\(createdTaskCount == 1 ? "" : "s")"
                    : ""
                let warningPart: String
                if let taskError = response.taskError {
                    DebugLogger.shared.log(
                        .app,
                        "[\(provider.rawValue)] task creation skipped error='\(taskError)' createdTasks=\(createdTaskCount) noteIDs=\(response.noteIDs.count)"
                    )
                    warningPart = " · task creation skipped: \(taskError)"
                } else if !tasksToCreate.isEmpty && createdTaskCount == 0 {
                    DebugLogger.shared.log(
                        .app,
                        "[\(provider.rawValue)] task creation returned zero tasks without explicit error; selectedTasks=\(tasksToCreate.count)"
                    )
                    warningPart = " · sent selected tasks but \(provider.displayName) returned 0 tasks"
                } else {
                    warningPart = ""
                }
                DebugLogger.shared.log(
                    .app,
                    "[\(provider.rawValue)] send success notes=\(response.noteIDs.count) tasks=\(createdTaskCount)"
                )
                sendMessage = "sent (\(notePart)\(taskPart))\(warningPart)"
            } else {
                DebugLogger.shared.log(.app, "[\(provider.rawValue)] send response success=false")
                sendError = "\(provider.displayName) send failed"
            }
        } catch {
            DebugLogger.shared.log(.app, "[\(provider.rawValue)] send failed \(error.localizedDescription)")
            sendError = userFacingCRMError(error)
        }
    }

    private func isMissingCRMBackend(_ error: Error) -> Bool {
        guard case let MinitiAPIService.ServiceError.serverError(message) = error else { return false }
        return message.contains("HTTP 404")
    }

    private var selectedObjectLabel: String {
        switch (selectedRecordObject ?? "").lowercased() {
        case "people": return "person"
        case "companies": return "company"
        case "opportunities": return "opportunity"
        default: return selectedRecordObject ?? ""
        }
    }

    private var linkedRecordPreview: String {
        let record = selectedRecordText ?? "selected record"
        let object = selectedObjectLabel
        return object.isEmpty ? record : "\(record) · \(object)"
    }

    private func userFacingCRMError(_ error: Error) -> String {
        if isMissingCRMBackend(error) {
            return "\(provider.displayName) backend endpoints are not deployed yet"
        }
        return error.localizedDescription
    }

    nonisolated static func parseOAuthCallback(_ url: URL, provider: CRMProvider) -> OAuthCallbackPayload? {
        guard url.scheme?.lowercased() == provider.callbackScheme else { return nil }
        guard url.host?.lowercased() == "oauth-callback" else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let status = components?.queryItems?.first(where: { $0.name == "status" })?.value
        let message = components?.queryItems?.first(where: { $0.name == "message" })?.value
        return OAuthCallbackPayload(status: status, message: message)
    }

    private func selectRecord(_ record: MinitiAPIService.AttioSearchRecord) {
        selectedRecordID = record.idPayload.recordID
        selectedRecordObject = record.objectSlug
        selectedRecordText = record.recordText
        selectedRecordDetail = record.recordDetail ?? record.secondaryIdentifier
        showSearchResults = false
        results = []
        DebugLogger.shared.log(
            .app,
            "[\(provider.rawValue)] selected record object=\(record.objectSlug) id=\(record.idPayload.recordID) text='\(record.recordText.prefix(80))'"
        )
        persistSelection()
    }

    private func loadPersistedSelection() {
        let defaults = UserDefaults.standard
        selectedRecordID = defaults.string(forKey: persistedSelectionKey("record_id"))
        selectedRecordObject = defaults.string(forKey: persistedSelectionKey("object"))
        selectedRecordText = defaults.string(forKey: persistedSelectionKey("label"))
        selectedRecordDetail = defaults.string(forKey: persistedSelectionKey("detail"))
    }

    private func persistSelection() {
        let defaults = UserDefaults.standard
        defaults.set(selectedRecordID, forKey: persistedSelectionKey("record_id"))
        defaults.set(selectedRecordObject, forKey: persistedSelectionKey("object"))
        defaults.set(selectedRecordText, forKey: persistedSelectionKey("label"))
        defaults.set(selectedRecordDetail, forKey: persistedSelectionKey("detail"))
    }

    private func persistedSelectionKey(_ suffix: String) -> String {
        "crm.\(provider.rawValue).lastSelection.\(meeting.id.uuidString).\(suffix)"
    }

    private func installLocalEscapeMonitor() {
        guard localEscapeMonitor == nil else { return }
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            guard event.keyCode == 53 else { return event } // Esc
            if event.type == .keyDown {
                dismiss()
            }
            return nil // consume to avoid window flash/beep
        }
    }

    private func removeLocalEscapeMonitor() {
        guard let localEscapeMonitor else { return }
        NSEvent.removeMonitor(localEscapeMonitor)
        self.localEscapeMonitor = nil
    }
}

enum CRMSearchScope: CaseIterable {
    case people
    case companies
    case opportunities
    case both
    case all

    var label: String {
        switch self {
        case .people: return "people"
        case .companies: return "companies"
        case .opportunities: return "opportunities"
        case .both: return "both"
        case .all: return "all"
        }
    }

    var objectSlugs: [String] {
        switch self {
        case .people: return ["people"]
        case .companies: return ["companies"]
        case .opportunities: return ["opportunities"]
        case .both: return ["people", "companies"]
        case .all: return ["people", "companies", "opportunities"]
        }
    }
}



#Preview {
    MainWindow()
        .environmentObject(AppState())
        .environmentObject(KeyboardShortcutsService.shared)
}
