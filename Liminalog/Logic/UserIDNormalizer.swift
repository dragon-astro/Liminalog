import Foundation

enum UserIDValidationError: Equatable, LocalizedError {
    case empty
    case tooShort(minimum: Int)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "ユーザーIDを入力してください。"
        case let .tooShort(minimum):
            return "ユーザーIDは\(minimum)文字以上にしてください。"
        }
    }
}

enum UserIDNormalizer {
    nonisolated static let minimumLength = 4
    private nonisolated static let displayAtMarks: Set<Character> = ["@", "＠"]

    nonisolated static func normalize(_ rawValue: String) -> Result<String, UserIDValidationError> {
        let trimmed = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutDisplayPrefix = trimmed.first.map(displayAtMarks.contains) == true
            ? String(trimmed.dropFirst())
            : trimmed
        let normalized = withoutDisplayPrefix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()

        guard !normalized.isEmpty else {
            return .failure(.empty)
        }
        guard normalized.count >= minimumLength else {
            return .failure(.tooShort(minimum: minimumLength))
        }
        return .success(normalized)
    }

    nonisolated static func normalizedValue(_ rawValue: String) -> String? {
        guard case let .success(value) = normalize(rawValue) else { return nil }
        return value
    }
}
