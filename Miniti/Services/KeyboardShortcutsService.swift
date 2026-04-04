import SwiftUI
import Carbon.HIToolbox

/// Manages global keyboard shortcuts for the app
@MainActor
final class KeyboardShortcutsService: ObservableObject {
    static let shared = KeyboardShortcutsService()
    
    private var eventMonitor: Any?
    
    // Callbacks for various actions
    var onToggleRecording: (() -> Void)?
    var onGenerateInsights: (() -> Void)?
    var onNewSession: (() -> Void)?
    var onGoHome: (() -> Void)?
    var onStandardMode: (() -> Void)?
    var onMeddpiccMode: (() -> Void)?
    var onTrainingMode: (() -> Void)?
    var onQuestionsMode: (() -> Void)?
    var onToggleHelp: (() -> Void)?
    var onToggleSidebarCollapse: (() -> Void)?
    var onToggleInsightsCollapse: (() -> Void)?
    var onNavigateUp: (() -> Void)?
    var onNavigateDown: (() -> Void)?
    var onFocusSearch: (() -> Void)?
    var onDismissSearch: (() -> Bool)?
    
    @Published var showingHelp = false
    
    private init() {}
    
    func startMonitoring() {
        // Local event monitor for app-specific shortcuts
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            return self?.handleKeyEvent(event)
        }
    }
    
    func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        // Check for modifier keys
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isTypingInTextInput = isFocusedInEditableTextInput(for: event)
        
        // Escape - Go home or close help
        if event.keyCode == kVK_Escape {
            if dismissAnyActiveSheetIfNeeded() {
                return nil
            }
            if closeSettingsWindowIfActive() {
                return nil
            }
            if closeAnyVisibleSettingsWindowIfNeeded() {
                return nil
            }
            if showingHelp {
                showingHelp = false
                return nil
            }
            if let dismiss = onDismissSearch, dismiss() {
                return nil
            }
            onGoHome?()
            return nil
        }
        
        // ⌘⇧R - Toggle recording
        if modifiers == [.command, .shift] && event.keyCode == kVK_ANSI_R {
            onToggleRecording?()
            return nil
        }
        
        // ⌘⇧I - Generate insights
        if modifiers == [.command, .shift] && event.keyCode == kVK_ANSI_I {
            onGenerateInsights?()
            return nil
        }
        
        // ⌘N - New session
        if modifiers == .command && event.keyCode == kVK_ANSI_N {
            onNewSession?()
            return nil
        }
        
        // ⌘H - Go home (when not recording)
        if modifiers == .command && event.keyCode == kVK_ANSI_H {
            onGoHome?()
            return nil
        }

        // ⌘[ - Toggle sidebar collapse
        if modifiers == .command && event.keyCode == kVK_ANSI_LeftBracket {
            onToggleSidebarCollapse?()
            return nil
        }

        // ⌘] - Toggle insights collapse
        if modifiers == .command && event.keyCode == kVK_ANSI_RightBracket {
            onToggleInsightsCollapse?()
            return nil
        }
        
        // ⌘1 - Standard mode
        if modifiers == .command && event.keyCode == kVK_ANSI_1 {
            onStandardMode?()
            return nil
        }
        
        // ⌘2 - MEDDPICC mode
        if modifiers == .command && event.keyCode == kVK_ANSI_2 {
            onMeddpiccMode?()
            return nil
        }
        
        // ⌘3 - Training mode
        if modifiers == .command && event.keyCode == kVK_ANSI_3 {
            onTrainingMode?()
            return nil
        }
        
        // ⌘4 - Questions mode
        if modifiers == .command && event.keyCode == kVK_ANSI_4 {
            onQuestionsMode?()
            return nil
        }
        
        // ⌘/ or ⌘? - Toggle help
        if modifiers == .command && event.keyCode == kVK_ANSI_Slash {
            showingHelp.toggle()
            return nil
        }
        
        // / - Focus search (unmodified)
        if modifiers.isEmpty && !isTypingInTextInput && event.keyCode == kVK_ANSI_Slash {
            onFocusSearch?()
            return nil
        }

        // Arrow Up or K - Navigate up in history
        if modifiers.isEmpty &&
            !isTypingInTextInput &&
            (event.keyCode == kVK_UpArrow || event.keyCode == kVK_ANSI_K) {
            onNavigateUp?()
            return nil
        }
        
        // Arrow Down or J - Navigate down in history
        if modifiers.isEmpty &&
            !isTypingInTextInput &&
            (event.keyCode == kVK_DownArrow || event.keyCode == kVK_ANSI_J) {
            onNavigateDown?()
            return nil
        }
        
        return event
    }

    private func isFocusedInEditableTextInput(for event: NSEvent) -> Bool {
        let candidateWindows = [event.window, NSApp.keyWindow].compactMap { $0 }
        for window in candidateWindows {
            guard let textView = window.firstResponder as? NSTextView else { continue }
            if textView.isEditable || textView.isFieldEditor {
                return true
            }
        }
        return false
    }
    
    private func dismissAnyActiveSheetIfNeeded() -> Bool {
        if let keyWindow = NSApp.keyWindow {
            // If the sheet itself is key (e.g. debug log opened from Settings),
            // ask the sheet to close itself first so SwiftUI `.sheet` bindings
            // are updated. Do not force `endSheet` here; that can desync state
            // and cause the sheet to immediately re-present ("flash").
            if let parent = keyWindow.sheetParent {
                _ = NSApp.sendAction(#selector(NSResponder.cancelOperation(_:)), to: nil, from: nil)
                keyWindow.performClose(nil)
                if keyWindow.sheetParent == nil || !keyWindow.isVisible || parent.attachedSheet !== keyWindow {
                    return true
                }
                // Consume Escape anyway to avoid window flash/beep; sheet-level handlers
                // (or a subsequent Esc) can close if the current first responder vetoes.
                return true
            }
            
            if let sheet = keyWindow.attachedSheet {
                _ = NSApp.sendAction(#selector(NSResponder.cancelOperation(_:)), to: nil, from: nil)
                sheet.performClose(nil)
                if keyWindow.attachedSheet == nil || !sheet.isVisible {
                    return true
                }
                return true
            }
        }

        // Fallback: scan all visible windows in case AppKit reports a different key window.
        for window in NSApp.windows where window.isVisible {
            if let parent = window.sheetParent {
                _ = NSApp.sendAction(#selector(NSResponder.cancelOperation(_:)), to: nil, from: nil)
                window.performClose(nil)
                if window.sheetParent == nil || !window.isVisible || parent.attachedSheet !== window {
                    return true
                }
                return true
            }
            if let sheet = window.attachedSheet {
                _ = NSApp.sendAction(#selector(NSResponder.cancelOperation(_:)), to: nil, from: nil)
                sheet.performClose(nil)
                if window.attachedSheet == nil || !sheet.isVisible {
                    return true
                }
                return true
            }
        }

        return false
    }
    
    private func closeSettingsWindowIfActive() -> Bool {
        guard let keyWindow = NSApp.keyWindow else { return false }
        guard isSettingsWindow(keyWindow) else { return false }
        keyWindow.close()
        return true
    }

    private func closeAnyVisibleSettingsWindowIfNeeded() -> Bool {
        for window in NSApp.windows where window.isVisible {
            guard isSettingsWindow(window) else { continue }
            window.close()
            return true
        }
        return false
    }
    
    private func isSettingsWindow(_ window: NSWindow) -> Bool {
        let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if title == "settings" || title == "preferences" {
            return true
        }
        
        // SwiftUI Settings windows can sometimes have generic/empty titles,
        // but still present as a utility panel with a tabbed settings UI.
        if window.toolbarStyle == .preference {
            return true
        }

        return false
    }
}

// MARK: - Keyboard Shortcut Info

struct KeyboardShortcut: Identifiable {
    let id = UUID()
    let keys: String
    let description: String
    let category: String
}

let allKeyboardShortcuts: [KeyboardShortcut] = [
    // Recording
    KeyboardShortcut(keys: "⌘⇧R", description: "Start/Stop recording", category: "Recording"),
    KeyboardShortcut(keys: "⌘N", description: "New session", category: "Recording"),
    KeyboardShortcut(keys: "⌘S", description: "Save current session", category: "Recording"),
    KeyboardShortcut(keys: "⌘⌫", description: "Discard current session", category: "Recording"),
    
    // Navigation
    KeyboardShortcut(keys: "↑ / K", description: "Previous in history", category: "Navigation"),
    KeyboardShortcut(keys: "↓ / J", description: "Next in history", category: "Navigation"),
    KeyboardShortcut(keys: "⌘H", description: "Go home", category: "Navigation"),
    KeyboardShortcut(keys: "⌘[", description: "Toggle sidebar", category: "Navigation"),
    KeyboardShortcut(keys: "⌘]", description: "Toggle insights", category: "Navigation"),
    KeyboardShortcut(keys: "/", description: "Search meetings", category: "Navigation"),
    KeyboardShortcut(keys: "Esc", description: "Go home / Close", category: "Navigation"),
    
    // Insights
    KeyboardShortcut(keys: "⌘1", description: "Standard mode", category: "Insights"),
    KeyboardShortcut(keys: "⌘2", description: "MEDDPICC mode", category: "Insights"),
    KeyboardShortcut(keys: "⌘3", description: "Training mode", category: "Insights"),
    KeyboardShortcut(keys: "⌘4", description: "Questions mode", category: "Insights"),
    KeyboardShortcut(keys: "⌘⇧I", description: "Generate insights", category: "Insights"),
    
    // App
    KeyboardShortcut(keys: "⌘/", description: "Show shortcuts", category: "App"),
    KeyboardShortcut(keys: "⌘,", description: "Settings", category: "App"),
]

// MARK: - SwiftUI Environment Integration

struct KeyboardShortcutsKey: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue = KeyboardShortcutsService.shared
}

extension EnvironmentValues {
    var keyboardShortcuts: KeyboardShortcutsService {
        get { self[KeyboardShortcutsKey.self] }
        set { self[KeyboardShortcutsKey.self] = newValue }
    }
}

// MARK: - Keyboard Constants

private let kVK_Escape: UInt16 = 0x35
private let kVK_ANSI_R: UInt16 = 0x0F
private let kVK_ANSI_I: UInt16 = 0x22
private let kVK_ANSI_N: UInt16 = 0x2D
private let kVK_ANSI_H: UInt16 = 0x04
private let kVK_ANSI_J: UInt16 = 0x26
private let kVK_ANSI_K: UInt16 = 0x28
private let kVK_ANSI_1: UInt16 = 0x12
private let kVK_ANSI_2: UInt16 = 0x13
private let kVK_ANSI_3: UInt16 = 0x14
private let kVK_ANSI_Slash: UInt16 = 0x2C
private let kVK_ANSI_LeftBracket: UInt16 = 0x21
private let kVK_ANSI_RightBracket: UInt16 = 0x1E
private let kVK_UpArrow: UInt16 = 0x7E
private let kVK_DownArrow: UInt16 = 0x7D
