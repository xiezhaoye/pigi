import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state
    @Environment(LayoutState.self) private var layout

    var body: some View {
        @Bindable var layout = layout
        ZStack {
            VisualEffectView(material: .sidebar)
                .ignoresSafeArea()
            HStack(spacing: 0) {
                if layout.sidebarCollapsed {
                    SidebarRail(folded: true)
                        .frame(width: LayoutState.railWidth)
                        .overlay(alignment: .trailing) { EdgeStrip { layout.setSidebarCollapsed(false) } }
                } else {
                    Group {
                        if layout.sidebarWidth < LayoutState.avatarOnlyBelow { SidebarRail() } else { SidebarView() }
                    }
                    .frame(width: layout.sidebarWidth)
                    SidebarHandle()
                }
                PaneCard { MailListView() }
                    .frame(width: layout.listWidth)
                    .padding(.vertical, 8)
                ListHandle(width: $layout.listWidth)
                PaneCard { MailDetailView() }
                    .padding(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 10))
            }
            .ignoresSafeArea(.container, edges: .top)
            WindowConfigurator(lightsX: layout.sidebarCollapsed ? SidebarMetrics.foldedLightsX : SidebarMetrics.trafficLightsX)
                .frame(width: 0, height: 0)
        }
        .focusEffectDisabled()
        .feedbackOverlays()
        .sheet(isPresented: $layout.showingSettings) { SettingsView() }
    }
}
