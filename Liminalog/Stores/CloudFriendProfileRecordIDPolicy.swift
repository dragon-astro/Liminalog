import CryptoKit
import Foundation

enum CloudFriendProfileRecordIDPolicy {
    private static let legacyAllowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_.")

    static func recordName(username: String) -> String {
        "profile:v2:\(sha256Hex(username))"
    }

    static func legacyRecordName(username: String) -> String {
        "profile:\(username)"
    }

    static func lookupRecordNames(username: String) -> [String] {
        let current = recordName(username: username)
        guard canUseLegacyRecordName(username: username) else {
            return [current]
        }
        return [current, legacyRecordName(username: username)]
    }

    static func canUseLegacyRecordName(username: String) -> Bool {
        username.unicodeScalars.allSatisfy { legacyAllowedCharacters.contains($0) }
    }

    private static func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
