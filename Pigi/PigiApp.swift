import AppKit
import SwiftUI

@main
struct PigiApp: App {
    @State private var state: AppState
    @State private var layout: LayoutState
    @State private var updater = Updater()

    init() {
        let appState = AppState()
        _state = State(initialValue: appState)
        // Syncing belongs to the app, not the window: the menu bar keeps counting after the window closes.
        Task { await appState.runSyncLoop() }
        PanelHotKey.shared.start()
        MailNotifier.shared.start()
        Task { await LocalEngine.shared.start() }
        if !DockPolicy.shown { NSApplication.shared.setActivationPolicy(.accessory) }
        _layout = State(initialValue: LayoutState())
        // The system plates bundle icons in a rounded square; setting the image
        // at runtime keeps the Dock icon transparent while the app is running.
        NSApplication.shared.applicationIconImage = NSImage(named: "Logo")
    }

    var body: some Scene {
        MenuBarExtra {
            MenuPanel()
                .environment(state)
                .environment(layout)
        } label: {
            Image(systemName: "envelope")
            Text("\(state.unreadTotal)")
        }
        .menuBarExtraStyle(.window)

        WindowGroup(id: "main") {
            RootView()
                .environment(state)
                .environment(layout)
                .environment(updater)
                .task { await updater.check() }
                .frame(minWidth: 1020, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandMenu("视图") {
                Button("收起邮箱栏") { layout.setSidebarCollapsed(true) }.shortcut(.collapseSidebar)
                Button("展开邮箱栏") { layout.setSidebarCollapsed(false) }.shortcut(.expandSidebar)
            }
            CommandGroup(after: .newItem) {
                Button("刷新") { Task { await state.reloadAll() } }
                    .shortcut(.refresh)
            }
        }
    }
}
