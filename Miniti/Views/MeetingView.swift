import SwiftUI

struct MeetingView: View {
    @EnvironmentObject var appState: AppState
    @State private var meetingTitle: String = ""
    
    var body: some View {
        Group {
            if appState.currentMeeting == nil && !appState.isRecording {
                // Ready state - no active session
                ReadyStateView()
            } else {
                // Active session view
                VStack(spacing: 0) {
                    // Header
                    TerminalHeader(meetingTitle: $meetingTitle)
                    
                    // Divider
                    Rectangle()
                        .fill(Color(hex: "1C1C1F"))
                        .frame(height: 1)
                    
                    // Main content - split view with transcript+notes and live insights
                    HSplitView {
                        // Left side - transcript and notes (vertically split)
                        VSplitView {
                            // Transcript (top) - takes most of the space
                            VStack(spacing: 0) {
                                SectionHeader(title: "transcript", icon: "¶", onCopy: {
                                    appState.transcriptAsMarkdown()
                                })
                                TranscriptView()
                            }
                            .frame(minHeight: 300)
                            
                            // Notes (bottom) - very compact (~3 lines), resizable
                            VStack(spacing: 0) {
                                SectionHeader(title: "notes", icon: "✎", shortcut: "⌘⇧N", onCopy: {
                                    "## Notes\n\n\(appState.liveNotes)"
                                })
                                NotesEditor()
                            }
                            .frame(minHeight: 20, maxHeight: 700)
                        }
                        .frame(minWidth: 400)
                        
                        // Live Insights (right side)
                        VStack(spacing: 0) {
                            InsightsSectionHeader(onCopyInsights: {
                                appState.insightsAsMarkdown()
                            })
                            LiveInsightsPanel()
                        }
                        .frame(minWidth: 280, maxWidth: 350)
                    }
                }
            }
        }
        .background(Color(hex: "09090B"))
        .onAppear {
            meetingTitle = appState.currentMeeting?.title ?? ""
        }
        .onChange(of: meetingTitle) { _, newValue in
            // Only update meeting if user manually edited (not from auto-update)
            if let meeting = appState.currentMeeting,
               meeting.title != newValue {
                appState.currentMeeting?.title = newValue
            }
        }
        .onChange(of: appState.currentMeeting) { _, meeting in
            meetingTitle = meeting?.title ?? ""
        }
        .onChange(of: appState.currentMeeting?.title) { _, newTitle in
            // Sync when meeting title changes (e.g., from auto-update)
            if let newTitle, newTitle != meetingTitle {
                meetingTitle = newTitle
            }
        }
    }
}

// MARK: - Ready State View

struct ReadyStateView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @State private var editingDeepgram = false
    @State private var editingOpenAI = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Logo and title
            VStack(spacing: 12) {
                Text("⬢")
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "3FB950"))
                
                Text("miniti")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "E6EDF3"))
                
                Text("multi-dimensional meetings")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: "A1A1AA"))
                    .tracking(2)
            }
            
            // Mode-aware status section
            if appState.appMode == .managed {
                // Managed mode: show usage instead of API pills
                ManagedStatusView()
            } else {
                // BYOK mode: API key pills
                HStack(spacing: 12) {
                    APIStatusPill(
                        label: "deepgram",
                        key: $appState.deepgramApiKey,
                        isEditing: $editingDeepgram,
                        placeholder: "dg_..."
                    )
                    
                    APIStatusPill(
                        label: "openai",
                        key: $appState.openaiApiKey,
                        isEditing: $editingOpenAI,
                        placeholder: "sk-..."
                    )
                }
            }
            
            // Model selector
            VStack(spacing: 8) {
                Text("model")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: "484F58"))
                    .tracking(1)
                
                HomeModelSelector()
            }
            
            // Audio sources (pre-flight check with waveforms)
            AudioSourcePanel()
            
            // Update available banner
            if let update = appState.availableUpdate {
                UpdateAvailableBanner(versionInfo: update)
            }
            
            // Limit reached warning (managed mode)
            if appState.appMode == .managed, let usage = appState.usageInfo, usage.minutesRemaining < 60, !usage.isLimitReached {
                LimitWarningBanner(minutesRemaining: usage.minutesRemaining)
            }
            
            // Start button or limit reached
            if appState.isLimitReached {
                // Show inline limit message
                VStack(spacing: 8) {
                    Text("limit reached")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(hex: "F85149"))
                    
                    Button {
                        appState.appModeRaw = AppMode.byok.rawValue
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 10))
                            Text("switch to BYOK")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                        .foregroundStyle(Color(hex: "58A6FF"))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(hex: "58A6FF").opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button(action: {
                    appState.startNewMeeting()
                }) {
                    HStack(spacing: 12) {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color(hex: "09090B"))
                                .frame(width: 8, height: 8)
                            Text("relax and take notes")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        }
                        
                        Text("⌘⇧R")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(hex: "09090B").opacity(0.5))
                    }
                    .foregroundStyle(Color(hex: "09090B"))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(appState.canStartRecording ? Color(hex: "3FB950") : Color(hex: "484F58"))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!appState.canStartRecording)
            }
            
            // Keyboard shortcut hint
            ShortcutHint(keys: "⌘/", label: "shortcuts")
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "52525B"))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(hex: "0F0F11"))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(hex: "27272A"), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .focusable(false)
            .padding(12)
        }
    }
}

// MARK: - API Status Pill

struct APIStatusPill: View {
    let label: String
    @Binding var key: String
    @Binding var isEditing: Bool
    let placeholder: String
    
    @FocusState private var isFocused: Bool
    @State private var isHovering = false
    
    var isConnected: Bool { !key.isEmpty }
    
    var body: some View {
        if isEditing {
            // Edit mode - show input field
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: "71717A"))
                
                HStack(spacing: 8) {
                    SecureField(placeholder, text: $key)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(hex: "E6EDF3"))
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                    
                    Button {
                        isEditing = false
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(isConnected ? Color(hex: "3FB950") : Color(hex: "71717A"))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: "18181B"))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(hex: "3FB950").opacity(0.5), lineWidth: 1)
                )
            }
            .frame(width: 160)
            .onAppear {
                isFocused = true
            }
        } else {
            // Status pill - click to edit
            Button {
                isEditing = true
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isConnected ? Color(hex: "3FB950") : Color(hex: "71717A"))
                        .frame(width: 6, height: 6)
                    
                    Text(label)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(isConnected ? Color(hex: "D4D4D8") : Color(hex: "71717A"))
                    
                    if isConnected {
                        Text("connected")
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color(hex: "3FB950").opacity(0.8))
                    } else {
                        Text("click to add")
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color(hex: "71717A").opacity(0.6))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color(hex: "0F0F11"))
                        .overlay(
                            Capsule()
                                .stroke(
                                    isConnected 
                                        ? Color(hex: "3FB950").opacity(isHovering ? 0.5 : 0.3) 
                                        : Color(hex: "3F3F46").opacity(isHovering ? 0.8 : 0.5),
                                    lineWidth: 1
                                )
                        )
                )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovering = hovering
            }
        }
    }
}

// MARK: - Home Screen Components

struct ShortcutHint: View {
    let keys: String
    let label: String
    
    var body: some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: "D4D4D8"))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: "1C1C1F"))
                )
            
            Text(label)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(Color(hex: "71717A"))
        }
    }
}

struct HomeModelSelector: View {
    @EnvironmentObject var appState: AppState
    
    private var selectedModel: DeepgramModel {
        DeepgramModel(rawValue: appState.deepgramModel) ?? .nova3
    }
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(DeepgramModel.allCases, id: \.self) { model in
                Button {
                    appState.deepgramModel = model.rawValue
                } label: {
                    VStack(spacing: 2) {
                        Text(model.displayName)
                            .font(.system(size: 11, weight: selectedModel == model ? .semibold : .medium, design: .monospaced))
                            .foregroundStyle(selectedModel == model ? Color(hex: "FAFAFA") : Color(hex: "D4D4D8"))
                        
                        Text(model.shortDescription)
                            .font(.system(size: 8, weight: .regular, design: .monospaced))
                            .foregroundStyle(selectedModel == model ? Color(hex: "D4D4D8") : Color(hex: "A1A1AA"))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedModel == model ? Color(hex: "1C1C1F") : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: "0F0F11"))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(hex: "1C1C1F"), lineWidth: 1)
                )
        )
    }
}

struct StatusCheckRow: View {
    let label: String
    let isReady: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Text(isReady ? "✓" : "○")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(isReady ? Color(hex: "3FB950") : Color(hex: "484F58"))
                .frame(width: 16)
            
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: "8B949E"))
            
            Spacer()
            
            Text(isReady ? "configured" : "missing")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(isReady ? Color(hex: "3FB950") : Color(hex: "D29922"))
        }
    }
}

struct SectionHeader: View {
    let title: String
    let icon: String
    var shortcut: String? = nil
    var onCopy: (() -> String)? = nil
    
    @State private var showCopied = false
    
    var body: some View {
        HStack(spacing: 8) {
            Text(icon)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: "484F58"))
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(hex: "8B949E"))
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
                        Text(showCopied ? "copied" : "md")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(showCopied ? Color(hex: "3FB950") : Color(hex: "52525B"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: "1C1C1F"))
                    )
                }
                .buttonStyle(.plain)
            }
            
            if let shortcut = shortcut {
                Text(shortcut)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: "3F3F46"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(hex: "0F0F11"))
    }
}

// MARK: - Notes Editor

struct NotesEditor: View {
    @EnvironmentObject var appState: AppState
    @FocusState private var isFocused: Bool
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Placeholder
            if appState.liveNotes.isEmpty && !isFocused {
                Text("relax and take notes...")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "3F3F46"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            
            // Text editor
            TextEditor(text: $appState.liveNotes)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(Color(hex: "E6EDF3"))
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .background(Color(hex: "09090B"))
    }
}

struct InsightsSectionHeader: View {
    @EnvironmentObject var appState: AppState
    var onCopyInsights: (() -> String)? = nil
    
    @State private var showCopied = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Top row: insights label + model selector + copy
            HStack(spacing: 8) {
                Text("◇")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: "484F58"))
                Text("insights")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(hex: "8B949E"))
                
                Spacer()
                
                // Copy to markdown button
                if let onCopyInsights = onCopyInsights {
                    Button {
                        let markdown = onCopyInsights()
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
                            Text(showCopied ? "copied" : "md")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                        }
                        .foregroundStyle(showCopied ? Color(hex: "3FB950") : Color(hex: "52525B"))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(hex: "1C1C1F"))
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                // OpenAI Model selector (sexier)
                OpenAIModelSelector()
            }
            
            // Mode selector - centered, larger
            HStack(spacing: 2) {
                ForEach(Array(InsightsMode.allCases.enumerated()), id: \.element) { index, mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            appState.switchInsightsMode(to: mode)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(mode.displayName)
                                .font(.system(size: 11, weight: appState.insightsMode == mode ? .semibold : .medium, design: .monospaced))
                                .foregroundStyle(appState.insightsMode == mode ? Color(hex: "FAFAFA") : Color(hex: "71717A"))
                            
                            Text("⌘\(index + 1)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(appState.insightsMode == mode ? Color(hex: "FAFAFA").opacity(0.4) : Color(hex: "3F3F46"))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(appState.insightsMode == mode ? Color(hex: "22C55E").opacity(0.15) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: "09090B"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(hex: "27272A"), lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(hex: "0F0F11"))
    }
}

// MARK: - OpenAI Model Selector

struct OpenAIModelSelector: View {
    @EnvironmentObject var appState: AppState
    @State private var showPopover = false
    @State private var isHovering = false
    
    private var selectedModel: OpenAIModel {
        OpenAIModel(rawValue: appState.openaiModel) ?? .gpt5Mini
    }
    
    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: 6) {
                // AI indicator dot
                Circle()
                    .fill(Color(hex: "A78BFA"))
                    .frame(width: 5, height: 5)
                
                Text(selectedModel.shortName)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: "D4D4D8"))
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(Color(hex: "71717A"))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovering ? Color(hex: "27272A") : Color(hex: "18181B"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isHovering ? Color(hex: "3F3F46") : Color(hex: "27272A"), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            OpenAIModelPopover(selectedModel: $appState.openaiModel)
        }
    }
}

struct OpenAIModelPopover: View {
    @Binding var selectedModel: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Model")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(hex: "E6EDF3"))
            
            ForEach(OpenAIModel.allCases, id: \.self) { model in
                Button {
                    selectedModel = model.rawValue
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(hex: "A78BFA"))
                                    .frame(width: 6, height: 6)
                                Text(model.displayName)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Color(hex: "E6EDF3"))
                            }
                            
                            Spacer()
                            
                            if selectedModel == model.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color(hex: "A78BFA"))
                            }
                        }
                        
                        Text(model.shortDescription)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(hex: "8B949E"))
                        
                        // Pros
                        HStack(alignment: .top, spacing: 4) {
                            Text("+")
                                .foregroundStyle(Color(hex: "3FB950"))
                            Text(model.pros.joined(separator: ", "))
                                .foregroundStyle(Color(hex: "8B949E"))
                        }
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        
                        // Cons
                        HStack(alignment: .top, spacing: 4) {
                            Text("-")
                                .foregroundStyle(Color(hex: "F85149"))
                            Text(model.cons.joined(separator: ", "))
                                .foregroundStyle(Color(hex: "8B949E"))
                        }
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedModel == model.rawValue ? Color(hex: "1C1C1F") : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(selectedModel == model.rawValue ? Color(hex: "A78BFA").opacity(0.3) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 280)
        .background(Color(hex: "0F0F11"))
    }
}

struct LiveInsightsPanel: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Status indicator
                if appState.isGeneratingInsights {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(appState.insightsMode == .meddpicc ? "analyzing with MEDDPICC..." : "updating...")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(hex: "58A6FF"))
                    }
                    .padding(.horizontal, 16)
                }
                
                // Summary (always shown)
                if !appState.liveSummary.isEmpty {
                    LiveInsightSection(title: "summary", color: Color(hex: "58A6FF")) {
                        Text(appState.liveSummary)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color(hex: "E6EDF3"))
                            .lineSpacing(4)
                    }
                }
                
                // Discussion Flow (chronological)
                if !appState.liveDiscussionFlow.isEmpty && appState.insightsMode == .standard {
                    LiveInsightSection(title: "discussion", color: Color(hex: "F59E0B")) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(appState.liveDiscussionFlow.enumerated()), id: \.offset) { index, item in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(index + 1).")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Color(hex: "F59E0B").opacity(0.7))
                                        .frame(width: 16, alignment: .trailing)
                                    Text(item)
                                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                                        .foregroundStyle(Color(hex: "D4D4D8"))
                                }
                            }
                        }
                    }
                }
                
                // MEDDPICC Framework (only in meddpicc mode)
                if appState.insightsMode == .meddpicc {
                    LiveMEDDPICCGrid()
                }
                
                // Action Items
                if !appState.liveActionItems.isEmpty {
                    LiveInsightSection(title: "actions", color: Color(hex: "3FB950")) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(appState.liveActionItems, id: \.self) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("→")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Color(hex: "3FB950"))
                                    Text(item)
                                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                                        .foregroundStyle(Color(hex: "E6EDF3"))
                                }
                            }
                        }
                    }
                }
                
                // Topics
                if !appState.liveTopics.isEmpty {
                    LiveInsightSection(title: "topics", color: Color(hex: "A371F7")) {
                        FlowLayout(spacing: 6) {
                            ForEach(appState.liveTopics, id: \.self) { topic in
                                Text("#\(topic.lowercased().replacingOccurrences(of: " ", with: "_"))")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color(hex: "A371F7"))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color(hex: "A371F7").opacity(0.15))
                                    .cornerRadius(3)
                            }
                        }
                    }
                }
                
                // Empty state
                if appState.liveSummary.isEmpty && !appState.isGeneratingInsights {
                    VStack(spacing: 12) {
                        Text("◇")
                            .font(.system(size: 28, weight: .ultraLight, design: .monospaced))
                            .foregroundStyle(Color(hex: "1C1C1F"))
                        
                        if appState.isRecording {
                            Text("listening...")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color(hex: "484F58"))
                            Text("insights after 5 sentences")
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color(hex: "1C1C1F"))
                        } else if appState.openaiApiKey.isEmpty {
                            Text("openai_key_missing")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color(hex: "D29922"))
                        } else {
                            Text("start recording")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color(hex: "484F58"))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }
                
                Spacer(minLength: 20)
            }
            .padding(.top, 12)
        }
        .background(Color(hex: "09090B"))
    }
}

// MARK: - Live MEDDPICC List

struct LiveMEDDPICCGrid: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color(hex: "F59E0B"))
                    .frame(width: 3, height: 14)
                    .cornerRadius(1)
                Text("MEDDPICC FRAMEWORK")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "F59E0B"))
            }
            
            // Vertical list
            VStack(spacing: 10) {
                MEDDPICCRow(letter: "M", title: "Metrics", value: appState.liveMetrics, color: "3B82F6")
                MEDDPICCRow(letter: "E", title: "Economic Buyer", value: appState.liveEconomicBuyer, color: "8B5CF6")
                MEDDPICCRow(letter: "D", title: "Decision Criteria", value: appState.liveDecisionCriteria, color: "EC4899")
                MEDDPICCRow(letter: "D", title: "Decision Process", value: appState.liveDecisionProcess, color: "F59E0B")
                MEDDPICCRow(letter: "P", title: "Paper Process", value: appState.livePaperProcess, color: "F97316")
                MEDDPICCRow(letter: "I", title: "Identified Pain", value: appState.liveIdentifiedPain, color: "EF4444")
                MEDDPICCRow(letter: "C", title: "Champion", value: appState.liveChampion, color: "22C55E")
                MEDDPICCRow(letter: "C", title: "Competition", value: appState.liveCompetition, color: "6366F1")
            }
        }
        .padding(.horizontal, 16)
    }
}

struct MEDDPICCRow: View {
    let letter: String
    let title: String
    let value: String?
    let color: String
    
    private var hasValue: Bool {
        guard let value else { return false }
        return !value.isEmpty && value.lowercased() != "null"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title row
            HStack(spacing: 8) {
                Text(letter)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(hasValue ? Color(hex: color) : Color(hex: "52525B"))
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(hasValue ? Color(hex: color).opacity(0.15) : Color(hex: "18181B"))
                    )
                
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(hasValue ? Color(hex: "FAFAFA") : Color(hex: "52525B"))
                
                Spacer()
                
                if hasValue {
                    Circle()
                        .fill(Color(hex: color))
                        .frame(width: 6, height: 6)
                }
            }
            
            // Value
            if hasValue, let value {
                Text(value)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "D4D4D8"))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Not yet identified")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "3F3F46"))
                    .italic()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: "0C0C0E"))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(hasValue ? Color(hex: color).opacity(0.25) : Color(hex: "1C1C1F"), lineWidth: 1)
                )
        )
    }
}

struct LiveInsightSection<Content: View>: View {
    let title: String
    let color: Color
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(color)
                    .frame(width: 3, height: 12)
                    .cornerRadius(1)
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                    .textCase(.uppercase)
            }
            
            content()
                .padding(.leading, 12)
        }
        .padding(.horizontal, 16)
    }
}

struct TerminalHeader: View {
    @EnvironmentObject var appState: AppState
    @Binding var meetingTitle: String
    @State private var isEditingTitle = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Recording controls
            HStack(spacing: 12) {
                // Home button (only when not recording - to go back to home screen)
                if !appState.isRecording && appState.currentMeeting != nil {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            appState.goHome()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            HStack(spacing: 5) {
                                Text("⬢")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                Text("home")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                            }
                            .foregroundStyle(Color(hex: "8B949E"))
                            
                            Text("⌘H")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color(hex: "52525B"))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(hex: "1C1C1F"))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(hex: "30363D"), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                // Status indicator (only when recording)
                if appState.isRecording {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: "F85149"))
                            .frame(width: 8, height: 8)
                            .shadow(color: Color(hex: "F85149").opacity(0.5), radius: 4)
                        
                        Text(appState.formattedDuration)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(hex: "F85149"))
                    }
                }
                
                // Record button
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if appState.isRecording {
                            appState.stopRecording()
                        } else if appState.currentMeeting != nil {
                            // Resume recording on the current session
                            appState.startRecording()
                        } else {
                            appState.startNewMeeting()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: appState.isRecording ? "stop.fill" : "record.circle")
                                .font(.system(size: 11, weight: .semibold))
                            Text(appState.isRecording ? "stop" : "cont")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        }
                        .foregroundStyle(appState.isRecording ? Color(hex: "F85149") : Color(hex: "3FB950"))
                        
                        Text("⌘⇧R")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(appState.isRecording ? Color(hex: "F85149").opacity(0.5) : Color(hex: "3FB950").opacity(0.5))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(appState.isRecording ? Color(hex: "F85149").opacity(0.15) : Color(hex: "3FB950").opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(appState.isRecording ? Color(hex: "F85149").opacity(0.3) : Color(hex: "3FB950").opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                // Audio waveforms (next to record button when recording)
                // Model selector (only when not recording, after record button so button stays in place)
                if !appState.isRecording {
                    DeepgramModelSelector()
                }
                if appState.isRecording {
                    HStack(spacing: 8) {
                        // Mic waveform
                        if appState.captureMicrophone {
                            HStack(spacing: 4) {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(Color(hex: "3FB950").opacity(0.7))
                                SourceWaveform(
                                    level: appState.microphoneLevel,
                                    color: Color(hex: "3FB950"),
                                    bandCount: 5,
                                    barWidth: 3,
                                    maxHeight: 20
                                )
                                .frame(width: 22, height: 20)
                            }
                        }
                        
                        // System audio waveform
                        if appState.captureSystemAudio {
                            HStack(spacing: 4) {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(Color(hex: "58A6FF").opacity(0.7))
                                SourceWaveform(
                                    level: appState.systemAudioLevel,
                                    color: Color(hex: "58A6FF"),
                                    bandCount: 5,
                                    barWidth: 3,
                                    maxHeight: 20
                                )
                                .frame(width: 22, height: 20)
                            }
                        }
                    }
                }
            }
            
            Spacer()
            
            // Session title
            HStack(spacing: 6) {
                Text("~")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: "484F58"))
                
                if isEditingTitle {
                    TextField("session_name", text: $meetingTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(hex: "E6EDF3"))
                        .onSubmit { isEditingTitle = false }
                        .frame(maxWidth: 300)
                } else {
                    Text(meetingTitle)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(hex: "8B949E"))
                        .lineLimit(1)
                        .onTapGesture { isEditingTitle = true }
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(hex: "0F0F11"))
    }
}

// MARK: - Deepgram Model Selector

struct DeepgramModelSelector: View {
    @EnvironmentObject var appState: AppState
    @State private var showPopover = false
    
    private var selectedModel: DeepgramModel {
        DeepgramModel(rawValue: appState.deepgramModel) ?? .nova3
    }
    
    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(selectedModel.displayName)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(Color(hex: "8B949E"))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "1C1C1F"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(hex: "30363D"), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            DeepgramModelPopover(selectedModel: $appState.deepgramModel)
        }
    }
}

struct DeepgramModelPopover: View {
    @Binding var selectedModel: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcription Model")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(hex: "E6EDF3"))
            
            ForEach(DeepgramModel.allCases, id: \.self) { model in
                Button {
                    selectedModel = model.rawValue
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(model.displayName)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color(hex: "E6EDF3"))
                            
                            Spacer()
                            
                            if selectedModel == model.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color(hex: "3FB950"))
                            }
                        }
                        
                        Text(model.shortDescription)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(hex: "8B949E"))
                        
                        // Pros
                        HStack(alignment: .top, spacing: 4) {
                            Text("+")
                                .foregroundStyle(Color(hex: "3FB950"))
                            Text(model.pros.joined(separator: ", "))
                                .foregroundStyle(Color(hex: "8B949E"))
                        }
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        
                        // Cons
                        HStack(alignment: .top, spacing: 4) {
                            Text("-")
                                .foregroundStyle(Color(hex: "F85149"))
                            Text(model.cons.joined(separator: ", "))
                                .foregroundStyle(Color(hex: "8B949E"))
                        }
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedModel == model.rawValue ? Color(hex: "1C1C1F") : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(selectedModel == model.rawValue ? Color(hex: "3FB950").opacity(0.3) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 280)
        .background(Color(hex: "0F0F11"))
    }
}

// MARK: - Source Waveform (per-source mini waveform)

struct SourceWaveform: View {
    let level: Float
    let color: Color
    let bandCount: Int
    let barWidth: CGFloat
    let maxHeight: CGFloat
    
    init(level: Float, color: Color, bandCount: Int = 5, barWidth: CGFloat = 3, maxHeight: CGFloat = 18) {
        self.level = level
        self.color = color
        self.bandCount = bandCount
        self.barWidth = barWidth
        self.maxHeight = maxHeight
    }
    
    @State private var bands: [CGFloat] = []
    @State private var previousLevel: CGFloat = 0
    
    let timer = Timer.publish(every: 0.06, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<bandCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color.opacity(0.5 + (index < bands.count ? bands[index] : 0.05) * 0.5))
                    .frame(width: barWidth, height: max(2, maxHeight * (index < bands.count ? bands[index] : 0.05)))
            }
        }
        .onAppear {
            bands = Array(repeating: 0.05, count: bandCount)
        }
        .onReceive(timer) { _ in
            guard bands.count == bandCount else { return }
            withAnimation(.linear(duration: 0.06)) {
                let rawLevel = CGFloat(max(level, 0.0001))
                // Aggressive power curve for quiet mics (~0.003 RMS typical)
                // 0.003 → 0.44, 0.01 → 0.54, 0.05 → 0.66, 0.1 → 0.72, 0.3 → 0.84
                let amplified = min(1.0, pow(rawLevel, 0.15))
                let delta = amplified - previousLevel
                previousLevel = amplified
                
                // Distribute across bands with variation
                for i in 0..<bandCount {
                    let position = CGFloat(i) / CGFloat(bandCount - 1) // 0..1
                    let bassWeight = 1.0 - position * 0.4
                    let transientWeight = position * 3.0
                    let smoothFactor = 0.4 - position * 0.25
                    let target = amplified * bassWeight + abs(delta) * transientWeight + CGFloat.random(in: 0...0.1)
                    bands[i] = smooth(bands[i], to: target, factor: max(0.1, smoothFactor))
                    bands[i] = min(1.0, max(0.05, bands[i]))
                }
            }
        }
    }
    
    private func smooth(_ current: CGFloat, to target: CGFloat, factor: CGFloat) -> CGFloat {
        current + (target - current) * factor
    }
}

// MARK: - Audio Source Panel (home screen pre-flight)

struct AudioSourcePanel: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 12) {
            AudioSourcePill(
                label: "mic",
                icon: "mic.fill",
                isEnabled: $appState.captureMicrophone,
                isActive: appState.audioCaptureService?.isMicActive ?? false,
                level: appState.microphoneLevel,
                color: Color(hex: "3FB950")
            )
            
            AudioSourcePill(
                label: "system",
                icon: "speaker.wave.2.fill",
                isEnabled: $appState.captureSystemAudio,
                isActive: appState.audioCaptureService?.isSystemAudioActive ?? false,
                level: appState.systemAudioLevel,
                color: Color(hex: "58A6FF")
            )
        }
        .onAppear {
            appState.startAudioMonitoring()
        }
        .onDisappear {
            appState.stopAudioMonitoring()
        }
    }
}

struct AudioSourcePill: View {
    let label: String
    let icon: String
    @Binding var isEnabled: Bool
    let isActive: Bool
    let level: Float
    let color: Color
    
    @EnvironmentObject var appState: AppState
    @State private var isHovering = false
    
    var body: some View {
        Button {
            isEnabled.toggle()
            appState.restartAudioMonitoring()
        } label: {
            HStack(spacing: 6) {
                // Waveform or status dot
                if isEnabled && appState.isMonitoring && isActive {
                    SourceWaveform(level: level, color: color, bandCount: 5, barWidth: 2, maxHeight: 12)
                        .frame(width: 16, height: 12)
                } else {
                    Circle()
                        .fill(isEnabled ? color.opacity(0.5) : Color(hex: "71717A"))
                        .frame(width: 6, height: 6)
                }
                
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(isEnabled ? Color(hex: "D4D4D8") : Color(hex: "71717A"))
                
                Text(isEnabled ? "on" : "off")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(isEnabled ? color.opacity(0.8) : Color(hex: "71717A").opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color(hex: "0F0F11"))
                    .overlay(
                        Capsule()
                            .stroke(
                                isEnabled
                                    ? color.opacity(isHovering ? 0.5 : 0.3)
                                    : Color(hex: "3F3F46").opacity(isHovering ? 0.8 : 0.5),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Update Available Banner

struct UpdateAvailableBanner: View {
    let versionInfo: MinitiAPIService.VersionInfo
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(ColorPalette.Accent.blue)
            
            Text("v\(versionInfo.latestVersion) available")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(ColorPalette.Accent.blue)
            
            if let notes = versionInfo.releaseNotes, !notes.isEmpty {
                Text("— \(notes)")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "58A6FF").opacity(0.7))
                    .lineLimit(1)
            }
            
            Spacer()
            
            Link(destination: URL(string: versionInfo.downloadUrl)!) {
                Text("download")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ColorPalette.Accent.blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: "58A6FF").opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(hex: "58A6FF").opacity(0.2), lineWidth: 1)
                )
        )
    }
}

#Preview {
    MeetingView()
        .environmentObject(AppState())
        .frame(width: 900, height: 600)
}
