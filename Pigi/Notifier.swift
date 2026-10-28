import AppKit
import Observation
import UserNotifications

/// New-mail banners with the system sound, and what the system currently lets the app do.
@MainActor
@Observable
final class MailNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = MailNotifier()

    enum Access { case unknown, notDetermined, allowed, denied }

    private(set) var access = Access.unknown
    private(set) var soundOn = true

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "notifyNewMail") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "notifyNewMail") }
    }

    private var center: UNUserNotificationCenter { .current() }

    func start() {
        center.delegate = self
        Task { await refresh() }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in await MailNotifier.shared.refresh() }
        }
    }

    /// Reads the system's answer again; the user may have changed it in System Settings.
    func refresh() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: access = .notDetermined
        case .denied: access = .denied
        default: access = .allowed
        }
        soundOn = settings.soundSetting != .disabled
    }

    func requestAccess() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        await refresh()
    }

    func openSystemSettings() {
        let urls = ["x-apple.systempreferences:com.apple.Notifications-Settings.extension",
                    "x-apple.systempreferences:com.apple.preference.notifications"]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    func notify(_ mails: [Mail]) {
        guard Self.enabled, access == .allowed, !mails.isEmpty else { return }
        if mails.count > 3 {
            send(id: "batch-\(UUID().uuidString)", title: "\(mails.count) 封新邮件", body: mails.prefix(3).map(\.subject).joined(separator: "\n"), thread: "pigi")
            return
        }
        for mail in mails {
            let box = mail.accountID.split(separator: "@").first.map(String.init) ?? mail.accountID
            send(id: mail.id, title: mail.senderName.isEmpty ? mail.senderEmail : mail.senderName,
                 body: mail.subject, subtitle: box, thread: mail.accountID)
        }
    }

    private func send(id: String, title: String, body: String, subtitle: String = "", thread: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = .default
        content.threadIdentifier = thread
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // Show the banner even while pigi is in front.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { NSApp.activate(ignoringOtherApps: true) }
    }
}

/// Whether pigi has a Dock icon; without one it lives in the menu bar.
@MainActor
enum DockPolicy {
    static var shown: Bool {
        get { UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "showInDock")
            apply()
        }
    }

    static func apply() {
        NSApp.setActivationPolicy(shown ? .regular : .accessory)
        if shown { NSApp.activate(ignoringOtherApps: true) }
    }
}
