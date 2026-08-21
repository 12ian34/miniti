#if os(macOS)
import SwiftUI
import AppKit
import Combine

// Floating recording indicator: one non-activating NSPanel owned by a small coordinator,
// outside the main SwiftUI window hierarchy so it survives the main window closing. Every
// action routes through the same AppState methods as the main window, menu bar, and
// notifications — the panel is presentation only.
// See docs/call-lifecycle-and-recording-presence-plan.md ("Recording presence design").

// MARK: - Shared presentation model

extension AppState {
    /// One AppState-derived presentation model shared by the menu bar and the floating
    /// indicator so their wording, countdowns, and actions cannot diverge. Derived on
    /// read; contains no O(transcript) work.
    struct RecordingPresence: Equatable {
        var isRecording: Bool
        var elapsedText: String
        var meetingTitle: String
        /// Bounded lifecycle status: "Zoom call active", "call ended", or
        /// "No supported call detected". Nil when not recording.
        var lifecycleStatus: String?
        var transcriptionStatus: String
        var audioStatus: String
        var graceRemainingSeconds: Int?
        var graceAppName: String?
        /// Recognized call app the recording is associated with, when known.
        var callAppName: String?
    }

    var recordingPresence: RecordingPresence {
        let elapsed = Self.presenceDuration(recordingDuration)
        var lifecycle: String?
        var graceSeconds: Int?
        var graceApp: String?
        if let grace = endingGrace {
            lifecycle = "\(grace.appDisplayName) call ended"
            graceSeconds = grace.remainingSeconds
            graceApp = grace.appDisplayName
        } else if isRecording {
            if let associated = callLifecycleEngine.associatedApp {
                let stillActive = latestCallSnapshot?.activeCalls
                    .contains(where: { $0.bundleID == associated.bundleID }) ?? false
                lifecycle = stillActive
                    ? "\(associated.displayName) call active"
                    : "\(associated.displayName) call not detected"
            } else {
                lifecycle = "No supported call detected"
            }
        }
        return RecordingPresence(
            isRecording: isRecording,
            elapsedText: elapsed,
            meetingTitle: currentMeeting?.displayTitle ?? "",
            lifecycleStatus: lifecycle,
            transcriptionStatus: (deepgramService?.connectionState ?? .disconnected).presenceLabel,
            audioStatus: audioRecoveryState.presenceLabel,
            graceRemainingSeconds: graceSeconds,
            graceAppName: graceApp,
            callAppName: graceApp ?? callLifecycleEngine.associatedApp?.displayName
        )
    }

    static func presenceDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Call-app lifecycle choices belong in the floating surface. Quiet and calendar
    /// prompts remain in the main window/menu bar because they are not evidence that a
    /// supported call has just appeared, ended, or changed.
    var floatingCallLifecyclePrompt: SmartMeetingPrompt? {
        guard let prompt = smartMeetingPrompt else { return nil }
        switch prompt.kind {
        case .callStart, .callEnd, .callTransition:
            return prompt
        case .quiet, .calendar:
            return nil
        }
    }
}

private extension DeepgramService.ConnectionState {
    var presenceLabel: String {
        switch self {
        case .connected: return "Transcription: live"
        case .connecting: return "Transcription: connecting"
        case .disconnected: return "Transcription: off"
        case .error: return "Transcription: degraded"
        }
    }
}

private extension AppState.AudioRecoveryState {
    var presenceLabel: String {
        switch self {
        case .healthy: return "Audio: healthy"
        case .recovering: return "Audio: recovering…"
        case .degraded: return "Audio: degraded"
        }
    }
}

// MARK: - Presentation policies

struct RecordingIndicatorAttentionState: Equatable {
    var promptID: String?
    var isRecording: Bool
    var isEnding: Bool

    static let idle = RecordingIndicatorAttentionState(
        promptID: nil,
        isRecording: false,
        isEnding: false
    )
}

enum RecordingIndicatorAttentionPolicy {
    static func shouldAutoExpand(
        from previous: RecordingIndicatorAttentionState,
        to current: RecordingIndicatorAttentionState
    ) -> Bool {
        let newPrompt = current.promptID != nil && current.promptID != previous.promptID
        let recordingStarted = current.isRecording && !previous.isRecording
        let endingStarted = current.isEnding && !previous.isEnding
        return newPrompt || recordingStarted || endingStarted
    }
}

enum RecordingIndicatorDisclosurePolicy {
    static let dragTolerance: CGFloat = 3

    static func shouldSuppressToggle(for translation: CGSize) -> Bool {
        hypot(translation.width, translation.height) > dragTolerance
    }
}

enum RecordingIndicatorGeometry {
    static let screenMargin: CGFloat = 8

    static func resizedFrame(
        currentFrame: NSRect,
        contentSize: NSSize,
        visibleFrame: NSRect
    ) -> NSRect {
        let bounds = usableBounds(visibleFrame)
        let size = NSSize(
            width: min(contentSize.width, bounds.width),
            height: min(contentSize.height, bounds.height)
        )
        let isOnRightHalf = currentFrame.midX >= visibleFrame.midX
        let origin = NSPoint(
            x: isOnRightHalf ? currentFrame.maxX - size.width : currentFrame.minX,
            y: currentFrame.maxY - size.height
        )
        return constrainedFrame(NSRect(origin: origin, size: size), to: visibleFrame)
    }

    static func constrainedFrame(_ frame: NSRect, to visibleFrame: NSRect) -> NSRect {
        let bounds = usableBounds(visibleFrame)
        let size = NSSize(
            width: min(frame.width, bounds.width),
            height: min(frame.height, bounds.height)
        )
        let x = min(max(frame.minX, bounds.minX), max(bounds.minX, bounds.maxX - size.width))
        let y = min(max(frame.minY, bounds.minY), max(bounds.minY, bounds.maxY - size.height))
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private static func usableBounds(_ visibleFrame: NSRect) -> NSRect {
        guard visibleFrame.width > screenMargin * 2,
              visibleFrame.height > screenMargin * 2 else { return visibleFrame }
        return visibleFrame.insetBy(dx: screenMargin, dy: screenMargin)
    }
}

// MARK: - Coordinator

/// Expansion state lives here (not in SwiftUI @State) so the coordinator can resize the
/// panel window when the content's desired size changes.
@MainActor
final class RecordingIndicatorModel: ObservableObject {
    @Published var expanded = false
}

@MainActor
final class RecordingIndicatorCoordinator {
    static let shared = RecordingIndicatorCoordinator()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private let model = RecordingIndicatorModel()
    private weak var appState: AppState?
    private var stateObservation: AnyCancellable?
    private var moveObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var previousAttentionState: RecordingIndicatorAttentionState = .idle

    private static let positionKey = "recordingIndicator.position"

    func configure(appState: AppState) {
        guard self.appState !== appState else { return }
        self.appState = appState
        // objectWillChange fires before mutation; hop one runloop so reads see new state.
        // The model drives panel expansion, so its changes must also resize the window.
        stateObservation = appState.objectWillChange
            .map { _ in () }
            .merge(with: model.objectWillChange.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateVisibility()
            }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                self?.clampPanelToVisibleScreen()
            }
        }
        updateVisibility()
    }

    private func shouldShowPanel() -> Bool {
        guard let appState else { return false }
        guard appState.showRecordingIndicator else { return false }
        return appState.isRecording
            || appState.endingGrace != nil
            || appState.floatingCallLifecyclePrompt != nil
    }

    private func updateVisibility() {
        guard let appState else { return }
        let currentAttentionState = RecordingIndicatorAttentionState(
            promptID: appState.floatingCallLifecyclePrompt?.id,
            isRecording: appState.isRecording,
            isEnding: appState.endingGrace != nil
        )
        if RecordingIndicatorAttentionPolicy.shouldAutoExpand(
            from: previousAttentionState,
            to: currentAttentionState
        ), !model.expanded {
            model.expanded = true
        }
        previousAttentionState = currentAttentionState

        if shouldShowPanel() {
            showPanel()
        } else {
            if model.expanded {
                model.expanded = false
            }
            hidePanel()
        }
    }

    private func showPanel() {
        guard let appState else { return }
        if panel == nil {
            panel = makePanel(appState: appState)
        }
        guard let panel else { return }
        resizePanelToFitContent()
        if !panel.isVisible {
            panel.orderFrontRegardless()
            clampPanelToVisibleScreen()
        }
    }

    /// AppKit does not resize a borderless panel to its SwiftUI content on its own: track
    /// the hosting view's fitting size explicitly. Preserve the nearest horizontal edge,
    /// grow down from the top, and then constrain the whole result to the visible screen.
    private func resizePanelToFitContent() {
        guard let panel, let hostingView else { return }
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        guard size.width > 1, size.height > 1 else { return }
        let current = panel.frame
        guard let screen = targetScreen(for: current) else { return }
        let target = RecordingIndicatorGeometry.resizedFrame(
            currentFrame: current,
            contentSize: size,
            visibleFrame: screen.visibleFrame
        )
        guard !framesNearlyEqual(current, target) else { return }
        panel.setFrame(target, display: true)
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }

    private func makePanel(appState: AppState) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Never steal focus from the call app or the user's notes.
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let hosting = NSHostingView(
            rootView: AnyView(
                RecordingIndicatorView(model: model)
                    .environmentObject(appState)
            )
        )
        panel.contentView = hosting
        hostingView = hosting

        // Size to real content before positioning so the corner math uses the true frame.
        hosting.layoutSubtreeIfNeeded()
        let initialSize = hosting.fittingSize
        if initialSize.width > 1, initialSize.height > 1 {
            panel.setContentSize(initialSize)
        }

        if let saved = savedPosition() {
            panel.setFrameOrigin(saved)
        } else {
            positionInDefaultCorner(panel)
        }

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                self?.savePanelPosition()
            }
        }
        return panel
    }

    private func positionInDefaultCorner(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: frame.maxX - size.width - 16,
            y: frame.maxY - size.height - 16
        ))
    }

    private func savedPosition() -> NSPoint? {
        guard let values = UserDefaults.standard.array(forKey: Self.positionKey) as? [Double],
              values.count == 2 else { return nil }
        return NSPoint(x: values[0], y: values[1])
    }

    private func savePanelPosition() {
        guard let panel, panel.isVisible else { return }
        UserDefaults.standard.set([panel.frame.origin.x, panel.frame.origin.y], forKey: Self.positionKey)
    }

    /// Keep the whole panel visible after display changes and after restoring a position.
    /// Merely intersecting a screen is insufficient: that allowed expanded controls to sit
    /// partly beyond the right edge.
    private func clampPanelToVisibleScreen() {
        guard let panel, panel.isVisible else { return }
        guard let screen = targetScreen(for: panel.frame) else { return }
        let intersectsAnyScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(panel.frame) }
        if !intersectsAnyScreen {
            positionInDefaultCorner(panel)
        }
        let target = RecordingIndicatorGeometry.constrainedFrame(panel.frame, to: screen.visibleFrame)
        if !framesNearlyEqual(panel.frame, target) {
            panel.setFrame(target, display: true)
        }
    }

    private func targetScreen(for frame: NSRect) -> NSScreen? {
        if let panelScreen = panel?.screen {
            return panelScreen
        }
        let overlapping = NSScreen.screens.max { lhs, rhs in
            lhs.visibleFrame.intersection(frame).area < rhs.visibleFrame.intersection(frame).area
        }
        if let overlapping, overlapping.visibleFrame.intersects(frame) {
            return overlapping
        }
        return NSScreen.main
    }

    private func framesNearlyEqual(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 0.5
            && abs(lhs.minY - rhs.minY) <= 0.5
            && abs(lhs.width - rhs.width) <= 0.5
            && abs(lhs.height - rhs.height) <= 0.5
    }
}

private extension NSRect {
    var area: CGFloat { width * height }
}

// MARK: - Panel content

private struct RecordingIndicatorView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var model: RecordingIndicatorModel
    @State private var headerDragSuppressesToggle = false

    var body: some View {
        let presence = appState.recordingPresence
        let prompt = appState.floatingCallLifecyclePrompt
        VStack(alignment: .leading, spacing: 0) {
            collapsedRow(presence, prompt: prompt)
            if model.expanded {
                expandedContent(presence, prompt: prompt)
            }
        }
        .padding(10)
        .frame(minWidth: model.expanded ? 268 : 0, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(ColorPalette.Background.primary.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(ColorPalette.Border.primary, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private func collapsedRow(
        _ presence: AppState.RecordingPresence,
        prompt: AppState.SmartMeetingPrompt?
    ) -> some View {
        Button {
            guard !headerDragSuppressesToggle else { return }
            model.expanded.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: collapsedIcon(presence, prompt: prompt))
                    .font(.system(size: 11))
                    .foregroundStyle(prompt == nil ? ColorPalette.Status.recording : ColorPalette.Status.warning)
                    .accessibilityHidden(true)
                if let prompt {
                    Text(prompt.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ColorPalette.Text.primary)
                        .lineLimit(1)
                } else if let remaining = presence.graceRemainingSeconds {
                    Text("ending \(remaining)s")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(ColorPalette.Text.primary)
                } else {
                    Text(presence.elapsedText)
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(ColorPalette.Text.primary)
                }
                if prompt == nil,
                   let appName = presence.callAppName,
                   presence.graceRemainingSeconds == nil {
                    Text(appName)
                        .font(.system(size: 11))
                        .foregroundStyle(ColorPalette.Text.muted)
                        .lineLimit(1)
                        .frame(maxWidth: 90, alignment: .leading)
                }

                Spacer(minLength: 12)

                Image(systemName: model.expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ColorPalette.Text.primary)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(ColorPalette.Background.tertiary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(ColorPalette.Border.primary, lineWidth: 1)
                    )
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if RecordingIndicatorDisclosurePolicy.shouldSuppressToggle(
                        for: value.translation
                    ) {
                        headerDragSuppressesToggle = true
                    }
                }
                .onEnded { _ in
                    // Keep suppression through the Button's mouse-up action, then reset
                    // before the next click begins.
                    DispatchQueue.main.async {
                        headerDragSuppressesToggle = false
                    }
                }
        )
        .accessibilityLabel(collapsedAccessibilityLabel(presence, prompt: prompt))
        .accessibilityHint(model.expanded ? "Collapses meeting controls" : "Expands meeting controls")
        .help(model.expanded ? "Collapse meeting controls" : "Expand meeting controls")
    }

    private func collapsedIcon(
        _ presence: AppState.RecordingPresence,
        prompt: AppState.SmartMeetingPrompt?
    ) -> String {
        if prompt != nil { return "phone.fill" }
        return presence.graceRemainingSeconds != nil ? "phone.down.fill" : "record.circle.fill"
    }

    private func collapsedAccessibilityLabel(
        _ presence: AppState.RecordingPresence,
        prompt: AppState.SmartMeetingPrompt?
    ) -> String {
        if let prompt {
            return "\(prompt.title). \(prompt.message) Activate for controls."
        }
        if let remaining = presence.graceRemainingSeconds {
            return "Call ended, finishing recording in \(remaining) seconds. Activate for controls."
        }
        return "Recording, \(presence.elapsedText) elapsed. Activate for controls."
    }

    @ViewBuilder
    private func expandedContent(
        _ presence: AppState.RecordingPresence,
        prompt: AppState.SmartMeetingPrompt?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.vertical, 6)

            if let prompt {
                promptMessage(prompt)

                Divider().padding(.vertical, 2)
                promptActions(prompt)
            } else {
                if !presence.meetingTitle.isEmpty {
                    Text(presence.meetingTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ColorPalette.Text.primary)
                        .lineLimit(1)
                }
                if let lifecycle = presence.lifecycleStatus {
                    statusRow(lifecycle)
                }
                statusRow(presence.transcriptionStatus)
                statusRow(presence.audioStatus)

                Divider().padding(.vertical, 2)

                if presence.graceRemainingSeconds != nil {
                    HStack(spacing: 6) {
                        indicatorActionButton(
                            "keep recording",
                            systemImage: "record.circle",
                            role: .positive,
                            isEmphasized: true,
                            action: appState.keepRecordingFromEndingGrace
                        )
                        indicatorActionButton(
                            "end now",
                            systemImage: "stop.fill",
                            role: .recording,
                            action: appState.endEndingGraceNow
                        )
                    }
                } else {
                    HStack(spacing: 6) {
                        indicatorActionButton(
                            "open meeting",
                            systemImage: "macwindow",
                            role: .primary,
                            isEmphasized: true
                        ) {
                            (NSApp.delegate as? AppDelegate)?.openOrRestoreMainWindow()
                        }
                        indicatorActionButton(
                            "end meeting",
                            systemImage: "stop.fill",
                            role: .recording,
                            action: appState.stopRecording
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func promptActions(_ prompt: AppState.SmartMeetingPrompt) -> some View {
        HStack(spacing: 6) {
            switch prompt.kind {
            case .callStart:
                indicatorActionButton(
                    "take notes",
                    systemImage: "square.and.pencil",
                    role: .positive,
                    isEmphasized: true,
                    action: appState.startMeetingFromDetectedCall
                )
                indicatorActionButton(
                    "not now",
                    systemImage: "xmark",
                    role: .secondary,
                    action: appState.dismissDetectedCallStartPrompt
                )
            case .callEnd:
                indicatorActionButton(
                    "end meeting",
                    systemImage: "stop.fill",
                    role: .recording,
                    isEmphasized: true,
                    action: appState.endMeetingFromSmartPrompt
                )
                indicatorActionButton(
                    "keep recording",
                    systemImage: "record.circle",
                    role: .secondary,
                    action: appState.keepRecordingFromSmartMeetingPrompt
                )
            case .callTransition:
                indicatorActionButton(
                    "end & start next",
                    systemImage: "arrow.right",
                    role: .positive,
                    isEmphasized: true,
                    action: appState.endAndStartNewMeeting
                )
                indicatorActionButton(
                    "keep recording",
                    systemImage: "record.circle",
                    role: .secondary,
                    action: appState.keepRecordingFromSmartMeetingPrompt
                )
            case .quiet, .calendar:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func promptMessage(_ prompt: AppState.SmartMeetingPrompt) -> some View {
        if prompt.kind == .callStart {
            HStack(spacing: 6) {
                Text("take notes with")
                    .font(.system(size: 11))
                    .foregroundStyle(ColorPalette.Text.muted)
                Text("⬢")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(ColorPalette.Accent.greenGitHub)
                    .accessibilityHidden(true)
                Text("miniti")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ColorPalette.Text.primary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Take notes with Miniti")
        } else {
            Text(prompt.message)
                .font(.system(size: 11))
                .foregroundStyle(ColorPalette.Text.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func indicatorActionButton(
        _ title: String,
        systemImage: String,
        role: MinitiControlRole,
        isEmphasized: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            MinitiControlLabel(
                role: role,
                isEmphasized: isEmphasized,
                height: 28,
                horizontalPadding: 9
            ) {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private func statusRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(ColorPalette.Text.muted)
            .lineLimit(1)
    }
}
#endif
