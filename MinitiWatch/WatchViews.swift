import SwiftUI

struct WatchRootView: View {
    @EnvironmentObject private var model: WatchModel
    @State private var page = 0

    var body: some View {
        TabView(selection: $page) {
            RecordView().tag(0)
            QueueView().tag(1)
        }
        .tabViewStyle(.verticalPage)
        .background(WatchPalette.background)
        .onAppear {
            if model.screenshotScene == "queue" { page = 1 }
        }
    }
}

struct RecordView: View {
    @EnvironmentObject private var model: WatchModel

    var body: some View {
        RecordContent(recorder: model.recorder, link: model.link, toggle: model.toggleRecording,
                      permissionDenied: model.permissionDenied, screenshot: model.screenshotScene != nil)
    }
}

private struct RecordContent: View {
    @ObservedObject var recorder: WatchRecorder
    @ObservedObject var link: WatchSessionClient
    let toggle: () -> Void
    let permissionDenied: Bool
    var screenshot = false

    var body: some View {
        VStack(spacing: 10) {
            Text("miniti")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(WatchPalette.textDim)
            Text(timeString(recorder.elapsed))
                .font(.system(.title2, design: .rounded).monospacedDigit())
                .foregroundStyle(WatchPalette.textPrimary)
            LevelBar(level: recorder.level, active: recorder.isRecording)
            Button(action: toggle) {
                Label(recorder.isRecording ? "Stop" : "Record", systemImage: recorder.isRecording ? "stop.fill" : "mic.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .tint(recorder.isRecording ? WatchPalette.recording : WatchPalette.success)
            .buttonStyle(.borderedProminent)
            Text(footer)
                .font(.caption2)
                .foregroundStyle(WatchPalette.textDim)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WatchPalette.background)
    }

    private var footer: String {
        if screenshot { return recorder.isRecording ? "Stays on the watch until your iPhone has it" : "Transcribed on your iPhone after you stop" }
        if permissionDenied { return "Allow the microphone in Settings" }
        if let error = recorder.lastError { return error }
        if recorder.isRecording { return "Stays on the watch until your iPhone has it" }
        if !link.isCompanionInstalled { return "Install miniti on your iPhone" }
        return "Transcribed on your iPhone after you stop"
    }

    private func timeString(_ t: TimeInterval) -> String {
        let total = Int(t)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

private struct LevelBar: View {
    let level: Float
    let active: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(WatchPalette.surface)
                Capsule()
                    .fill(active ? WatchPalette.recording : WatchPalette.textDim)
                    .frame(width: max(4, proxy.size.width * CGFloat(active ? level : 0)))
            }
        }
        .frame(height: 6)
        .animation(.linear(duration: 0.2), value: level)
    }
}

struct QueueView: View {
    @EnvironmentObject private var model: WatchModel

    var body: some View {
        List {
            if model.recordings.isEmpty {
                Text("No recordings waiting")
                    .font(.caption)
                    .foregroundStyle(WatchPalette.textDim)
            }
            ForEach(model.recordings, id: \.id) { recording in
                VStack(alignment: .leading, spacing: 2) {
                    Text(recording.startedAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                        .font(.caption)
                        .foregroundStyle(WatchPalette.textPrimary)
                    HStack {
                        Text(durationString(recording.duration))
                        Text("·")
                        Text(model.status(for: recording))
                    }
                    .font(.caption2)
                    .foregroundStyle(WatchPalette.textDim)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { model.discard(recording.id) } label: {
                        Label("Discard", systemImage: "trash")
                    }
                    .disabled(recording.state == .recording)
                }
            }
            if model.recordings.contains(where: { $0.state != .recording }) {
                Button { model.resend() } label: {
                    Label("Send again", systemImage: "arrow.clockwise")
                }
            }
        }
        .navigationTitle("Queue")
    }

    private func durationString(_ t: TimeInterval) -> String {
        let m = Int(t) / 60, s = Int(t) % 60
        return m > 0 ? "\(m) min" : "\(s) s"
    }
}
