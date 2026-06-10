import Foundation

enum UserIDValidationError: Equatable, LocalizedError {
    case empty
    case tooShort(minimum: Int)
    case tooLong(maximum: Int)
    case invalidCharacters

    var errorDescription: String? {
        switch self {
        case .empty:
            return "ユーザーIDを入力してください。"
        case let .tooShort(minimum):
            return "ユーザーIDは\(minimum)文字以上にしてください。"
        case let .tooLong(maximum):
            return "ユーザーIDは\(maximum)文字以内にしてください。"
        case .invalidCharacters:
            return "ユーザーIDに使えるのは半角の英小文字・数字・記号（ _ . - ）だけです。"
        }
    }
}

enum UserIDNormalizer {
    nonisolated static let minimumLength = 4
    nonisolated static let maximumLength = 20
    private nonisolated static let displayAtMarks: Set<Character> = ["@", "＠"]
    // 英小文字・数字・一部記号のみ。キリル文字等の見た目が同じ文字（ホモグリフ）による
    // なりすましIDを防ぐため、ASCII外は正規化後も許可しない。
    private nonisolated static let allowedScalars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_.-")

    nonisolated static func normalize(_ rawValue: String) -> Result<String, UserIDValidationError> {
        let trimmed = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutDisplayPrefix = trimmed.first.map(displayAtMarks.contains) == true
            ? String(trimmed.dropFirst())
            : trimmed
        // 日本語キーボードの全角入力（ＲＹＵ１２３）をエラーにせず半角へ寄せる。
        let halfWidth = withoutDisplayPrefix
            .applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? withoutDisplayPrefix
        let normalized = halfWidth
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()

        guard !normalized.isEmpty else {
            return .failure(.empty)
        }
        guard normalized.count >= minimumLength else {
            return .failure(.tooShort(minimum: minimumLength))
        }
        guard normalized.count <= maximumLength else {
            return .failure(.tooLong(maximum: maximumLength))
        }
        guard normalized.unicodeScalars.allSatisfy(allowedScalars.contains) else {
            return .failure(.invalidCharacters)
        }
        return .success(normalized)
    }

    nonisolated static func normalizedValue(_ rawValue: String) -> String? {
        guard case let .success(value) = normalize(rawValue) else { return nil }
        return value
    }
}
