import Foundation

/// Turns the worker's loosely formatted fields into what the UI shows.
enum RemoteMapping {
    static func looksLikeHTML(_ text: String) -> Bool {
        text.range(of: "<(html|body|div|p|br|table|span|a |img|style)", options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Strips markup so list snippets read as plain text.
    static func plainText(_ html: String) -> String {
        guard looksLikeHTML(html) || html.contains("&") else {
            return collapse(html)
        }
        var text = html
        text = text.replacingOccurrences(of: "<(style|script|head)[^>]*>[\\s\\S]*?</\\1>", with: " ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, value) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'")] {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return collapse(text)
    }

    private static func collapse(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
