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
    @State private var isAutoScrollEnabled = true

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
        .onChange(of: filter) { _, _ in
            isAutoScrollEnabled = true
        }
        .onChange(of: viewMode) { _, _ in
            isAutoScrollEnabled = true
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
            
#if os(macOS)
            Button("save") { saveLogsToFile() }
                .font(.system(.caption, design: .monospaced))
                .buttonStyle(.plain)
                .foregroundStyle(.gray)
#endif

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
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(filtered) { entry in
                            LogEntryRow(entry: entry)
                                .id(entry.id)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("pretty-bottom")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { _ in
                            if isAutoScrollEnabled {
                                isAutoScrollEnabled = false
                            }
                        }
                )
                .onChange(of: logger.entries.count) {
                    guard isAutoScrollEnabled else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("pretty-bottom", anchor: .bottom)
                    }
                }
                
                if !isAutoScrollEnabled {
                    Button {
                        isAutoScrollEnabled = true
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("pretty-bottom", anchor: .bottom)
                        }
                    } label: {
                        Text("resume auto-scroll")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.9))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 12)
                    .padding(.bottom, 10)
                }
            }
        }
    }

    private var rawLogView: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(rawFilteredText.isEmpty ? "(no logs)" : rawFilteredText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        Color.clear
                            .frame(height: 1)
                            .id("raw-bottom")
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { _ in
                            if isAutoScrollEnabled {
                                isAutoScrollEnabled = false
                            }
                        }
                )
                .onChange(of: logger.entries.count) {
                    guard isAutoScrollEnabled else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("raw-bottom", anchor: .bottom)
                    }
                }
                
                if !isAutoScrollEnabled {
                    Button {
                        isAutoScrollEnabled = true
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("raw-bottom", anchor: .bottom)
                        }
                    } label: {
                        Text("resume auto-scroll")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.9))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 12)
                    .padding(.bottom, 10)
                }
            }
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
    private func saveLogsToFile() {
        let panel = NSSavePanel()
        panel.title = "Save Debug Log"
        panel.nameFieldStringValue = "miniti-debug-log-\(timestampForFilename()).txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try rawFilteredText.write(to: url, atomically: true, encoding: .utf8)
                DebugLogger.shared.log(.app, "Debug log saved to \(url.path)")
            } catch {
                DebugLogger.shared.log(.app, "Debug log save FAILED: \(error.localizedDescription)")
            }
        }
    }
    
    private func timestampForFilename() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        return fmt.string(from: Date())
    }
    #endif

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
import UniformTypeIdentifiers
#else
import UIKit
#endif
