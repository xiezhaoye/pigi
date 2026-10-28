import AppKit
import Observation
import SwiftUI

enum ShortcutAction: String, CaseIterable, Identifiable, Codable {
    case collapseSidebar, expandSidebar
    case nextMail, previousMail, archive, star, delete, refresh
    case backToList, showPanel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .collapseSidebar: "收起邮箱栏"
        case .expandSidebar: "展开邮箱栏"
        case .nextMail: "下一封"
        case .previousMail: "上一封"
        case .archive: "归档"
        case .star: "加星标 / 取消星标"
        case .delete: "删除"
        case .refresh: "刷新"
        case .backToList: "返回列表(菜单栏面板)"
        case .showPanel: "唤起菜单栏面板"
        }
    }

    var isSidebar: Bool { self == .collapseSidebar || self == .expandSidebar }
    /// Works from any app, not only while pigi is in front.
    var isGlobal: Bool { self == .showPanel }

    var defaultCombo: KeyCombo {
        switch self {
        case .collapseSidebar: KeyCombo(key: "1", option: true)
        case .expandSidebar: KeyCombo(key: "2", option: true)
        case .nextMail: KeyCombo(key: "j")
        case .previousMail: KeyCombo(key: "k")
        case .archive: KeyCombo(key: "e")
        case .star: KeyCombo(key: "s")
        case .delete: KeyCombo(key: "delete")
        case .refresh: KeyCombo(key: "r", command: true)
        case .backToList: KeyCombo(key: "i")
        case .showPanel: KeyCombo(key: "m", option: true, control: true)
        }
    }
}

/// One key plus modifiers. Named keys ("delete", "up", …) cover what has no character.
struct KeyCombo: Codable, Equatable {
    var key: String
    var command = false
    var option = false
    var shift = false
    var control = false

    private static let named: [UInt16: String] = [
        51: "delete", 117: "forwardDelete", 126: "up", 125: "down", 123: "left", 124: "right",
        36: "return", 49: "space", 48: "tab",
    ]

    var keyEquivalent: KeyEquivalent {
        switch key {
        case "delete": .delete
        case "forwardDelete": .deleteForward
        case "up": .upArrow
        case "down": .downArrow
        case "left": .leftArrow
        case "right": .rightArrow
        case "return": .return
        case "space": .space
        case "tab": .tab
        default: KeyEquivalent(key.first ?? " ")
        }
    }

    var modifiers: EventModifiers {
        var result: EventModifiers = []
        if command { result.insert(.command) }
        if option { result.insert(.option) }
        if shift { result.insert(.shift) }
        if control { result.insert(.control) }
        return result
    }

    var display: String {
        let symbol: String = switch key {
        case "delete": "⌫"
        case "forwardDelete": "⌦"
        case "up": "↑"
        case "down": "↓"
        case "left": "←"
        case "right": "→"
        case "return": "↩"
        case "space": "Space"
        case "tab": "⇥"
        default: key.uppercased()
        }
        return (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + symbol
    }

    static func from(_ event: NSEvent) -> KeyCombo? {
        let flags = event.modifierFlags
        var combo = KeyCombo(
            key: "",
            command: flags.contains(.command),
            option: flags.contains(.option),
            shift: flags.contains(.shift),
            control: flags.contains(.control)
        )
        if let name = named[event.keyCode] {
            combo.key = name
        } else if let text = event.charactersIgnoringModifiers?.lowercased(), let first = text.first,
                  !first.isNewline, first.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 }) {
            combo.key = String(first)
        } else {
            return nil
        }
        return combo
    }
}

/// The user's key bindings, saved in UserDefaults.
@MainActor
@Observable
final class ShortcutStore {
    static let shared = ShortcutStore()

    private var custom: [String: KeyCombo]

    private init() {
        if let data = UserDefaults.standard.data(forKey: "shortcutCombos"),
           let saved = try? JSONDecoder().decode([String: KeyCombo].self, from: data) {
            custom = saved
        } else {
            custom = [:]
        }
    }

    func combo(_ action: ShortcutAction) -> KeyCombo { custom[action.rawValue] ?? action.defaultCombo }

    /// Assigns a combo; returns the action already using it (nothing changes in that case).
    @discardableResult
    func set(_ combo: KeyCombo, for action: ShortcutAction) -> ShortcutAction? {
        if let clash = ShortcutAction.allCases.first(where: { $0 != action && self.combo($0) == combo }) {
            return clash
        }
        custom[action.rawValue] = combo
        save()
        return nil
    }

    func resetAll() {
        custom = [:]
        save()
    }

    var isDefault: Bool { custom.isEmpty }

    private func save() {
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: "shortcutCombos")
        }
        NotificationCenter.default.post(name: .shortcutsChanged, object: nil)
    }
}

extension Notification.Name {
    static let shortcutsChanged = Notification.Name("pigi.shortcutsChanged")
}

extension View {
    /// Applies the user's current binding for an action.
    @MainActor
    func shortcut(_ action: ShortcutAction) -> some View {
        let combo = ShortcutStore.shared.combo(action)
        return keyboardShortcut(combo.keyEquivalent, modifiers: combo.modifiers)
    }
}
