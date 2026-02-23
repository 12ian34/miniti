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
    var onToggleHelp: (() -> Void)?
    var onNavigateUp: (() -> Void)?
    var onNavigateDown: (() -> Void)?
    
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
        
        // Escape - Go home or close help
        if event.keyCode == kVK_Escape {
            // Let the native Settings/Preferences window handle Escape (cancel/close).
            if isSettingsWindowActive() {
                return event
            }
            if showingHelp {
                showingHelp = false
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
        
        // ⌘/ or ⌘? - Toggle help
        if modifiers == .command && event.keyCode == kVK_ANSI_Slash {
            showingHelp.toggle()
            return nil
        }
        
        // Arrow Up or K - Navigate up in history
        if modifiers.isEmpty && (event.keyCode == kVK_UpArrow || event.keyCode == kVK_ANSI_K) {
            onNavigateUp?()
            return nil
        }
        
        // Arrow Down or J - Navigate down in history
        if modifiers.isEmpty && (event.keyCode == kVK_DownArrow || event.keyCode == kVK_ANSI_J) {
            onNavigateDown?()
            return nil
        }
        
        return event
    }
    
    private func isSettingsWindowActive() -> Bool {
        guard let keyWindow = NSApp.keyWindow else { return false }
        let title = keyWindow.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return title == "settings" || title == "preferences"
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
    
    // Navigation
    KeyboardShortcut(keys: "↑ / K", description: "Previous in history", category: "Navigation"),
    KeyboardShortcut(keys: "↓ / J", description: "Next in history", category: "Navigation"),
    KeyboardShortcut(keys: "⌘H", description: "Go home", category: "Navigation"),
    KeyboardShortcut(keys: "Esc", description: "Go home / Close", category: "Navigation"),
    
    // Insights
    KeyboardShortcut(keys: "⌘1", description: "Standard mode", category: "Insights"),
    KeyboardShortcut(keys: "⌘2", description: "MEDDPICC mode", category: "Insights"),
    KeyboardShortcut(keys: "⌘3", description: "Training mode", category: "Insights"),
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
private let kVK_UpArrow: UInt16 = 0x7E
private let kVK_DownArrow: UInt16 = 0x7D
