import AppKit
import Carbon.HIToolbox

/// The global "show the menu bar panel" key: registered with Carbon, so it needs no Accessibility permission.
@MainActor
final class PanelHotKey {
    static let shared = PanelHotKey()

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// ANSI key codes for the characters a shortcut can use.
    private static let codes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
        "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
        "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "space": kVK_Space, "return": kVK_Return, "tab": kVK_Tab,
        "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period,
        "/": kVK_ANSI_Slash, ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, "[": kVK_ANSI_LeftBracket,
        "]": kVK_ANSI_RightBracket, "\\": kVK_ANSI_Backslash, "`": kVK_ANSI_Grave,
    ]

    func start() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { PanelHotKey.togglePanel() }
            return noErr
        }, 1, &spec, nil, &handler)
        NotificationCenter.default.addObserver(forName: .shortcutsChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PanelHotKey.shared.register() }
        }
        register()
    }

    private func register() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        let combo = ShortcutStore.shared.combo(.showPanel)
        guard let code = Self.codes[combo.key] else { return }
        var modifiers = 0
        if combo.command { modifiers |= cmdKey }
        if combo.option { modifiers |= optionKey }
        if combo.shift { modifiers |= shiftKey }
        if combo.control { modifiers |= controlKey }
        RegisterEventHotKey(UInt32(code), UInt32(modifiers), EventHotKeyID(signature: OSType(0x7067_6931), id: 1),
                            GetApplicationEventTarget(), 0, &ref)
    }

    /// The menu bar item belongs to SwiftUI; clicking its button is the one way to open its window.
    static func togglePanel() {
        for window in NSApp.windows where String(describing: type(of: window)).contains("StatusBar") {
            if let button = findButton(in: window.contentView) {
                NSApp.activate(ignoringOtherApps: true)
                button.performClick(nil)
                return
            }
        }
    }

    private static func findButton(in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton { return button }
        for sub in view.subviews { if let found = findButton(in: sub) { return found } }
        return nil
    }
}
