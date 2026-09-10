import SwiftUI
import Combine
import os

private let transcriptViewPerformanceLog = OSLog(
    subsystem: "com.miniti.app",
    category: .pointsOfInterest
)

#if os(macOS)
enum LiveTranscriptDocumentMutation {
    static func localizedReplacement(
        previous: NSAttributedString,
        next: NSAttributedString,
        revision: UInt64
    ) -> SelectableTextMutation? {
        let old = previous.string as NSString
        let new = next.string as NSString
        guard old != new, old.length > 0, new.length > 0 else { return nil }

        let sharedLimit = min(old.length, new.length)
        var prefix = 0
        while prefix < sharedLimit, old.character(at: prefix) == new.character(at: prefix) {
            prefix += 1
        }

        var suffix = 0
        while suffix < old.length - prefix,
              suffix < new.length - prefix,
              old.character(at: old.length - suffix - 1)
                == new.character(at: new.length - suffix - 1) {
            suffix += 1
        }

        let replacementStart = paragraphStart(in: old, before: prefix)
        let oldChangedEnd = old.length - suffix
        let newChangedEnd = new.length - suffix
        let oldReplacementEnd = paragraphEnd(in: old, after: oldChangedEnd)
        let newReplacementEnd = paragraphEnd(in: new, after: newChangedEnd)
        guard replacementStart <= oldReplacementEnd,
              replacementStart <= newReplacementEnd else { return nil }

        let oldRange = NSRange(
            location: replacementStart,
            length: oldReplacementEnd - replacementStart
        )
        let newRange = NSRange(
            location: replacementStart,
            length: newReplacementEnd - replacementStart
        )
        return SelectableTextMutation(
            revision: revision,
            range: oldRange,
            replacement: next.attributedSubstring(from: newRange)
        )
    }

    private static func paragraphStart(in string: NSString, before index: Int) -> Int {
        guard index > 0 else { return 0 }
        let newline = string.range(
            of: "\n",
            options: .backwards,
            range: NSRange(location: 0, length: min(index, string.length))
        )
        return newline.location == NSNotFound ? 0 : NSMaxRange(newline)
    }

    private static func paragraphEnd(in string: NSString, after index: Int) -> Int {
        guard index < string.length else { return string.length }
        let newline = string.range(
            of: "\n",
            range: NSRange(location: max(0, index), length: string.length - max(0, index))
        )
        return newline.location == NSNotFound ? string.length : NSMaxRange(newline)
    }
}
#endif

struct TranscriptView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.interfaceScale) private var interfaceScale
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var isAutoScrollEnabled = true
    @State private var suppressAutoScrollLockUntil = Date.distantPast
    @State private var cachedSourceSegments: [AppState.LiveSegment] = []
    @State private var cachedVisibleSegmentCount = 0
    @State private var cachedVisibleSpeakers: Set<Int> = []
    @State private var cachedDisplayTurns: [SelectableAttributed.TranscriptTurn] = []
    #if os(macOS)
    @State private var cachedTurnStartOffsets: [Int] = []
    @State private var cachedTranscript = NSMutableAttributedString()
    @State private var cachedTranscriptMutation: SelectableTextMutation?
    @State private var cachedTranscriptRevision: UInt64 = 0
    #endif
    @State private var cachedLastDisplaySpeaker: Int?
    @State private var cachedUniqueSpeakers: [Int] = []
    @State private var runtimeSnapshot = TranscriptRuntimeState.Snapshot.zero
    @State private var pendingAutoScrollTask: Task<Void, Never>?
    @State private var renamingSpeaker: Int? = nil
    @State private var correctingHeardText: String?
    @State private var correctionDraft = ""
    @State private var fixEarlierMentions = true
    #if os(macOS)
    @StateObject private var liveSelectionState = LiveTranscriptSelectionState()
    #else
    @State private var correctingTurnWords: [String] = []
    #endif

    private var interimText: String { runtimeSnapshot.interimText }
    private var currentSpeaker: Int { runtimeSnapshot.currentSpeaker }
    private var interimSpeaker: Int? { runtimeSnapshot.interimSpeaker }

    private var hasInterimText: Bool {
        !interimText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    #if os(macOS)
    private var macInterimSnapshot: LiveTranscriptInterimSnapshot? {
        guard hasInterimText else { return nil }
        let speaker = interimSpeaker ?? currentSpeaker
        let startsNewTurn = cachedLastDisplaySpeaker.map {
            SelectableAttributed.displayGroupKey(
                speaker: $0,
                names: appState.liveSpeakerNames,
                selfIDs: appState.liveSpeakerLabelSelfIDs
            ) != SelectableAttributed.displayGroupKey(
                speaker: speaker,
                names: appState.liveSpeakerNames,
                selfIDs: appState.liveSpeakerLabelSelfIDs
            )
        } ?? true
        return LiveTranscriptInterimSnapshot(
            revision: runtimeSnapshot.revision,
            text: interimText,
            speaker: speaker,
            startsNewTurn: startsNewTurn,
            hasFinalizedContent: cachedTranscript.length > 0,
            speakerNames: appState.liveSpeakerNames,
            selfIDs: appState.liveSpeakerLabelSelfIDs,
            bodyFontSize: interfaceScale.transcriptBodySize,
            headerFontSize: interfaceScale.transcriptHeaderSize,
            lineSpacing: interfaceScale.transcriptLineSpacing
        )
    }
    #endif

    private func rebuildSegmentCaches(
        liveSegments: [AppState.LiveSegment],
        detectedSpeakers: Set<Int>,
        forceFullRebuild: Bool = false
    ) {
        let signpostID = OSSignpostID(log: transcriptViewPerformanceLog)
        os_signpost(
            .begin,
            log: transcriptViewPerformanceLog,
            name: "TranscriptViewCacheUpdate",
            signpostID: signpostID,
            "segments=%{public}d full=%{public}d",
            liveSegments.count,
            forceFullRebuild ? 1 : 0
        )
        defer {
            os_signpost(
                .end,
                log: transcriptViewPerformanceLog,
                name: "TranscriptViewCacheUpdate",
                signpostID: signpostID,
                "visible=%{public}d turns=%{public}d",
                cachedVisibleSegmentCount,
                cachedDisplayTurns.count
            )
        }

        let names = appState.liveSpeakerNames
        let selfIDs = appState.liveSpeakerLabelSelfIDs
        let canAppend = !forceFullRebuild
            && !cachedSourceSegments.isEmpty
            && liveSegments.count > cachedSourceSegments.count
            && liveSegments.first == cachedSourceSegments.first
            && liveSegments[cachedSourceSegments.count - 1] == cachedSourceSegments.last

        if canAppend {
            let appended = liveSegments.dropFirst(cachedSourceSegments.count).filter {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            #if os(macOS)
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
                let oldTailRange = NSRange(
                    location: replacementStart,
                    length: cachedTranscript.length - replacementStart
                )
                let oldTail = cachedTranscript.attributedSubstring(from: oldTailRange)
                cachedTranscript.replaceCharacters(in: oldTailRange, with: tailDocument.attributed)

                // A normal final either extends the current speaker turn or appends
                // a new one, so the previously rendered tail remains an exact prefix.
                // Mutate only the new suffix: this minimizes TextKit layout work and
                // keeps selections that reach into the prior final turn intact.
                let stablePrefixLength = tailDocument.attributed.string.hasPrefix(oldTail.string)
                    ? oldTail.length
                    : 0
                let mutationRange = NSRange(
                    location: replacementStart + stablePrefixLength,
                    length: oldTail.length - stablePrefixLength
                )
                let mutationReplacement = tailDocument.attributed.attributedSubstring(
                    from: NSRange(
                        location: stablePrefixLength,
                        length: tailDocument.attributed.length - stablePrefixLength
                    )
                )

                cachedTranscriptRevision &+= 1
                cachedTranscriptMutation = SelectableTextMutation(
                    revision: cachedTranscriptRevision,
                    range: mutationRange,
                    replacement: mutationReplacement
                )
                cachedDisplayTurns = Array(updatedTurns[..<tailStartIndex]) + tailDocument.turns
                cachedTurnStartOffsets = Array(cachedTurnStartOffsets[..<tailStartIndex])
                    + tailDocument.turnStartOffsets.map { replacementStart + $0 }
                cachedVisibleSegmentCount += appended.count
                for segment in appended { cachedVisibleSpeakers.insert(segment.speaker) }
            } else if !appended.isEmpty {
                rebuildAllSegments(
                    liveSegments,
                    names: names,
                    selfIDs: selfIDs,
                    allowsLocalizedMutation: !forceFullRebuild
                )
            }
            #else
            if !appended.isEmpty, !cachedDisplayTurns.isEmpty {
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
                cachedDisplayTurns = updatedTurns
                cachedVisibleSegmentCount += appended.count
                for segment in appended { cachedVisibleSpeakers.insert(segment.speaker) }
            } else if !appended.isEmpty {
                rebuildAllSegments(liveSegments, names: names, selfIDs: selfIDs)
            }
            #endif
        } else {
            rebuildAllSegments(
                liveSegments,
                names: names,
                selfIDs: selfIDs,
                allowsLocalizedMutation: !forceFullRebuild
            )
        }

        cachedSourceSegments = liveSegments
        cachedLastDisplaySpeaker = cachedDisplayTurns.last?.speaker
        updateUniqueSpeakers(detectedSpeakers)
    }

    private func rebuildAllSegments(
        _ liveSegments: [AppState.LiveSegment],
        names: [String: String],
        selfIDs: Set<Int>?,
        allowsLocalizedMutation: Bool = false
    ) {
        let visible = liveSegments.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let visibleTurns: [SelectableAttributed.TranscriptTurn] = visible.map {
            .init(speaker: $0.speaker, timestamp: $0.timestamp, text: $0.text)
        }
        cachedVisibleSegmentCount = visible.count
        cachedVisibleSpeakers = Set(visible.map(\.speaker))
        #if os(macOS)
        let document = SelectableAttributed.transcriptDocument(
            turns: visibleTurns,
            speakerNames: names,
            selfIDs: selfIDs,
            bodyFontSize: interfaceScale.transcriptBodySize,
            headerFontSize: interfaceScale.transcriptHeaderSize,
            lineSpacing: interfaceScale.transcriptLineSpacing
        )
        cachedTranscriptRevision &+= 1
        cachedTranscriptMutation = allowsLocalizedMutation
            ? LiveTranscriptDocumentMutation.localizedReplacement(
                previous: cachedTranscript,
                next: document.attributed,
                revision: cachedTranscriptRevision
            )
            : nil
        cachedDisplayTurns = document.turns
        cachedTurnStartOffsets = document.turnStartOffsets
        cachedTranscript = NSMutableAttributedString(attributedString: document.attributed)
        #else
        cachedDisplayTurns = SelectableAttributed.mergeTurns(
            visibleTurns,
            speakerNames: names,
            selfIDs: selfIDs
        )
        #endif
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
        applyRuntimeSnapshot(appState.transcriptRuntime.snapshot)
    }

    private func applyRuntimeSnapshot(_ snapshot: TranscriptRuntimeState.Snapshot) {
        guard snapshot.revision >= runtimeSnapshot.revision else { return }
        runtimeSnapshot = snapshot
    }

    private func cancelPendingAutoScroll() {
        pendingAutoScrollTask?.cancel()
        pendingAutoScrollTask = nil
    }

    private func scrollToBottom(proxy: ScrollViewProxy, delay: Duration = .milliseconds(20)) {
        cancelPendingAutoScroll()
        pendingAutoScrollTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, isAutoScrollEnabled else { return }
            if accessibilityReduceMotion {
                proxy.scrollTo("bottom", anchor: .bottom)
            } else {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            pendingAutoScrollTask = nil
        }
    }

    private func suppressAutoScrollLockBriefly(_ duration: TimeInterval = 0.25) {
        suppressAutoScrollLockUntil = Date().addingTimeInterval(duration)
    }

    @ViewBuilder
    private func renameSpeakerView(for speakerID: Int) -> some View {
        let key = String(speakerID)
        let currentName = appState.liveSpeakerNames[key]
        let defaultName = resolvedSpeakerLabel(for: speakerID, names: nil, selfIDs: appState.liveSpeakerLabelSelfIDs)
        let isSelf = appState.effectiveLiveSelfSpeakerIDs.contains(speakerID)
        let hasOtherSelves = appState.effectiveLiveSelfSpeakerIDs.subtracting([speakerID]).isEmpty == false
        RenameSpeakerView(
            speakerID: speakerID,
            currentName: currentName,
            defaultName: defaultName,
            isSelf: isSelf,
            hasOtherSelves: hasOtherSelves,
            showMarkAllMicAsSelf: appState.liveMicSpeakerIDs.count > 1,
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
            onMarkAllMicAsSelf: {
                appState.markAllLiveMicSpeakersAsSelf()
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
                            selfIDs: appState.liveSpeakerLabelSelfIDs,
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
                    
                    #if os(macOS)
                    ZStack(alignment: .bottomTrailing) {
                        LiveTranscriptTextPaneMac(
                            finalizedAttributed: cachedTranscript,
                            finalizedMutation: cachedTranscriptMutation,
                            finalizedRevision: cachedTranscriptRevision,
                            interim: macInterimSnapshot,
                            isAutoScrollEnabled: isAutoScrollEnabled,
                            reduceMotion: accessibilityReduceMotion,
                            onScrolledAwayFromBottom: {
                                isAutoScrollEnabled = false
                            },
                            selectionState: liveSelectionState,
                            onCorrectSelection: { heard in
                                beginLiveCorrection(heard: heard)
                            }
                        )

                        // The pill stays mounted while the editor is open: the popover is
                        // anchored on it, so tearing it down would dismiss the editor.
                        // `correctingHeardText` wins so a selection change mid-edit cannot
                        // relabel the pill or swap the word being corrected.
                        if let heard = correctingHeardText ?? liveSelectionState.heardText {
                            Button {
                                beginLiveCorrection(heard: heard)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "character.cursor.ibeam")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text("correct “\(heard)”")
                                        .font(.system(size: 10, weight: .semibold, design: .default))
                                        .lineLimit(1)
                                    Text("⌘⇧D")
                                        .font(.system(size: 9, weight: .medium, design: .default))
                                        .foregroundStyle(ColorPalette.Text.primary.opacity(0.7))
                                }
                                .foregroundStyle(ColorPalette.Text.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(ColorPalette.Background.card)
                                .overlay(
                                    Capsule()
                                        .stroke(
                                            correctingHeardText != nil
                                                ? ColorPalette.Accent.green
                                                : ColorPalette.Border.primary,
                                            lineWidth: 1
                                        )
                                )
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .help("Save a dictionary correction for the selected word")
                            .padding(.trailing, 32)
                            .padding(.bottom, isAutoScrollEnabled ? 16 : 48)
                            .zIndex(2)
                            .transition(.opacity)
                            .popover(
                                isPresented: Binding(
                                    get: { correctingHeardText != nil },
                                    set: { if !$0 { correctingHeardText = nil } }
                                ),
                                arrowEdge: .bottom
                            ) {
                                if let editing = correctingHeardText {
                                    TranscriptCorrectionEditor(
                                        heard: editing,
                                        correct: $correctionDraft,
                                        fixEarlierMentions: $fixEarlierMentions,
                                        onSave: {
                                            appState.saveDictionaryCorrection(
                                                heard: editing,
                                                correct: correctionDraft,
                                                fixEarlierMentions: fixEarlierMentions
                                            )
                                            correctingHeardText = nil
                                            // Collapse the native selection so the pill does
                                            // not immediately reappear offering to "correct"
                                            // the word that was just corrected.
                                            liveSelectionState.requestDeselect()
                                        },
                                        onCancel: {
                                            correctingHeardText = nil
                                        }
                                    )
                                    .frame(minWidth: 280)
                                }
                            }
                        }

                        if !isAutoScrollEnabled {
                            Button {
                                isAutoScrollEnabled = true
                            } label: {
                                Text("resume auto-scroll")
                                    .font(.system(size: 10, weight: .semibold, design: .default))
                                    .foregroundStyle(ColorPalette.Text.primary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(ColorPalette.Accent.blue.opacity(0.95))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .help("resume following the live transcript")
                            .padding(.trailing, 32)
                            .padding(.bottom, 16)
                            .zIndex(1)
                        }
                    }
                    .onChange(of: appState.isRecording) { _, isRecording in
                        if isRecording {
                            isAutoScrollEnabled = true
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .minitiCorrectSelectedTranscriptWord)) { _ in
                        guard let heard = liveSelectionState.heardText else { return }
                        beginLiveCorrection(heard: heard)
                    }
                    #else
                    ScrollViewReader { proxy in
                        GeometryReader { scrollGeometry in
                            ZStack(alignment: .bottomTrailing) {
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 6) {
                                        ForEach(cachedDisplayTurns.indices, id: \.self) { index in
                                            TerminalTranscriptTurnRow(
                                                turn: cachedDisplayTurns[index],
                                                isFirst: index == cachedDisplayTurns.startIndex,
                                                speakerNames: appState.liveSpeakerNames,
                                                selfIDs: appState.liveSpeakerLabelSelfIDs,
                                                onRequestCorrectWord: {
                                                    beginIOSCorrection(for: cachedDisplayTurns[index].text)
                                                }
                                            )
                                            .id("turn-\(index)")
                                        }

                                        // Interim (live typing) text
                                        if hasInterimText {
                                            let interimSpeakerValue = interimSpeaker ?? currentSpeaker
                                            TerminalInterimRow(
                                                text: interimText,
                                                speaker: interimSpeakerValue,
                                                isNewTurn: cachedLastDisplaySpeaker.map {
                                                    SelectableAttributed.displayGroupKey(speaker: $0, names: appState.liveSpeakerNames, selfIDs: appState.liveSpeakerLabelSelfIDs)
                                                    != SelectableAttributed.displayGroupKey(speaker: interimSpeakerValue, names: appState.liveSpeakerNames, selfIDs: appState.liveSpeakerLabelSelfIDs)
                                                } ?? true,
                                                speakerNames: appState.liveSpeakerNames,
                                                selfIDs: appState.liveSpeakerLabelSelfIDs
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
                                .simultaneousGesture(
                                    DragGesture(minimumDistance: 4)
                                        .onChanged { _ in
                                            if isAutoScrollEnabled {
                                                isAutoScrollEnabled = false
                                                cancelPendingAutoScroll()
                                            }
                                        }
                                )
                                .onChange(of: cachedVisibleSegmentCount) { _, newCount in
                                    if newCount == 0 {
                                        isAutoScrollEnabled = true
                                    }
                                    guard isAutoScrollEnabled else { return }
                                    suppressAutoScrollLockBriefly()
                                    scrollToBottom(proxy: proxy)
                                }
                                .onChange(of: interimText) { _, _ in
                                    guard isAutoScrollEnabled else { return }
                                    suppressAutoScrollLockBriefly()
                                    scrollToBottom(proxy: proxy, delay: .milliseconds(80))
                                }
                                .onChange(of: appState.isRecording) { _, isRecording in
                                    if isRecording {
                                        isAutoScrollEnabled = true
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
                                            suppressAutoScrollLockBriefly(1.0)
                                            scrollToBottom(proxy: proxy)
                                        }
                                        // Keep the pill visually separate from the transient
                                        // macOS overlay scrollbar at the trailing edge.
                                        .padding(.trailing, 32)
                                        .padding(.bottom, 16)
                                        .zIndex(1)
                                }
                            }
                        }
                    }
                    #endif
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
            // Finals must clear any pending interim immediately. The revision guard also
            // prevents an older throttled fragment from reappearing after this snapshot.
            syncRuntimeSnapshot()
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
        .onChange(of: appState.liveMicSpeakerIDs) { _, _ in
            // A second confirmed mic speaker withdraws the implicit "You" from
            // already-rendered turns, so cached turn headers must rebuild.
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
        .onReceive(
            appState.transcriptRuntime.$snapshot
                .filter { $0.interimText.isEmpty }
        ) { snapshot in
            // Clears are never throttled: finalized text must replace the interim row now.
            applyRuntimeSnapshot(snapshot)
        }
        .onReceive(
            appState.transcriptRuntime.$snapshot
                .filter { !$0.interimText.isEmpty }
                .throttle(for: .milliseconds(125), scheduler: RunLoop.main, latest: true)
        ) { snapshot in
            applyRuntimeSnapshot(snapshot)
        }
        .onDisappear {
            cancelPendingAutoScroll()
        }
        #if os(iOS)
        .sheet(isPresented: Binding(
            get: { !correctingTurnWords.isEmpty },
            set: { showing in
                if !showing {
                    correctingTurnWords = []
                    correctingHeardText = nil
                    correctionDraft = ""
                }
            }
        )) {
            IOSLiveTranscriptCorrectionSheet(
                words: correctingTurnWords,
                heard: Binding(
                    get: { correctingHeardText ?? "" },
                    set: { correctingHeardText = $0.isEmpty ? nil : $0 }
                ),
                correct: $correctionDraft,
                fixEarlierMentions: $fixEarlierMentions,
                onSave: {
                    guard let heard = correctingHeardText else { return }
                    appState.saveDictionaryCorrection(
                        heard: heard,
                        correct: correctionDraft,
                        fixEarlierMentions: fixEarlierMentions
                    )
                    correctingTurnWords = []
                    correctingHeardText = nil
                    correctionDraft = ""
                },
                onCancel: {
                    correctingTurnWords = []
                    correctingHeardText = nil
                    correctionDraft = ""
                }
            )
            .presentationDetents([.medium])
            .presentationBackground(ColorPalette.Background.primary)
        }
        #endif
        .background(Color(hex: "09090B")) // GitHub dark background
    }

    #if os(macOS)
    private func beginLiveCorrection(heard: String) {
        guard correctingHeardText == nil else { return }
        correctingHeardText = heard
        correctionDraft = ""
        fixEarlierMentions = true
    }
    #endif

    #if os(iOS)
    private func beginIOSCorrection(for turnText: String) {
        let words = TranscriptCorrectionSelection.words(in: turnText)
        guard !words.isEmpty else { return }
        correctingTurnWords = words
        correctingHeardText = nil
        correctionDraft = ""
        fixEarlierMentions = true
    }
    #endif
}

// MARK: - Speaker Legend

struct SpeakerLegend: View {
    let speakers: [Int]
    var isRecording: Bool = false
    var speakerNames: [String: String]? = nil
    var selfIDs: Set<Int>? = nil
    var onRename: ((Int) -> Void)? = nil

    var body: some View {
        FlowLayout(spacing: 12) {
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
                .fixedSize()
            }

            Text("speakers:")
                .font(.system(size: 10, weight: .medium, design: .default))
                .foregroundStyle(Color(hex: "484F58"))
                .fixedSize()

            if speakers.isEmpty {
                Text("detecting...")
                    .font(.system(size: 10, weight: .medium, design: .default))
                    .foregroundStyle(Color(hex: "484F58"))
                    .fixedSize()
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
                        .fixedSize()
                    } else {
                        chip.fixedSize()
                    }
                }
            }

            // Show count. An empty (non-nil) self set means several people share the
            // microphone and nobody is implicitly "You".
            let effectiveSelves: Set<Int> = selfIDs ?? [DeepgramService.micSpeakerID]
            let selfCount = speakers.filter { effectiveSelves.contains($0) }.count
            let remoteCount = speakers.count - selfCount
            if speakers.count == 1 && !speakers.isEmpty {
                let isSelf = effectiveSelves.contains(speakers[0])
                Text(isSelf ? "(you only)" : "(single speaker)")
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(Color(hex: "484F58"))
                    .fixedSize()
            } else if selfCount >= 1 && remoteCount == 1 {
                Text(selfCount > 1 ? "(you ×\(selfCount) + 1 remote)" : "(you + 1 remote)")
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(Color(hex: "484F58"))
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    let effectiveSelves: Set<Int> = selfIDs ?? [DeepgramService.micSpeakerID]
    if effectiveSelves.contains(speaker) {
        return micSpeakerColor
    }
    if DeepgramService.isMicAppSpeakerID(speaker) {
        // Offset non-self mic-range speakers so the first extra room speakers don't
        // reuse the palette indices the first remote speakers already claimed.
        return remoteSpeakerColors[(speaker - DeepgramService.micSpeakerID + 3) % remoteSpeakerColors.count]
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

struct TerminalTranscriptTurnRow: View {
    @Environment(\.interfaceScale) private var interfaceScale
    let turn: SelectableAttributed.TranscriptTurn
    var isFirst: Bool = false
    var speakerNames: [String: String]? = nil
    var selfIDs: Set<Int>? = nil
    var onRequestCorrectWord: (() -> Void)? = nil

    private var color: Color { speakerColor(for: turn.speaker, selfIDs: selfIDs) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(speakerLabel(for: turn.speaker, names: speakerNames, selfIDs: selfIDs)) · \(formatTimestamp(turn.timestamp))")
                .font(.system(size: interfaceScale.transcriptHeaderSize, weight: .semibold, design: .default))
                .foregroundStyle(color)

            Text(turn.text)
                .font(.system(size: interfaceScale.transcriptBodySize, weight: .regular, design: .default))
                .foregroundStyle(Color(hex: "E6EDF3"))
                .lineSpacing(interfaceScale.transcriptLineSpacing)
        }
        .padding(.top, isFirst ? 0 : 10)
        .textSelection(.enabled)
        #if os(iOS)
        .contextMenu {
            if onRequestCorrectWord != nil {
                Button("correct a word...") {
                    onRequestCorrectWord?()
                }
            }
        }
        #endif
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
/// Shared dictionary-correction editor for live transcript and saved-meeting trim.
struct TranscriptCorrectionEditor: View {
    let heard: String
    @Binding var correct: String
    @Binding var fixEarlierMentions: Bool
    var fixEarlierLabel: String = "fix earlier mentions in this meeting"
    let onSave: () -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("correct word")
                .font(.system(size: 11, weight: .semibold, design: .default))
                .foregroundStyle(ColorPalette.Text.muted)

            VStack(alignment: .leading, spacing: 6) {
                Text("heard")
                    .font(.system(size: 10, weight: .medium, design: .default))
                    .foregroundStyle(ColorPalette.Text.dim)
                Text(heard)
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(ColorPalette.Text.primary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ColorPalette.Background.tertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text("correct to")
                    .font(.system(size: 10, weight: .medium, design: .default))
                    .foregroundStyle(ColorPalette.Text.dim)
                TextField("replacement", text: $correct)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .padding(8)
                    .background(ColorPalette.Background.tertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .focused($focused)
                    .onSubmit(onSave)
            }

            Toggle(fixEarlierLabel, isOn: $fixEarlierMentions)
                .font(.system(size: 11, weight: .regular, design: .default))
                #if os(macOS)
                .toggleStyle(.checkbox)
                #endif

            HStack {
                Button("cancel", action: onCancel)
                    #if os(macOS)
                    .keyboardShortcut(.cancelAction)
                    #endif
                Spacer()
                Button("save", action: onSave)
                    #if os(macOS)
                    .keyboardShortcut(.defaultAction)
                    #endif
                    .disabled(correct.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .background(ColorPalette.Background.primary)
        .onAppear { focused = true }
    }
}

#if os(iOS)
/// Long-press chip picker for correcting a word from a live transcript turn.
struct IOSLiveTranscriptCorrectionSheet: View {
    let words: [String]
    @Binding var heard: String
    @Binding var correct: String
    @Binding var fixEarlierMentions: Bool
    let onSave: () -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("tap the word miniti misheard")
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .foregroundStyle(ColorPalette.Text.muted)

                    FlowLayout(spacing: 8) {
                        ForEach(words, id: \.self) { word in
                            Button {
                                heard = word
                            } label: {
                                Text(word)
                                    .font(.system(size: 13, weight: .medium, design: .default))
                                    .foregroundStyle(
                                        heard.lowercased() == word.lowercased()
                                            ? ColorPalette.Text.primary
                                            : ColorPalette.Text.muted
                                    )
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(
                                                heard.lowercased() == word.lowercased()
                                                    ? ColorPalette.Accent.blue.opacity(0.35)
                                                    : ColorPalette.Background.tertiary
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("correct to")
                            .font(.system(size: 10, weight: .medium, design: .default))
                            .foregroundStyle(ColorPalette.Text.dim)
                        TextField("replacement", text: $correct)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15, weight: .regular, design: .default))
                            .padding(10)
                            .background(ColorPalette.Background.tertiary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .focused($focused)
                            .onSubmit(saveIfReady)
                    }

                    Toggle("fix earlier mentions in this meeting", isOn: $fixEarlierMentions)
                        .font(.system(size: 13, weight: .regular, design: .default))
                }
                .padding(16)
            }
            .background(ColorPalette.Background.primary)
            .navigationTitle("correct a word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save", action: saveIfReady)
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if heard.isEmpty, let first = words.first {
                    heard = first
                }
                focused = true
            }
        }
    }

    private var canSave: Bool {
        !heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !correct.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && heard.lowercased() != correct.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func saveIfReady() {
        guard canSave else { return }
        onSave()
    }
}
#endif

struct RenameSpeakerView: View {
    @Environment(\.undoManager) private var undoManager
    let speakerID: Int
    let currentName: String?
    let defaultName: String
    let isSelf: Bool
    var hasOtherSelves: Bool = false
    /// When more than one mic ID exists, offer one-tap consolidation.
    var showMarkAllMicAsSelf: Bool = false
    let onSave: (String) -> Void
    let onClear: () -> Void
    let onMarkAsSelf: () -> Void
    let onUnmarkAsSelf: () -> Void
    var onMarkAllMicAsSelf: (() -> Void)? = nil
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

                if showMarkAllMicAsSelf, let onMarkAllMicAsSelf {
                    Button {
                        registerUndo(actionName: "Mark All Mic Speakers as Me") {
                            // Best-effort undo restores only this speaker's prior mark.
                            if isSelf {
                                onMarkAsSelf()
                            } else {
                                onUnmarkAsSelf()
                            }
                        }
                        onMarkAllMicAsSelf()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 11))
                            Text("mark all mic speakers as me")
                                .font(.system(size: 11, weight: .semibold, design: .default))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(hex: "13151A"))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(hex: "1C1C1F"), lineWidth: 1)
                        )
                        .foregroundStyle(ColorPalette.Text.muted)
                    }
                    .buttonStyle(.plain)
                }

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
