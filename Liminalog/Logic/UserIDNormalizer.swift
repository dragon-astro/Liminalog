import Foundation

enum UserIDValidationError: Equatable, LocalizedError {
    case empty
    case tooShort(minimum: Int)
    case invalidCharacters

    var errorDescription: String? {
        switch self {
        case .empty:
            return "ユーザーIDを入力してください。"
        case let .tooShort(minimum):
            return "ユーザーIDは\(minimum)文字以上にしてください。"
        case .invalidCharacters:
            return "ユーザーIDは半角英数字、_、. だけ使えます。"
        }
    }
}

enum UserIDNormalizer {
    static let minimumLength = 3

    private static let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_.")

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
        guard normalized.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
            return .failure(.invalidCharacters)
        }
        return .success(normalized)
    }

    static func normalizedValue(_ rawValue: String) -> String? {
        guard case let .success(value) = normalize(rawValue) else { return nil }
        return value
    }
}
