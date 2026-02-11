import SwiftUI
import SwiftData

struct HistoryView_iOS: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.startTime, order: .reverse) private var meetings: [Meeting]
    @State private var searchText = ""
    
    var filteredMeetings: [Meeting] {
        if searchText.isEmpty {
            return meetings
        }
        return meetings.filter { meeting in
            meeting.title.localizedCaseInsensitiveContains(searchText) ||
            meeting.fullTranscript.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if filteredMeetings.isEmpty {
                    emptyState
                } else {
                    meetingsList
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search meetings...")
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("◌")
                .font(.system(size: 48, weight: .ultraLight, design: .monospaced))
                .foregroundStyle(ColorPalette.Text.disabled)
            Text("No sessions yet")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(ColorPalette.Text.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorPalette.Background.primary)
    }
    
    // MARK: - Meetings List
    
    private var meetingsList: some View {
        List {
            ForEach(filteredMeetings) { meeting in
                NavigationLink(value: meeting) {
                    MeetingRow_iOS(meeting: meeting)
                }
            }
            .onDelete(perform: deleteMeetings)
        }
        .listStyle(.plain)
        .navigationDestination(for: Meeting.self) { meeting in
            MeetingDetail_iOS(meeting: meeting)
        }
    }
    
    private func deleteMeetings(at offsets: IndexSet) {
        for index in offsets {
            let meeting = filteredMeetings[index]
            modelContext.delete(meeting)
        }
        try? modelContext.save()
    }
}

// MARK: - Meeting Row

struct MeetingRow_iOS: View {
    let meeting: Meeting
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meeting.title)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(ColorPalette.Text.primary)
                .lineLimit(1)
            
            HStack(spacing: 8) {
                Text(meeting.startTime.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ColorPalette.Text.muted)
                
                if !meeting.segments.isEmpty {
                    Text("·")
                        .foregroundStyle(ColorPalette.Text.disabled)
                    Text("\(meeting.segments.count) segments")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ColorPalette.Text.muted)
                }
                
                if meeting.summaryText != nil {
                    Text("·")
                        .foregroundStyle(ColorPalette.Text.disabled)
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundStyle(ColorPalette.Accent.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Meeting Detail

struct MeetingDetail_iOS: View {
    let meeting: Meeting
    @State private var activeSection: DetailSection = .transcript
    
    enum DetailSection: String, CaseIterable {
        case transcript = "Transcript"
        case insights = "Insights"
        case notes = "Notes"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Section picker
            Picker("Section", selection: $activeSection) {
                ForEach(DetailSection.allCases, id: \.self) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Content
            Group {
                switch activeSection {
                case .transcript:
                    transcriptContent
                case .insights:
                    insightsContent
                case .notes:
                    notesContent
                }
            }
        }
        .navigationTitle(meeting.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = meetingAsMarkdown()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
            }
        }
    }
    
    // MARK: - Transcript
    
    private var transcriptContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if meeting.segments.isEmpty {
                    Text("No transcript available")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(ColorPalette.Text.muted)
                        .padding()
                } else {
                    ForEach(meeting.segments.sorted(by: { $0.timestamp < $1.timestamp })) { segment in
                        let isMic = segment.speaker == DeepgramService.micSpeakerID
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isMic ? "You" : segment.speakerLabel)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(isMic ? ColorPalette.Speaker.mic : speakerColor(segment.speaker))
                            
                            Text(segment.text)
                                .font(.system(size: 14))
                                .foregroundStyle(ColorPalette.Text.primary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.vertical)
        }
    }
    
    // MARK: - Insights
    
    private var insightsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let summary = meeting.summaryText, !summary.isEmpty {
                    DetailBlock(title: "Summary", content: summary)
                }
                
                if !meeting.discussionFlow.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Discussion Flow")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(ColorPalette.Text.secondary)
                        
                        ForEach(Array(meeting.discussionFlow.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .top, spacing: 6) {
                                Text("\(index + 1).")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(ColorPalette.Text.muted)
                                Text(item)
                                    .font(.system(size: 13))
                                    .foregroundStyle(ColorPalette.Text.primary)
                            }
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(ColorPalette.Background.secondary)
                    )
                }
                
                if !meeting.actionItems.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Action Items")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(ColorPalette.Text.secondary)
                        
                        ForEach(meeting.actionItems, id: \.self) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "circle")
                                    .font(.system(size: 8))
                                    .foregroundStyle(ColorPalette.Accent.blue)
                                    .padding(.top, 4)
                                Text(item)
                                    .font(.system(size: 13))
                                    .foregroundStyle(ColorPalette.Text.primary)
                            }
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(ColorPalette.Background.secondary)
                    )
                }
                
                if !meeting.topics.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Topics")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(ColorPalette.Text.secondary)
                        
                        FlowLayout_iOS(items: meeting.topics) { topic in
                            Text(topic)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(ColorPalette.Text.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(ColorPalette.Background.tertiary)
                                )
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(ColorPalette.Background.secondary)
                    )
                }
                
                if !hasInsights {
                    Text("No insights available")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(ColorPalette.Text.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                }
            }
            .padding()
        }
    }
    
    private var hasInsights: Bool {
        (meeting.summaryText != nil && !meeting.summaryText!.isEmpty) ||
        !meeting.actionItems.isEmpty ||
        !meeting.topics.isEmpty ||
        !meeting.discussionFlow.isEmpty
    }
    
    // MARK: - Notes
    
    private var notesContent: some View {
        ScrollView {
            if !meeting.notes.isEmpty {
                Text(meeting.notes)
                    .font(.system(size: 14))
                    .foregroundStyle(ColorPalette.Text.primary)
                    .padding()
            } else {
                Text("No notes")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(ColorPalette.Text.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func speakerColor(_ speaker: Int) -> Color {
        let remoteColors = ColorPalette.Speaker.remote
        let index = speaker % remoteColors.count
        return remoteColors[index]
    }
    
    private func meetingAsMarkdown() -> String {
        var md = "# \(meeting.title)\n\n"
        md += "_\(meeting.startTime.formatted(date: .long, time: .shortened))_\n\n"
        
        if !meeting.segments.isEmpty {
            md += "## Transcript\n\n"
            var currentSpeaker: Int? = nil
            for segment in meeting.segments.sorted(by: { $0.timestamp < $1.timestamp }) {
                if segment.speaker != currentSpeaker {
                    currentSpeaker = segment.speaker
                    md += "\n**\(segment.speakerLabel):**\n"
                }
                md += "\(segment.text) "
            }
            md += "\n\n"
        }
        
        if let summary = meeting.summaryText, !summary.isEmpty {
            md += "## Summary\n\n\(summary)\n\n"
        }
        
        if !meeting.actionItems.isEmpty {
            md += "## Action Items\n\n"
            for item in meeting.actionItems {
                md += "- [ ] \(item)\n"
            }
            md += "\n"
        }
        
        return md
    }
}

// MARK: - Detail Block

struct DetailBlock: View {
    let title: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(ColorPalette.Text.secondary)
            
            Text(content)
                .font(.system(size: 13))
                .foregroundStyle(ColorPalette.Text.primary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(ColorPalette.Background.secondary)
        )
    }
}

// MARK: - Flow Layout

struct FlowLayout_iOS<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content
    
    var body: some View {
        // Simple wrapping layout using ViewThatFits isn't available pre-iOS 16.
        // Use a basic VStack with HStacks for simplicity.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}
