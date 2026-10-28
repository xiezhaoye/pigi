import AppKit
import AuthenticationServices
import CryptoKit
import Foundation

/// Google OAuth for an installed app: system browser sign-in with PKCE.
/// The client is of type "iOS", so there is no client secret and the redirect
/// is the reversed client id used as a custom URL scheme.
enum GmailAuth {
    /// The OAuth client ID the user created in their own Google Cloud project (see docs/gmail-api.md).
    static var clientID: String {
        get { UserDefaults.standard.string(forKey: "gmailClientID") ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "gmailClientID") }
    }
    static var isConfigured: Bool { clientID.hasSuffix(".apps.googleusercontent.com") }
    static let scopes = [
        "https://www.googleapis.com/auth/gmail.modify",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
        "openid",
    ]

    private static var redirectScheme: String {
        "com.googleusercontent.apps." + clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
    }
    private static var redirectURI: String { "\(redirectScheme):/oauth2redirect" }

    struct Token {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date
    }

    enum AuthError: LocalizedError {
        case cancelled
        case denied(String)
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case .cancelled: "已取消登录"
            case .denied(let reason): "Google 拒绝了请求:\(reason)"
            case .badResponse(let detail): "Google 返回了意外的内容:\(detail)"
            }
        }
    }

    // MARK: - Sign in

    @MainActor
    static func signIn() async throws -> (email: String, token: Token) {
        guard isConfigured else { throw AuthError.badResponse("请先在 设置 › 邮箱管理 里填入你自己的 Google OAuth 客户端 ID") }
        let verifier = randomString(byteCount: 48)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = randomString(byteCount: 16)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "access_type", value: "offline"),
            // Always show the account chooser (several accounts are added one by one)
            // and force consent so a refresh token is issued every time.
            .init(name: "prompt", value: "select_account consent"),
        ]

        let callback = try await WebSession.run(url: components.url!, scheme: redirectScheme)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let error = value("error") {
            throw error == "access_denied" ? AuthError.cancelled : AuthError.denied(error)
        }
        guard value("state") == state, let code = value("code") else {
            throw AuthError.badResponse("授权回调缺少 code 或 state 不匹配")
        }

        let token = try await tokenRequest([
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
        ])
        let email = try await userEmail(accessToken: token.accessToken)
        return (email, token)
    }

    // MARK: - Refresh

    static func refresh(_ refreshToken: String) async throws -> Token {
        try await tokenRequest([
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ])
    }

    private static func tokenRequest(_ form: [String: String]) async throws -> Token {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        struct Response: Decodable {
            let access_token: String?
            let refresh_token: String?
            let expires_in: Double?
            let error: String?
            let error_description: String?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        if let error = response.error {
            throw AuthError.denied([error, response.error_description].compactMap { $0 }.joined(separator: ": "))
        }
        guard let access = response.access_token else { throw AuthError.badResponse("没有 access_token") }
        return Token(
            accessToken: access,
            refreshToken: response.refresh_token,
            expiresAt: Date().addingTimeInterval((response.expires_in ?? 3600) - 60)
        )
    }

    private static func userEmail(accessToken: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v3/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        struct Info: Decodable { let email: String? }
        guard let email = try JSONDecoder().decode(Info.self, from: data).email else {
            throw AuthError.badResponse("没有取到邮箱地址")
        }
        return email.lowercased()
    }

    private static func randomString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return Data(bytes).base64URL
    }
}

/// Bridges ASWebAuthenticationSession to async/await.
@MainActor
private final class WebSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    static func run(url: URL, scheme: String) async throws -> URL {
        let runner = WebSession()
        return try await runner.start(url: url, scheme: scheme)
    }

    private func start(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: GmailAuth.AuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? GmailAuth.AuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            self.session = session
            if !session.start() {
                continuation.resume(throwing: GmailAuth.AuthError.badResponse("无法打开登录窗口"))
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension CharacterSet {
    /// Everything except the characters that are special inside a form value.
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
