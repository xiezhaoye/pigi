import AppKit
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色模式"
        case .dark: "深色模式"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    @MainActor func apply() {
        NSApplication.shared.appearance = colorScheme.flatMap { NSAppearance(named: $0 == .dark ? .darkAqua : .aqua) }
    }
}
