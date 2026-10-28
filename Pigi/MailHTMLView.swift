import SwiftUI
import WebKit

/// Renders a mail body in a script-free web view. Remote content is blocked by
/// a CSP meta tag unless the reader asks for it.
struct MailHTMLView: NSViewRepresentable {
    let body: String
    let isHTML: Bool
    let allowRemoteContent: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = Self.document(body: body, isHTML: isHTML, allowRemote: allowRemoteContent)
        guard html != context.coordinator.lastHTML else { return }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    static func document(body: String, isHTML: Bool, allowRemote: Bool) -> String {
        let csp = allowRemote
            ? "default-src 'none'; img-src data: https: http:; style-src 'unsafe-inline' https:; font-src data: https:"
            : "default-src 'none'; img-src data:; style-src 'unsafe-inline'"
        let content = isHTML
            ? body
            : "<div style=\"white-space:pre-wrap\">\(RemoteMapping.escapeHTML(body))</div>"
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(csp)">
        <style>
        :root { color-scheme: light; }
        body { font: 14px/1.55 -apple-system, BlinkMacSystemFont, sans-serif; margin: 22px 26px;
               color: #1d1d1f; background: #fff; overflow-wrap: anywhere; }
        img { max-width: 100%; height: auto; }
        pre { white-space: pre-wrap; }
        </style></head><body>\(content)</body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML = ""

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
