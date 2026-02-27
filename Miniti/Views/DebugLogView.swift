import SwiftUI

struct DebugLogView: View {
    enum ViewMode {
        case pretty
        case raw
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var logger = DebugLogger.shared
    @State private var filter: DebugLogger.Category? = nil
    @State private var viewMode: ViewMode = .pretty
    @State private var localEscapeMonitor: Any?

    private var filtered: [DebugLogger.Entry] {
        guard let filter else { return logger.entries }
        return logger.entries.filter { $0.category == filter }
    }

    private var rawFilteredText: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss.SSS"
        return filtered.map { entry in
            "[\(fmt.string(from: entry.timestamp))] [\(entry.category.rawValue)] \(entry.message)"
        }.joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if viewMode == .pretty {
                logList
            } else {
                rawLogView
            }
        }
        .background(Color.black)
        .onAppear {
            DebugLogger.shared.log(.app, "Debug log opened")
            installLocalEscapeMonitor()
        }
        .onDisappear {
            removeLocalEscapeMonitor()
            DebugLogger.shared.log(.app, "Debug log closed")
        }
#if os(macOS) || os(tvOS)
        .onExitCommand {
            dismiss()
        }
#endif
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("debug log")
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(.white)

            Spacer()

            ForEach(DebugLogger.Category.allCases, id: \.self) { cat in
                Button(cat.rawValue) {
                    filter = filter == cat ? nil : cat
                }
                .font(.system(.caption, design: .monospaced))
                .buttonStyle(.plain)
                .foregroundStyle(filter == cat ? .white : .gray)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(filter == cat ? Color.white.opacity(0.15) : Color.clear)
                .cornerRadius(4)
            }

            Button(viewMode == .pretty ? "raw" : "pretty") {
                viewMode = (viewMode == .pretty) ? .raw : .pretty
            }
            .font(.system(.caption, design: .monospaced))
            .buttonStyle(.plain)
            .foregroundStyle(.gray)

            Button("copy") { copyLogs() }
                .font(.system(.caption, design: .monospaced))
                .buttonStyle(.plain)
                .foregroundStyle(.gray)

            Button("clear") { logger.clear() }
                .font(.system(.caption, design: .monospaced))
                .buttonStyle(.plain)
                .foregroundStyle(.gray)

            Button("close") { dismiss() }
                .font(.system(.caption, design: .monospaced))
                .buttonStyle(.plain)
                .foregroundStyle(.gray)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(filtered) { entry in
                        LogEntryRow(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
            .onChange(of: logger.entries.count) {
                if let last = filtered.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var rawLogView: some View {
        ScrollView {
            Text(rawFilteredText.isEmpty ? "(no logs)" : rawFilteredText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
    }

    private func copyLogs() {
        let text = rawFilteredText
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    #if os(macOS)
    private func installLocalEscapeMonitor() {
        guard localEscapeMonitor == nil else { return }
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            guard event.keyCode == 53 else { return event } // Esc
            if event.type == .keyDown {
                dismiss()
            }
            return nil
        }
    }

    private func removeLocalEscapeMonitor() {
        guard let localEscapeMonitor else { return }
        NSEvent.removeMonitor(localEscapeMonitor)
        self.localEscapeMonitor = nil
    }
    #else
    private func installLocalEscapeMonitor() {}
    private func removeLocalEscapeMonitor() {}
    #endif
}

// MARK: - Log Entry Row

private struct LogEntryRow: View {
    let entry: DebugLogger.Entry

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private var categoryColor: Color {
        switch entry.category {
        case .audio: return .green
        case .deepgram: return .cyan
        case .app: return .orange
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(Self.fmt.string(from: entry.timestamp))
                .foregroundStyle(.gray)
            Text(entry.category.rawValue)
                .foregroundStyle(categoryColor)
                .frame(width: 65, alignment: .leading)
            Text(entry.message)
                .foregroundStyle(.white)
        }
        .font(.system(size: 11, design: .monospaced))
        .textSelection(.enabled)
    }
}

#if os(macOS)
import AppKit
#else
import UIKit
#endif
