import Foundation

/// Optional fields keep old SwiftData and Codable records readable without a migration rewrite.
enum PlanExtraDetails {
    static let locationLimit = 100
    static let urlLimit = 2_000

    static func normalized(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    static func isValid(location: String?, url: String?) -> Bool {
        (normalized(location)?.count ?? 0) <= locationLimit && (normalized(url)?.count ?? 0) <= urlLimit
    }

    @discardableResult
    static func openWebURL(_ value: String?, using open: (URL) -> Void) -> Bool {
        guard let url = webURL(value) else { return false }
        open(url)
        return true
    }

    static func webURL(_ value: String?) -> URL? {
        guard let text = normalized(value), text.count <= urlLimit,
              !text.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) })
        else { return nil }
        let candidate = URLComponents(string: text)
        let resolved: URLComponents?
        if candidate?.scheme != nil { resolved = candidate }
        else { resolved = URLComponents(string: "https://" + text) }
        guard let resolved, ["http", "https"].contains(resolved.scheme?.lowercased() ?? ""),
              let host = resolved.host, !host.isEmpty else { return nil }
        return resolved.url
    }
}
