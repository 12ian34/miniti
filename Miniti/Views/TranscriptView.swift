import SwiftUI

struct TranscriptView: View {
    @EnvironmentObject var appState: AppState
    
    // Filter out empty segments
    private var visibleSegments: [AppState.LiveSegment] {
        appState.liveSegments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    
    private var hasInterimText: Bool {
        !appState.interimText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // Get unique speakers - combine from segments and detected speakers
    private var uniqueSpeakers: [Int] {
        var speakers = appState.detectedSpeakers
        for segment in visibleSegments {
            speakers.insert(segment.speaker)
        }
        return speakers.sorted()
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
    
    // Check if this segment starts a new speaker turn
    private func isNewSpeakerTurn(at index: Int) -> Bool {
        guard index > 0 else { return true }
        let segments = visibleSegments
        return segments[index].speaker != segments[index - 1].speaker
    }
    
    var body: some View {
        Group {
            if visibleSegments.isEmpty && !hasInterimText && !appState.isRecording {
                EmptyTranscriptView()
            } else {
                VStack(spacing: 0) {
                    // Speaker legend (show when recording or has segments)
                    if appState.isRecording || !visibleSegments.isEmpty {
                        SpeakerLegend(speakers: uniqueSpeakers, isRecording: appState.isRecording)
                    }
                    
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(visibleSegments.enumerated()), id: \.element.id) { index, segment in
                                    TerminalSegmentRow(
                                        segment: segment,
                                        isNewTurn: isNewSpeakerTurn(at: index)
                                    )
                                    .id(segment.id)
                                }
                                
                                // Interim (live typing) text
                                if hasInterimText {
                                    TerminalInterimRow(
                                        text: appState.interimText,
                                        speaker: appState.interimSpeaker ?? appState.currentSpeaker,
                                        isNewTurn: visibleSegments.last?.speaker != (appState.interimSpeaker ?? appState.currentSpeaker)
                                    )
                                    .id("interim")
                                }
                                
                                // Bottom anchor for scrolling
                                Color.clear
                                    .frame(height: 20)
                                    .id("bottom")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .scrollIndicators(.hidden)
                        .onChange(of: visibleSegments.count) { _, _ in
                            scrollToBottom(proxy: proxy)
                        }
                        .onChange(of: appState.interimText) { _, _ in
                            scrollToBottom(proxy: proxy)
                        }
                        .onChange(of: appState.isRecording) { _, isRecording in
                            if isRecording {
                                scrollToBottom(proxy: proxy)
                            }
                        }
                    }
                }
            }
        }
        .background(Color(hex: "09090B")) // GitHub dark background
    }
}

// MARK: - Speaker Legend

struct SpeakerLegend: View {
    let speakers: [Int]
    var isRecording: Bool = false
    
    private let speakerColors: [Color] = [
        Color(hex: "58A6FF"), // Blue
        Color(hex: "A371F7"), // Purple  
        Color(hex: "3FB950"), // Green
        Color(hex: "D29922"), // Orange
        Color(hex: "F778BA"), // Pink
        Color(hex: "79C0FF"), // Cyan
        Color(hex: "FFA657"), // Light orange
        Color(hex: "7EE787"), // Light green
    ]
    
    var body: some View {
        HStack(spacing: 16) {
            // Recording indicator
            if isRecording {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(hex: "F85149"))
                        .frame(width: 6, height: 6)
                    Text("live")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(hex: "F85149"))
                }
            }
            
            Text("speakers:")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: "484F58"))
            
            if speakers.isEmpty {
                Text("detecting...")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: "484F58"))
            } else {
                ForEach(speakers, id: \.self) { speaker in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(speakerColors[speaker % speakerColors.count])
                            .frame(width: 6, height: 6)
                        Text("S\(speaker + 1)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(speakerColors[speaker % speakerColors.count])
                    }
                }
            }
            
            Spacer()
            
            // Show count
            if speakers.count == 1 && !speakers.isEmpty {
                Text("(single speaker)")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "484F58"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(hex: "0F0F11"))
        .overlay(
            Rectangle()
                .fill(Color(hex: "1C1C1F"))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

// MARK: - Terminal Style Components

struct TerminalSegmentRow: View {
    let segment: AppState.LiveSegment
    var isNewTurn: Bool = true
    
    private let speakerColors: [Color] = [
        Color(hex: "58A6FF"), // Blue
        Color(hex: "A371F7"), // Purple
        Color(hex: "3FB950"), // Green
        Color(hex: "D29922"), // Orange
        Color(hex: "F778BA"), // Pink
        Color(hex: "79C0FF"), // Cyan
        Color(hex: "FFA657"), // Light orange
        Color(hex: "7EE787"), // Light green
    ]
    
    private var speakerColor: Color {
        speakerColors[segment.speaker % speakerColors.count]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Speaker turn indicator
            if isNewTurn {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(speakerColor)
                        .frame(width: 3, height: 12)
                        .cornerRadius(1.5)
                    
                    Text("Speaker \(segment.speaker + 1)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(speakerColor)
                    
                    Text("•")
                        .foregroundStyle(Color(hex: "1C1C1F"))
                    
                    Text(formatTimestamp(segment.timestamp))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(hex: "484F58"))
                }
                .padding(.top, isNewTurn ? 12 : 0)
                .padding(.bottom, 4)
            }
            
            // Message content
            HStack(alignment: .top, spacing: 0) {
                // Left border indicator
                Rectangle()
                    .fill(speakerColor.opacity(0.3))
                    .frame(width: 2)
                    .padding(.leading, 0)
                
                // Message text
                Text(segment.text)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "E6EDF3"))
                    .textSelection(.enabled)
                    .padding(.leading, 12)
                    .padding(.vertical, 4)
            }
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(y: 10)),
            removal: .opacity
        ))
    }
    
    private func formatTimestamp(_ timestamp: TimeInterval) -> String {
        let minutes = Int(timestamp) / 60
        let seconds = Int(timestamp) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct TerminalInterimRow: View {
    let text: String
    let speaker: Int
    var isNewTurn: Bool = true
    
    @State private var cursorVisible = true
    
    private let speakerColors: [Color] = [
        Color(hex: "58A6FF"),
        Color(hex: "A371F7"),
        Color(hex: "3FB950"),
        Color(hex: "D29922"),
        Color(hex: "F778BA"),
        Color(hex: "79C0FF"),
        Color(hex: "FFA657"),
        Color(hex: "7EE787"),
    ]
    
    private var speakerColor: Color {
        speakerColors[speaker % speakerColors.count]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Speaker turn indicator (only show if new turn)
            if isNewTurn {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(speakerColor.opacity(0.6))
                        .frame(width: 3, height: 12)
                        .cornerRadius(1.5)
                    
                    Text("Speaker \(speaker + 1)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(speakerColor.opacity(0.7))
                    
                    Text("•")
                        .foregroundStyle(Color(hex: "1C1C1F"))
                    
                    Text("listening...")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(hex: "3FB950").opacity(0.7))
                }
                .padding(.top, 12)
                .padding(.bottom, 4)
            }
            
            // Message content
            HStack(alignment: .top, spacing: 0) {
                // Left border indicator (pulsing for interim)
                Rectangle()
                    .fill(speakerColor.opacity(0.5))
                    .frame(width: 2)
                
                // Live text with cursor
                HStack(spacing: 0) {
                    Text(text)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(hex: "8B949E"))
                    
                    // Blinking cursor
                    Text("▊")
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(speakerColor)
                        .opacity(cursorVisible ? 1 : 0)
                }
                .padding(.leading, 12)
                .padding(.vertical, 4)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                cursorVisible.toggle()
            }
        }
    }
}

struct EmptyTranscriptView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 16) {
            // ASCII art style icon
            Text("⬢")
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .foregroundStyle(Color(hex: "1C1C1F"))
            
            Text("ready_to_transcribe")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: "8B949E"))
            
            Text("$ take notes --capture=audio")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(Color(hex: "484F58"))
            
            if appState.deepgramApiKey.isEmpty {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Text("⚠")
                            .foregroundStyle(Color(hex: "D29922"))
                        Text("error: deepgram_api_key not set")
                            .foregroundStyle(Color(hex: "F85149"))
                    }
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    
                    Button {
                        appState.showSettings = true
                    } label: {
                        Text("[ configure ]")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(hex: "58A6FF"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(hex: "58A6FF").opacity(0.1))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "09090B"))
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Previews

#Preview("With Content") {
    let appState = AppState()
    appState.liveSegments = [
        .init(id: UUID(), text: "Hey everyone, thanks for joining today's meeting.", speaker: 0, timestamp: 0, isFinal: true),
        .init(id: UUID(), text: "I wanted to go over the quarterly goals first.", speaker: 0, timestamp: 5, isFinal: true),
        .init(id: UUID(), text: "Happy to be here. So what's on the agenda?", speaker: 1, timestamp: 10, isFinal: true),
        .init(id: UUID(), text: "We need to discuss the new API integration and timeline.", speaker: 0, timestamp: 18, isFinal: true),
        .init(id: UUID(), text: "I've been looking at the documentation and it seems straightforward.", speaker: 1, timestamp: 25, isFinal: true),
        .init(id: UUID(), text: "I have some concerns about the authentication flow.", speaker: 2, timestamp: 32, isFinal: true),
    ]
    appState.interimText = "I think we should prioritize the auth"
    appState.currentSpeaker = 0
    appState.interimSpeaker = 0
    
    return TranscriptView()
        .environmentObject(appState)
        .frame(width: 700, height: 500)
}

#Preview("Single Speaker") {
    let appState = AppState()
    appState.liveSegments = [
        .init(id: UUID(), text: "Welcome to the product update.", speaker: 0, timestamp: 0, isFinal: true),
        .init(id: UUID(), text: "Today I'll cover three main topics.", speaker: 0, timestamp: 5, isFinal: true),
    ]
    
    return TranscriptView()
        .environmentObject(appState)
        .frame(width: 700, height: 400)
}

#Preview("Empty") {
    TranscriptView()
        .environmentObject(AppState())
        .frame(width: 700, height: 400)
}
