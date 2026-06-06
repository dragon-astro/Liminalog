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
    static let minimumLength = 3

    static func normalize(_ rawValue: String) -> Result<String, UserIDValidationError> {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty else {
            return .failure(.empty)
        }
        guard normalized.count >= minimumLength else {
            return .failure(.tooShort(minimum: minimumLength))
        }
        return .success(normalized)
    }

    static func normalizedValue(_ rawValue: String) -> String? {
        guard case let .success(value) = normalize(rawValue) else { return nil }
        return value
    }
}
