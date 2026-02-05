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
                            
                            // Notes (bottom) - compact, resizable
                            VStack(spacing: 0) {
                                SectionHeader(title: "notes", icon: "✎", shortcut: "⌘⇧N", onCopy: {
                                    "## Notes\n\n\(appState.liveNotes)"
                                })
                                NotesEditor()
                            }
                            .frame(minHeight: 70)
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
    @State private var showDeepgramKey = false
    @State private var showOpenAIKey = false
    
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
            
            // API Key inputs
            VStack(spacing: 12) {
                APIKeyInput(
                    label: "deepgram",
                    key: $appState.deepgramApiKey,
                    showKey: $showDeepgramKey,
                    placeholder: "dg_..."
                )
                
                APIKeyInput(
                    label: "openai",
                    key: $appState.openaiApiKey,
                    showKey: $showOpenAIKey,
                    placeholder: "sk-..."
                )
            }
            .frame(width: 320)
            
            // Model selector
            VStack(spacing: 8) {
                Text("model")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: "484F58"))
                    .tracking(1)
                
                HomeModelSelector()
            }
            
            // Start button
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
                        .fill(appState.deepgramApiKey.isEmpty ? Color(hex: "484F58") : Color(hex: "3FB950"))
                )
            }
            .buttonStyle(.plain)
            .disabled(appState.deepgramApiKey.isEmpty)
            
            // Keyboard shortcut hint
            ShortcutHint(keys: "⌘/", label: "all shortcuts")
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - API Key Input

struct APIKeyInput: View {
    let label: String
    @Binding var key: String
    @Binding var showKey: Bool
    let placeholder: String
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Label with status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(key.isEmpty ? Color(hex: "71717A") : Color(hex: "3FB950"))
                    .frame(width: 6, height: 6)
                
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: "A1A1AA"))
            }
            .frame(width: 80, alignment: .leading)
            
            // Key input
            HStack(spacing: 8) {
                Group {
                    if showKey {
                        TextField(placeholder, text: $key)
                    } else {
                        SecureField(placeholder, text: $key)
                    }
                }
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(Color(hex: "E6EDF3"))
                .textFieldStyle(.plain)
                .focused($isFocused)
                
                // Toggle visibility
                Button {
                    showKey.toggle()
                } label: {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: "52525B"))
                }
                .buttonStyle(.plain)
                
                // Status checkmark
                if !key.isEmpty {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(hex: "3FB950"))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: "18181B"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isFocused ? Color(hex: "3FB950").opacity(0.5) : Color(hex: "27272A"), lineWidth: 1)
            )
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
                Text("Add your notes here...")
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
                
                // Status indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(appState.isRecording ? Color(hex: "F85149") : Color(hex: "1C1C1F"))
                        .frame(width: 8, height: 8)
                        .shadow(color: appState.isRecording ? Color(hex: "F85149").opacity(0.5) : .clear, radius: 4)
                    
                    if appState.isRecording {
                        Text(appState.formattedDuration)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(hex: "F85149"))
                    }
                }
                
                // Model selector (only before recording)
                if !appState.isRecording {
                    DeepgramModelSelector()
                }
                
                // Record button
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if appState.isRecording {
                            appState.stopRecording()
                        } else {
                            appState.startNewMeeting()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: appState.isRecording ? "stop.fill" : "record.circle")
                                .font(.system(size: 11, weight: .semibold))
                            Text(appState.isRecording ? "stop" : "rec")
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
                
                // Audio waveform (next to record button when recording)
                if appState.isRecording {
                    TerminalAudioMeter()
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

struct TerminalAudioMeter: View {
    @EnvironmentObject var appState: AppState
    
    // Frequency bands: sub-bass, bass, low-mid, mid, high-mid, presence, brilliance
    @State private var bands: [CGFloat] = Array(repeating: 0.05, count: 7)
    @State private var previousLevel: CGFloat = 0
    
    let timer = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(bandColor(for: index, level: bands[index]))
                    .frame(width: 4, height: max(3, 24 * bands[index]))
            }
        }
        .onReceive(timer) { _ in
            if appState.isRecording {
                withAnimation(.linear(duration: 0.03)) {
                    let rawLevel = CGFloat(appState.audioLevel)
                    // Much more sensitive - amplify significantly
                    let amplified = min(1.0, rawLevel * 15.0)
                    let delta = amplified - previousLevel
                    previousLevel = amplified
                    
                    // Simulate frequency distribution based on level and variation
                    // Lower frequencies (bass) respond more to sustained levels
                    // Higher frequencies respond more to transients/changes
                    bands[0] = smooth(bands[0], to: amplified * 0.9 + CGFloat.random(in: 0...0.15), factor: 0.4)  // Sub-bass
                    bands[1] = smooth(bands[1], to: amplified * 0.95 + CGFloat.random(in: 0...0.1), factor: 0.35) // Bass
                    bands[2] = smooth(bands[2], to: amplified + CGFloat.random(in: 0...0.12), factor: 0.3)       // Low-mid
                    bands[3] = smooth(bands[3], to: amplified * 1.1 + abs(delta) * 2, factor: 0.25)              // Mid
                    bands[4] = smooth(bands[4], to: amplified * 0.85 + abs(delta) * 3, factor: 0.2)              // High-mid
                    bands[5] = smooth(bands[5], to: amplified * 0.7 + abs(delta) * 4, factor: 0.15)              // Presence
                    bands[6] = smooth(bands[6], to: amplified * 0.5 + abs(delta) * 5, factor: 0.1)               // Brilliance
                    
                    // Clamp all values
                    for i in 0..<bands.count {
                        bands[i] = min(1.0, max(0.05, bands[i]))
                    }
                }
            } else {
                withAnimation(.linear(duration: 0.15)) {
                    for i in 0..<bands.count {
                        bands[i] = 0.05
                    }
                    previousLevel = 0
                }
            }
        }
    }
    
    private func smooth(_ current: CGFloat, to target: CGFloat, factor: CGFloat) -> CGFloat {
        return current + (target - current) * factor
    }
    
    private func bandColor(for index: Int, level: CGFloat) -> Color {
        // Gradient from green (bass) to yellow (mid) to orange/red (highs)
        let colors: [Color] = [
            Color(hex: "22C55E"),  // Green - sub-bass
            Color(hex: "3FB950"),  // Green - bass
            Color(hex: "84CC16"),  // Lime - low-mid
            Color(hex: "EAB308"),  // Yellow - mid
            Color(hex: "F59E0B"),  // Amber - high-mid
            Color(hex: "F97316"),  // Orange - presence
            Color(hex: "EF4444"),  // Red - brilliance
        ]
        
        // Brighten based on level
        if level > 0.7 {
            return colors[index].opacity(1.0)
        }
        return colors[index].opacity(0.7 + level * 0.3)
    }
}

#Preview {
    MeetingView()
        .environmentObject(AppState())
        .frame(width: 900, height: 600)
}
