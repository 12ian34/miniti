import SwiftUI

struct TranscriptView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.interfaceScale) private var interfaceScale
    @State private var isAutoScrollEnabled = true
    @State private var previousBottomDistance: CGFloat = 0
    @State private var hasCapturedInitialBottomDistance = false
    @State private var suppressAutoScrollLockUntil = Date.distantPast
    @State private var cachedSourceSegments: [AppState.LiveSegment] = []
    @State private var cachedVisibleSegmentCount = 0
    @State private var cachedVisibleSpeakers: Set<Int> = []
    @State private var cachedDisplayTurns: [SelectableAttributed.TranscriptTurn] = []
    @State private var cachedTurnStartOffsets: [Int] = []
    @State private var cachedTranscript = NSAttributedString()
    @State private var cachedTranscriptMutation: SelectableTextMutation?
    @State private var cachedTranscriptRevision: UInt64 = 0
    @State private var cachedLastDisplaySpeaker: Int?
    @State private var cachedUniqueSpeakers: [Int] = []
    @State private var interimText: String = ""
    @State private var currentSpeaker: Int = 0
    @State private var interimSpeaker: Int? = nil
    @State private var renamingSpeaker: Int? = nil

    private var hasInterimText: Bool {
        !interimText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func rebuildSegmentCaches(
        liveSegments: [AppState.LiveSegment],
        detectedSpeakers: Set<Int>,
        forceFullRebuild: Bool = false
    ) {
        let names = appState.liveSpeakerNames
        let selfIDs = appState.liveSelfSpeakerIDs
        let canAppend = !forceFullRebuild
            && !cachedSourceSegments.isEmpty
            && liveSegments.count > cachedSourceSegments.count
            && liveSegments.first == cachedSourceSegments.first
            && liveSegments[cachedSourceSegments.count - 1] == cachedSourceSegments.last

        if canAppend {
            let appended = liveSegments.dropFirst(cachedSourceSegments.count).filter {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if !appended.isEmpty, !cachedDisplayTurns.isEmpty,
               let replacementStart = cachedTurnStartOffsets.last {
                let oldTurnCount = cachedDisplayTurns.count
                var updatedTurns = cachedDisplayTurns
                for segment in appended {
                    let next = SelectableAttributed.TranscriptTurn(
                        speaker: segment.speaker,
                        timestamp: segment.timestamp,
                        text: segment.text
                    )
                    let mergedTail = SelectableAttributed.mergeTurns(
                        [updatedTurns[updatedTurns.count - 1], next],
                        speakerNames: names,
                        selfIDs: selfIDs
                    )
                    if mergedTail.count == 1 {
                        updatedTurns[updatedTurns.count - 1] = mergedTail[0]
                    } else {
                        updatedTurns.append(next)
                    }
                }

                let tailStartIndex = oldTurnCount - 1
                let tailDocument = SelectableAttributed.transcriptDocument(
                    turns: Array(updatedTurns[tailStartIndex...]),
                    speakerNames: names,
                    selfIDs: selfIDs,
                    bodyFontSize: interfaceScale.transcriptBodySize,
                    headerFontSize: interfaceScale.transcriptHeaderSize,
                    lineSpacing: interfaceScale.transcriptLineSpacing,
                    startsAtDocumentBeginning: tailStartIndex == 0
                )
                let replacementRange = NSRange(
                    location: replacementStart,
                    length: cachedTranscript.length - replacementStart
                )
                let updatedTranscript = NSMutableAttributedString(attributedString: cachedTranscript)
                updatedTranscript.replaceCharacters(
                    in: replacementRange,
                    with: tailDocument.attributed
                )

                cachedTranscriptRevision &+= 1
                cachedTranscriptMutation = SelectableTextMutation(
                    revision: cachedTranscriptRevision,
                    range: replacementRange,
                    replacement: tailDocument.attributed
                )
                cachedTranscript = NSAttributedString(attributedString: updatedTranscript)
                cachedDisplayTurns = Array(updatedTurns[..<tailStartIndex]) + tailDocument.turns
                cachedTurnStartOffsets = Array(cachedTurnStartOffsets[..<tailStartIndex])
                    + tailDocument.turnStartOffsets.map { replacementStart + $0 }
                cachedVisibleSegmentCount += appended.count
                for segment in appended { cachedVisibleSpeakers.insert(segment.speaker) }
            } else if !appended.isEmpty {
                rebuildAllSegments(liveSegments, names: names, selfIDs: selfIDs)
            }
        } else {
            rebuildAllSegments(liveSegments, names: names, selfIDs: selfIDs)
        }

        cachedSourceSegments = liveSegments
        cachedLastDisplaySpeaker = cachedDisplayTurns.last?.speaker
        updateUniqueSpeakers(detectedSpeakers)
    }

    private func rebuildAllSegments(
        _ liveSegments: [AppState.LiveSegment],
        names: [String: String],
        selfIDs: Set<Int>
    ) {
        let visible = liveSegments.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let document = SelectableAttributed.transcriptDocument(
            turns: visible.map {
                .init(speaker: $0.speaker, timestamp: $0.timestamp, text: $0.text)
            },
            speakerNames: names,
            selfIDs: selfIDs,
            bodyFontSize: interfaceScale.transcriptBodySize,
            headerFontSize: interfaceScale.transcriptHeaderSize,
            lineSpacing: interfaceScale.transcriptLineSpacing
        )
        cachedVisibleSegmentCount = visible.count
        cachedVisibleSpeakers = Set(visible.map(\.speaker))
        cachedDisplayTurns = document.turns
        cachedTurnStartOffsets = document.turnStartOffsets
        cachedTranscript = document.attributed
        cachedTranscriptMutation = nil
    }

    private func updateUniqueSpeakers(_ detectedSpeakers: Set<Int>) {
        let speakers = detectedSpeakers.union(cachedVisibleSpeakers)
        let effectiveSelves = appState.effectiveLiveSelfSpeakerIDs
        cachedUniqueSpeakers = speakers.sorted { a, b in
            let aSelf = effectiveSelves.contains(a)
            let bSelf = effectiveSelves.contains(b)
            if aSelf != bSelf { return aSelf }
            return a < b
        }
    }

    private func syncRuntimeSnapshot() {
        let runtime = appState.transcriptRuntime
        interimText = runtime.interimText
        currentSpeaker = runtime.currentSpeaker
        interimSpeaker = runtime.interimSpeaker
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private func suppressAutoScrollLockBriefly(_ duration: TimeInterval = 0.25) {
        suppressAutoScrollLockUntil = Date().addingTimeInterval(duration)
    }

    private func updateAutoScrollLock(bottomAnchorMaxY: CGFloat, viewportHeight: CGFloat) {
        let distanceFromBottom = max(0, bottomAnchorMaxY - viewportHeight)

        guard hasCapturedInitialBottomDistance else {
            previousBottomDistance = distanceFromBottom
            hasCapturedInitialBottomDistance = true
            return
        }

        let movedAwayFromBottom = distanceFromBottom - previousBottomDistance
        if isAutoScrollEnabled,
           Date() >= suppressAutoScrollLockUntil,
           movedAwayFromBottom > 0.5,
           distanceFromBottom > 24 {
            isAutoScrollEnabled = false
        }

        previousBottomDistance = distanceFromBottom
    }
    
    // Check if this segment starts a new speaker turn
    private func isNewSpeakerTurn(at index: Int, in segments: [AppState.LiveSegment]) -> Bool {
        guard index > 0 else { return true }
        return segments[index].speaker != segments[index - 1].speaker
    }

    @ViewBuilder
    private func renameSpeakerView(for speakerID: Int) -> some View {
        let key = String(speakerID)
        let currentName = appState.liveSpeakerNames[key]
        let defaultName = resolvedSpeakerLabel(for: speakerID, names: nil, selfIDs: appState.liveSelfSpeakerIDs)
        let isSelf = appState.effectiveLiveSelfSpeakerIDs.contains(speakerID)
        let hasOtherSelves = appState.effectiveLiveSelfSpeakerIDs.subtracting([speakerID]).isEmpty == false
        RenameSpeakerView(
            speakerID: speakerID,
            currentName: currentName,
            defaultName: defaultName,
            isSelf: isSelf,
            hasOtherSelves: hasOtherSelves,
            onSave: { newName in
                appState.setLiveSpeakerName(id: speakerID, name: newName)
                renamingSpeaker = nil
            },
            onClear: {
                appState.setLiveSpeakerName(id: speakerID, name: nil)
                renamingSpeaker = nil
            },
            onMarkAsSelf: {
                appState.setLiveSelfSpeaker(id: speakerID, isSelf: true)
                renamingSpeaker = nil
            },
            onUnmarkAsSelf: {
                appState.setLiveSelfSpeaker(id: speakerID, isSelf: false)
                renamingSpeaker = nil
            },
            onCancel: {
                renamingSpeaker = nil
            }
        )
    }

    var body: some View {
        Group {
            if cachedVisibleSegmentCount == 0 && !hasInterimText && !appState.isRecording {
                EmptyTranscriptView()
            } else {
                VStack(spacing: 0) {
                    // Speaker legend (show when recording or has segments)
                    if appState.isRecording || cachedVisibleSegmentCount > 0 {
                        SpeakerLegend(
                            speakers: cachedUniqueSpeakers,
                            isRecording: appState.isRecording,
                            speakerNames: appState.liveSpeakerNames,
                            selfIDs: appState.liveSelfSpeakerIDs,
                            onRename: { renamingSpeaker = $0 }
                        )
                        #if os(macOS)
                        .popover(item: Binding(
                            get: { renamingSpeaker.map { SpeakerRenameTarget(id: $0) } },
                            set: { renamingSpeaker = $0?.id }
                        )) { target in
                            renameSpeakerView(for: target.id)
                        }
                        #else
                        .sheet(item: Binding(
                            get: { renamingSpeaker.map { SpeakerRenameTarget(id: $0) } },
                            set: { renamingSpeaker = $0?.id }
                        )) { target in
                            renameSpeakerView(for: target.id)
                                .presentationDetents([.height(260)])
                                .presentationBackground(ColorPalette.Background.primary)
                        }
                        #endif
                    }
                    
                    ScrollViewReader { proxy in
                        GeometryReader { scrollGeometry in
                            ZStack(alignment: .bottomTrailing) {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 6) {
                                        if cachedTranscript.length > 0 {
                                            SelectableTextView(
                                                cachedTranscript,
                                                mutation: cachedTranscriptMutation
                                            )
                                            .id("transcript")
                                        }

                                        // Interim (live typing) text
                                        if hasInterimText {
                                            let interimSpeakerValue = interimSpeaker ?? currentSpeaker
                                            TerminalInterimRow(
                                                text: interimText,
                                                speaker: interimSpeakerValue,
                                                isNewTurn: cachedLastDisplaySpeaker.map {
                                                    SelectableAttributed.displayGroupKey(speaker: $0, names: appState.liveSpeakerNames, selfIDs: appState.liveSelfSpeakerIDs)
                                                    != SelectableAttributed.displayGroupKey(speaker: interimSpeakerValue, names: appState.liveSpeakerNames, selfIDs: appState.liveSelfSpeakerIDs)
                                                } ?? true,
                                                speakerNames: appState.liveSpeakerNames,
                                                selfIDs: appState.liveSelfSpeakerIDs
                                            )
                                            .id("interim")
                                        }
                                        
                                        // Bottom anchor for scrolling
                                        Color.clear
                                            .frame(height: 20)
                                            .id("bottom")
                                            .background(
                                                GeometryReader { geo in
                                                    Color.clear.preference(
                                                        key: TranscriptBottomAnchorMaxYPreferenceKey.self,
                                                        value: geo.frame(in: .named("transcript-scroll")).maxY
                                                    )
                                                }
                                            )
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    #if os(macOS)
                                    .background(
                                        TranscriptScrollWheelObserver(
                                            onScrolledAwayFromBottom: {
                                                if isAutoScrollEnabled,
                                                   Date() >= suppressAutoScrollLockUntil {
                                                    isAutoScrollEnabled = false
                                                }
                                            }
                                        )
                                    )
                                    #endif
                                }
                                .coordinateSpace(name: "transcript-scroll")
                                .scrollIndicators(.hidden)
                                .simultaneousGesture(
                                    DragGesture(minimumDistance: 4)
                                        .onChanged { _ in
                                            if isAutoScrollEnabled {
                                                isAutoScrollEnabled = false
                                            }
                                        }
                                )
                                .onPreferenceChange(TranscriptBottomAnchorMaxYPreferenceKey.self) { bottomAnchorMaxY in
                                    updateAutoScrollLock(
                                        bottomAnchorMaxY: bottomAnchorMaxY,
                                        viewportHeight: scrollGeometry.size.height
                                    )
                                }
                                .onChange(of: cachedVisibleSegmentCount) { _, newCount in
                                    if newCount == 0 {
                                        isAutoScrollEnabled = true
                                        previousBottomDistance = 0
                                    }
                                    guard isAutoScrollEnabled else { return }
                                    suppressAutoScrollLockBriefly()
                                    scrollToBottom(proxy: proxy)
                                }
                                .onChange(of: interimText) { _, _ in
                                    guard isAutoScrollEnabled else { return }
                                    suppressAutoScrollLockBriefly()
                                    scrollToBottom(proxy: proxy)
                                }
                                .onChange(of: appState.isRecording) { _, isRecording in
                                    if isRecording {
                                        isAutoScrollEnabled = true
                                        previousBottomDistance = 0
                                        suppressAutoScrollLockBriefly()
                                        scrollToBottom(proxy: proxy)
                                    }
                                }
                                
                                if !isAutoScrollEnabled {
                                    Text("resume auto-scroll")
                                        .font(.system(size: 10, weight: .semibold, design: .default))
                                        .foregroundStyle(Color(hex: "E6EDF3"))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(ColorPalette.Accent.blue.opacity(0.95))
                                        .clipShape(Capsule())
                                        .onTapGesture {
                                            isAutoScrollEnabled = true
                                            previousBottomDistance = 0
                                            suppressAutoScrollLockBriefly(1.0)
                                            scrollToBottom(proxy: proxy)
                                        }
                                        .padding(.trailing, 16)
                                        .padding(.bottom, 12)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            rebuildSegmentCaches(
                liveSegments: appState.liveSegments,
                detectedSpeakers: appState.detectedSpeakers,
                forceFullRebuild: true
            )
            syncRuntimeSnapshot()
        }
        .onChange(of: appState.liveSegments) { _, newSegments in
            rebuildSegmentCaches(
                liveSegments: newSegments,
                detectedSpeakers: appState.detectedSpeakers
            )
        }
        .onChange(of: appState.detectedSpeakers) { _, newSpeakers in
            updateUniqueSpeakers(newSpeakers)
        }
        .onChange(of: appState.liveSpeakerNames) { _, _ in
            rebuildSegmentCaches(
                liveSegments: appState.liveSegments,
                detectedSpeakers: appState.detectedSpeakers,
                forceFullRebuild: true
            )
        }
        .onChange(of: appState.liveSelfSpeakerIDs) { _, _ in
            rebuildSegmentCaches(
                liveSegments: appState.liveSegments,
                detectedSpeakers: appState.detectedSpeakers,
                forceFullRebuild: true
            )
        }
        .onChange(of: interfaceScale) { _, _ in
            rebuildSegmentCaches(
                liveSegments: appState.liveSegments,
                detectedSpeakers: appState.detectedSpeakers,
                forceFullRebuild: true
            )
        }
        .onReceive(appState.transcriptRuntime.$interimText) { value in
            interimText = value
        }
        .onReceive(appState.transcriptRuntime.$currentSpeaker) { value in
            currentSpeaker = value
        }
        .onReceive(appState.transcriptRuntime.$interimSpeaker) { value in
            interimSpeaker = value
        }
        .background(Color(hex: "09090B")) // GitHub dark background
    }
}

private struct TranscriptBottomAnchorMaxYPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - macOS Scroll Wheel Observer

#if os(macOS)
private struct TranscriptScrollWheelObserver: NSViewRepresentable {
    var onScrolledAwayFromBottom: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ScrollWheelPassthroughView()
        view.onScrolledAwayFromBottom = onScrolledAwayFromBottom
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ScrollWheelPassthroughView)?.onScrolledAwayFromBottom = onScrolledAwayFromBottom
    }

    private class ScrollWheelPassthroughView: NSView {
        var onScrolledAwayFromBottom: (() -> Void)?
        private var boundsObserver: NSObjectProtocol?
        private var didSetupObserver = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !didSetupObserver, window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                self?.setupBoundsObserver()
            }
        }

        private func setupBoundsObserver() {
            guard let scrollView = enclosingScrollView else { return }
            didSetupObserver = true
            scrollView.contentView.postsBoundsChangedNotifications = true
            let clipView = scrollView.contentView
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                let shouldNotify = MainActor.assumeIsolated { () -> Bool in
                    guard let scrollView else { return false }
                    let contentHeight = scrollView.documentView?.frame.height ?? 0
                    let viewportHeight = scrollView.contentView.bounds.height
                    let scrollY = scrollView.contentView.bounds.origin.y
                    let distanceFromBottom = contentHeight - viewportHeight - scrollY
                    return distanceFromBottom > 30
                }
                if shouldNotify {
                    DispatchQueue.main.async { [weak self] in
                        self?.onScrolledAwayFromBottom?()
                    }
                }
            }
        }

        override func removeFromSuperview() {
            if let obs = boundsObserver {
                NotificationCenter.default.removeObserver(obs)
                boundsObserver = nil
            }
            super.removeFromSuperview()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
#endif

// MARK: - Speaker Legend

struct SpeakerLegend: View {
    let speakers: [Int]
    var isRecording: Bool = false
    var speakerNames: [String: String]? = nil
    var selfIDs: Set<Int>? = nil
    var onRename: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: 16) {
            // Recording indicator
            if isRecording {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(hex: "F85149"))
                        .frame(width: 6, height: 6)
                    Text("live")
                        .font(.system(size: 10, weight: .semibold, design: .default))
                        .foregroundStyle(Color(hex: "F85149"))
                }
            }

            Text("speakers:")
                .font(.system(size: 10, weight: .medium, design: .default))
                .foregroundStyle(Color(hex: "484F58"))

            if speakers.isEmpty {
                Text("detecting...")
                    .font(.system(size: 10, weight: .medium, design: .default))
                    .foregroundStyle(Color(hex: "484F58"))
            } else {
                let uniqueSpeakers: [Int] = {
                    var seen = Set<String>()
                    var out: [Int] = []
                    for s in speakers {
                        let key = SelectableAttributed.displayGroupKey(speaker: s, names: speakerNames, selfIDs: selfIDs)
                        if seen.insert(key).inserted { out.append(s) }
                    }
                    return out
                }()
                ForEach(uniqueSpeakers, id: \.self) { speaker in
                    let label = speakerLabel(for: speaker, names: speakerNames, selfIDs: selfIDs)
                    let color = speakerColor(for: speaker, selfIDs: selfIDs)
                    let chip = HStack(spacing: 4) {
                        Circle()
                            .fill(color)
                            .frame(width: 6, height: 6)
                        Text(label)
                            .font(.system(size: 10, weight: .semibold, design: .default))
                            .foregroundStyle(color)
                    }
                    if let onRename {
                        Button {
                            onRename(speaker)
                        } label: {
                            chip
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .help("rename speaker")
                    } else {
                        chip
                    }
                }
            }
            
            Spacer()
            
            // Show count
            let effectiveSelves: Set<Int> = (selfIDs?.isEmpty == false) ? selfIDs! : [DeepgramService.micSpeakerID]
            let selfCount = speakers.filter { effectiveSelves.contains($0) }.count
            let remoteCount = speakers.count - selfCount
            if speakers.count == 1 && !speakers.isEmpty {
                let isSelf = effectiveSelves.contains(speakers[0])
                Text(isSelf ? "(you only)" : "(single speaker)")
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(Color(hex: "484F58"))
            } else if selfCount >= 1 && remoteCount == 1 {
                Text(selfCount > 1 ? "(you ×\(selfCount) + 1 remote)" : "(you + 1 remote)")
                    .font(.system(size: 10, weight: .regular, design: .default))
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

// MARK: - Speaker Color & Label Helpers

/// Palette for remote speakers (Deepgram-diarized). Index 0 = first remote speaker.
private let remoteSpeakerColors: [Color] = [
    Color(hex: "58A6FF"), // Blue
    Color(hex: "A371F7"), // Purple
    Color(hex: "D29922"), // Orange
    Color(hex: "F778BA"), // Pink
    Color(hex: "79C0FF"), // Cyan
    Color(hex: "FFA657"), // Light orange
    Color(hex: "7EE787"), // Light green
]

/// Distinct green for "You" (local mic).
private let micSpeakerColor = Color(hex: "3FB950")

func speakerColor(for speaker: Int, selfIDs: Set<Int>? = nil) -> Color {
    let effectiveSelves: Set<Int> = (selfIDs?.isEmpty == false) ? selfIDs! : [DeepgramService.micSpeakerID]
    if effectiveSelves.contains(speaker) {
        return micSpeakerColor
    }
    return remoteSpeakerColors[speaker % remoteSpeakerColors.count]
}

func speakerLabel(for speaker: Int, names: [String: String]? = nil, selfIDs: Set<Int>? = nil) -> String {
    resolvedShortSpeakerLabel(for: speaker, names: names, selfIDs: selfIDs)
}

func speakerDisplayName(for speaker: Int, names: [String: String]? = nil, selfIDs: Set<Int>? = nil) -> String {
    resolvedSpeakerLabel(for: speaker, names: names, selfIDs: selfIDs)
}

// MARK: - Terminal Style Components

struct TerminalSegmentRow: View {
    @Environment(\.interfaceScale) private var interfaceScale
    let segment: AppState.LiveSegment
    var isNewTurn: Bool = true
    var isFirst: Bool = false
    var speakerNames: [String: String]? = nil
    var selfIDs: Set<Int>? = nil

    private var color: Color { speakerColor(for: segment.speaker, selfIDs: selfIDs) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Speaker turn indicator
            if isNewTurn {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(color)
                        .frame(width: 3, height: 12)
                        .cornerRadius(1.5)

                    Text(speakerDisplayName(for: segment.speaker, names: speakerNames, selfIDs: selfIDs))
                        .font(.system(size: 10, weight: .semibold, design: .default))
                        .foregroundStyle(color)

                    Text("•")
                        .foregroundStyle(Color(hex: "1C1C1F"))

                    Text(formatTimestamp(segment.timestamp))
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .foregroundStyle(Color(hex: "484F58"))
                }
                .padding(.top, isNewTurn && !isFirst ? 12 : 0)
                .padding(.bottom, 4)
            }
            
            // Message content
            HStack(alignment: .top, spacing: 0) {
                // Left border indicator
                Rectangle()
                    .fill(color.opacity(0.3))
                    .frame(width: 2)
                    .padding(.leading, 0)
                
                // Message text
                Text(segment.text)
                    .font(.system(size: interfaceScale.transcriptBodySize, weight: .regular, design: .default))
                    .foregroundStyle(Color(hex: "E6EDF3"))
                    .lineSpacing(interfaceScale.transcriptLineSpacing)
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
    @Environment(\.interfaceScale) private var interfaceScale
    let text: String
    let speaker: Int
    var isNewTurn: Bool = true
    var speakerNames: [String: String]? = nil
    var selfIDs: Set<Int>? = nil

    @State private var cursorVisible = true

    private var color: Color { speakerColor(for: speaker, selfIDs: selfIDs) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Speaker turn indicator (only show if new turn)
            if isNewTurn {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(color.opacity(0.6))
                        .frame(width: 3, height: 12)
                        .cornerRadius(1.5)

                    Text(speakerDisplayName(for: speaker, names: speakerNames, selfIDs: selfIDs))
                        .font(.system(size: 10, weight: .semibold, design: .default))
                        .foregroundStyle(color.opacity(0.7))
                    
                    Text("•")
                        .foregroundStyle(Color(hex: "1C1C1F"))
                    
                    Text("listening...")
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .foregroundStyle(Color(hex: "3FB950").opacity(0.7))
                }
                .padding(.top, 12)
                .padding(.bottom, 4)
            }
            
            // Message content
            HStack(alignment: .top, spacing: 0) {
                // Left border indicator (pulsing for interim)
                Rectangle()
                    .fill(color.opacity(0.5))
                    .frame(width: 2)
                
                // Live text with cursor
                HStack(spacing: 0) {
                    Text(text)
                        .font(.system(size: interfaceScale.transcriptBodySize, weight: .regular, design: .default))
                        .foregroundStyle(Color(hex: "8B949E"))
                        .lineSpacing(interfaceScale.transcriptLineSpacing)
                    
                    // Blinking cursor
                    Text("▊")
                        .font(.system(size: interfaceScale.transcriptBodySize, weight: .regular, design: .default))
                        .foregroundStyle(color)
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
                .font(.system(size: 48, weight: .light, design: .default))
                .foregroundStyle(Color(hex: "1C1C1F"))
            
            Text("ready to transcribe")
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundStyle(Color(hex: "8B949E"))
            
            if appState.appMode == .byok && appState.deepgramApiKey.isEmpty {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Text("⚠")
                            .foregroundStyle(Color(hex: "D29922"))
                        Text("error: deepgram_api_key not set")
                            .foregroundStyle(Color(hex: "F85149"))
                    }
                    .font(.system(size: 12, weight: .medium, design: .default))
                    
                    Button {
                        appState.showSettings = true
                    } label: {
                        Text("[ configure ]")
                            .font(.system(size: 12, weight: .semibold, design: .default))
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


// MARK: - Rename Speaker

/// Identifiable wrapper so we can drive a popover/sheet from an optional Int.
struct SpeakerRenameTarget: Identifiable, Equatable {
    let id: Int
}

/// Small editor that renames a single speaker. Shared by macOS popover and iOS sheet.
/// On save, calls `onSave` with a trimmed non-empty name. On clear, calls `onClear`
/// (which should remove the user override so automatic inference can refill).
struct RenameSpeakerView: View {
    @Environment(\.undoManager) private var undoManager
    let speakerID: Int
    let currentName: String?
    let defaultName: String
    let isSelf: Bool
    var hasOtherSelves: Bool = false
    let onSave: (String) -> Void
    let onClear: () -> Void
    let onMarkAsSelf: () -> Void
    let onUnmarkAsSelf: () -> Void
    let onCancel: () -> Void

    @State private var draft: String = ""
    @FocusState private var focused: Bool

    private var color: Color {
        speakerColor(for: speakerID, selfIDs: isSelf ? [speakerID] : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text("rename speaker")
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .foregroundStyle(ColorPalette.Text.muted)
                Spacer()
            }

            TextField(defaultName, text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(Color(hex: "E6EDF3"))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(hex: "0F0F11"))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(hex: "1C1C1F"), lineWidth: 1)
                )
                .focused($focused)
                .onSubmit { commit() }

            Text(currentName == nil
                 ? "automatic name will appear when detected."
                 : "currently: \(currentName!)")
                .font(.system(size: 10, weight: .regular, design: .default))
                .foregroundStyle(Color(hex: "484F58"))

            VStack(alignment: .leading, spacing: 4) {
                Button {
                    toggleSelfIdentification()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isSelf ? "person.fill.checkmark" : "person.crop.circle.badge.plus")
                            .font(.system(size: 11))
                        Text(isSelf ? "unmark as me" : (hasOtherSelves ? "also mark as me" : "this is me"))
                            .font(.system(size: 11, weight: .semibold, design: .default))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isSelf ? Color(hex: "1F3A22") : Color(hex: "13151A"))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isSelf ? Color(hex: "3FB950") : Color(hex: "1C1C1F"), lineWidth: 1)
                    )
                    .foregroundStyle(isSelf ? ColorPalette.Accent.greenGitHub : ColorPalette.Text.muted)
                }
                .buttonStyle(.plain)

                if !isSelf && hasOtherSelves {
                    Text("diarization sometimes splits one person across IDs — mark each one.")
                        .font(.system(size: 10, weight: .regular, design: .default))
                        .foregroundStyle(Color(hex: "484F58"))
                }
            }

            HStack(spacing: 8) {
                Button(role: .destructive) {
                    clearName()
                } label: {
                    Text("clear")
                        .font(.system(size: 11, weight: .semibold, design: .default))
                }
                .disabled(currentName == nil)

                Spacer()

                Button {
                    onCancel()
                } label: {
                    Text("cancel")
                        .font(.system(size: 11, weight: .semibold, design: .default))
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    commit()
                } label: {
                    Text("save")
                        .font(.system(size: 11, weight: .semibold, design: .default))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(minWidth: 260, idealWidth: 280)
        .background(ColorPalette.Background.primary)
        .onAppear {
            draft = currentName ?? ""
            focused = true
        }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed != currentName else {
            onCancel()
            return
        }
        registerUndo(actionName: "Rename Speaker") {
            if let currentName, !currentName.isEmpty {
                onSave(currentName)
            } else {
                onClear()
            }
        }
        onSave(trimmed)
    }

    private func clearName() {
        guard let currentName, !currentName.isEmpty else { return }
        registerUndo(actionName: "Clear Speaker Name") {
            onSave(currentName)
        }
        onClear()
    }

    private func toggleSelfIdentification() {
        registerUndo(actionName: isSelf ? "Unmark Speaker as Me" : "Mark Speaker as Me") {
            if isSelf {
                onMarkAsSelf()
            } else {
                onUnmarkAsSelf()
            }
        }
        if isSelf {
            onUnmarkAsSelf()
        } else {
            onMarkAsSelf()
        }
    }

    private func registerUndo(actionName: String, action: @escaping () -> Void) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: undoManager) { _ in
            action()
        }
        undoManager.setActionName(actionName)
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
