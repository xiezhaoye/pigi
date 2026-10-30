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
    static let codeCategory = "PIGI_VERIFICATION_CODE"
    static let copyCodeAction = "PIGI_COPY_VERIFICATION_CODE"
    static let codeKey = "verificationCode"
    var onOpenMail: ((String) -> Void)?

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "notifyNewMail") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "notifyNewMail") }
    }

    private var center: UNUserNotificationCenter { .current() }

    static var categories: Set<UNNotificationCategory> {
        let copy = UNNotificationAction(identifier: Self.copyCodeAction, title: "复制验证码", options: [.authenticationRequired])
        return [
            UNNotificationCategory(identifier: Self.codeCategory, actions: [copy], intentIdentifiers: [], options: [])
        ]
    }

    func start() {
        center.delegate = self
        center.setNotificationCategories(Self.categories)
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
        for request in Self.requests(for: mails) { center.add(request) }
    }

    /// Keep code-bearing messages individual even when other mail is grouped.
    static func requests(for mails: [Mail]) -> [UNNotificationRequest] {
        let codes = mails.filter { $0.code?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        let codeIDs = Set(codes.map(\.id))
        let ordinary = mails.filter { !codeIDs.contains($0.id) }
        var requests: [UNNotificationRequest] = []
        if ordinary.count > 3 {
            requests.append(request(id: "batch-\(UUID().uuidString)", title: "\(ordinary.count) 封新邮件",
                                    body: ordinary.prefix(3).map(\.subject).joined(separator: "\n"), thread: "pigi"))
        }
        for mail in codes + (ordinary.count > 3 ? [] : ordinary) {
            let box = mail.accountID.split(separator: "@").first.map(String.init) ?? mail.accountID
            requests.append(request(id: mail.id, title: mail.senderName.isEmpty ? mail.senderEmail : mail.senderName,
                                    body: mail.subject, subtitle: box, thread: mail.accountID, code: mail.code))
        }
        return requests
    }

    private static func request(id: String, title: String, body: String, subtitle: String = "", thread: String,
                                code: String? = nil) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = .default
        content.threadIdentifier = thread
        content.userInfo = ["mailID": id]
        if let code = code?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty {
            content.categoryIdentifier = codeCategory
            content.userInfo[codeKey] = code
        }
        return UNNotificationRequest(identifier: id, content: content, trigger: nil)
    }

    @discardableResult
    static func copyVerificationCode(from info: [AnyHashable: Any], to pasteboard: NSPasteboard = .general) -> Bool {
        guard let code = info[codeKey] as? String, !code.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(code, forType: .string)
    }

    // Show the banner even while pigi is in front.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run {
            let info = response.notification.request.content.userInfo
            if response.actionIdentifier == Self.copyCodeAction {
                Self.copyVerificationCode(from: info)
            } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                if let id = info["mailID"] as? String { onOpenMail?(id) }
                MainWindow.show()
            }
        }
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
