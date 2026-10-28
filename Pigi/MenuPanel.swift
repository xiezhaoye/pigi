import AppKit
import SwiftUI

/// The panel's own view state, so browsing it never moves the main window's selection.
@Observable @MainActor
final class PanelModel {
    /// The last mailbox picked, kept across launches.
    var scope: Scope = {
        guard let saved = UserDefaults.standard.string(forKey: "panelScope"), saved != "all" else { return .all }
        return .account(saved)
    }() {
        didSet {
            if case .account(let id) = scope { UserDefaults.standard.set(id, forKey: "panelScope") }
            else { UserDefaults.standard.set("all", forKey: "panelScope") }
        }
    }
    var unreadOnly = false { didSet { stayVisible = [] } }
    var searchText = "" { didSet { stayVisible = [] } }
    var openedID: String?
    var picking = false
    /// Mails read in this view stay listed under the unread filter until it changes.
    var stayVisible: Set<String> = []
}

/// Menu bar window: the mail list under a mailbox picker, with the body opened in place.
struct MenuPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @State private var model = PanelModel()

    private var mails: [Mail] {
        state.filteredMails(scope: model.scope, readFilter: model.unreadOnly ? .unread : .all,
                            stay: model.stayVisible, query: model.searchText)
    }

    var body: some View {
        PaneCard {
            if let mail = state.mails.first(where: { $0.id == model.openedID }) {
                MailDetailContent(mail: mail, inset: 18, onBack: { model.openedID = nil })
                    .background {
                        Group {
                            Button("") { step(1) }.shortcut(.nextMail)
                            Button("") { step(-1) }.shortcut(.previousMail)
                            Button("") { model.openedID = nil }.shortcut(.backToList)
                        }
                        .opacity(0).allowsHitTesting(false)
                    }
            } else {
                list
            }
        }
        .padding(8)
        .frame(width: 454, height: 680)
        .background(VisualEffectView(material: .sidebar))
        .overlay { if model.picking && model.openedID == nil { picker } }
        .feedbackOverlays()
        .environment(model)
        .onAppear {
            if case .account(let id) = model.scope, !state.accounts.contains(where: { $0.id == id }) { model.scope = .all }
        }
    }

    // MARK: Mailbox picker

    private var unreadForScope: Int { state.unreadCount(model.scope) }

    /// The round icon for the current mailbox (or the tray for all), with its unread count.
    private func badge(_ count: Int, size: CGFloat = 17) -> some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 4.5)
            .frame(minWidth: size, minHeight: size)
            .background(Color.accentColor, in: Capsule())
    }

    private func icon(for scope: Scope, size: CGFloat) -> some View {
        Group {
            switch scope {
            case .all:
                Image(systemName: "tray.2")
                    .font(.system(size: size * 0.5))
                    .frame(width: size, height: size)
                    .background(Color.primary.opacity(0.08), in: Circle())
            case .account(let id):
                if let account = state.accounts.first(where: { $0.id == id }) {
                    AvatarView(name: state.accountAliases[id] ?? account.name, size: size,
                               imageURL: state.accountAliases[id] == nil ? account.avatarURL : nil)
                } else {
                    Circle().fill(Color.primary.opacity(0.08)).frame(width: size, height: size)
                }
            }
        }
    }

    private var picker: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001).onTapGesture { model.picking = false }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    pickerRow(title: "打开主窗口", subtitle: nil, count: 0, selected: false,
                              icon: AnyView(Image(systemName: "macwindow").font(.system(size: 13)).frame(width: 28, height: 28))) {
                        model.picking = false
                        showMainWindow()
                    }
                    Divider().padding(.vertical, 4)
                    pickerRow(title: "全部邮件", subtitle: nil, count: state.unreadCount(.all), selected: model.scope == .all,
                              icon: AnyView(icon(for: .all, size: 28))) { pick(.all) }
                    ForEach(state.sidebarGroups.filter { !$0.accounts.isEmpty }) { entry in
                        ForEach(entry.accounts) { account in
                            let alias = state.accountAliases[account.id]
                            pickerRow(title: alias ?? account.email, subtitle: alias == nil ? nil : account.email,
                                      count: state.unreadCount(.account(account.id)),
                                      selected: model.scope == .account(account.id),
                                      icon: AnyView(icon(for: .account(account.id), size: 28))) { pick(.account(account.id)) }
                        }
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.never)
            .frame(width: 262)
            .frame(maxHeight: 460)
            .fixedSize(horizontal: false, vertical: true)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
            .padding(.leading, 14)
            .padding(.top, 58)
            .transition(.scale(scale: 0.96, anchor: .topLeading).combined(with: .opacity))
        }
    }

    private func pickerRow(title: String, subtitle: String?, count: Int, selected: Bool, icon: AnyView,
                           action: @escaping () -> Void) -> some View {
        PickerRow(title: title, subtitle: subtitle, count: count, selected: selected, icon: icon, action: action)
    }

    private func pick(_ scope: Scope) {
        model.scope = scope
        model.openedID = nil
        model.picking = false
    }

    // MARK: List

    private var list: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { withAnimation(.easeOut(duration: 0.15)) { model.picking.toggle() } } label: {
                    HStack(spacing: 8) {
                        icon(for: model.scope, size: 30)
                            .overlay(alignment: .topTrailing) {
                                if unreadForScope > 0 { badge(unreadForScope).offset(x: 6, y: -5) }
                            }
                        Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(model.picking ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                ReadToggle(isUnread: Binding(get: { model.unreadOnly }, set: { model.unreadOnly = $0 }))
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            searchField
            let sections = AppState.sections(of: mails)
            if sections.isEmpty {
                Spacer()
                Text(model.unreadOnly ? "没有未读邮件" : "没有邮件").foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(sections) { section in
                            Text(section.title)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 12)
                                .padding(.bottom, 6)
                            ForEach(section.mails) { mail in
                                MailRow(mail: mail, showsAccount: model.scope == .all, isSelected: false, verticalPadding: 15, shortAccount: true) { open(mail) }
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.never)
            }
        }
    }

    private var title: String {
        switch model.scope {
        case .all: "所有邮件"
        case .account(let id): state.accountAliases[id] ?? Self.userName(id)
        }
    }

    /// The part before the @, for the places that already say which mailbox this is.
    static func userName(_ email: String) -> String {
        email.split(separator: "@").first.map(String.init) ?? email
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索邮件", text: Binding(get: { model.searchText }, set: { model.searchText = $0 }))
                .textFieldStyle(.plain)
            if !model.searchText.isEmpty {
                Button { model.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    // MARK: Actions

    private func open(_ mail: Mail) {
        model.openedID = mail.id
        model.stayVisible.insert(mail.id)
        state.markOpened(mail)
    }

    /// J / K inside an opened mail: the neighbour in the list as it was when the mail was opened.
    private func step(_ delta: Int) {
        let list = mails
        guard let current = list.firstIndex(where: { $0.id == model.openedID }) else { return }
        let next = current + delta
        guard list.indices.contains(next) else { return }
        open(list[next])
    }

    private func showMainWindow() {
        NSApp.keyWindow?.close() // the panel itself
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}

/// One line of the mailbox picker.
private struct PickerRow: View {
    let title: String
    let subtitle: String?
    let count: Int
    let selected: Bool
    let icon: AnyView
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack { if selected { SelectionDot() } }.frame(width: 8)
                icon
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13.5, weight: selected ? .semibold : .regular)).lineLimit(1)
                    if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 6)
                if count > 0 {
                    Text(count > 99 ? "99+" : "\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(Color.accentColor, in: Capsule())
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 40)
            .background(Color.primary.opacity(hovering ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
