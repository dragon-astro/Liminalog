import CryptoKit
import Foundation

enum CloudFriendProfileRecordIDPolicy {
    static func recordName(username: String) -> String {
        "profile:v2:\(sha256Hex(username))"
    }

    static func legacyRecordName(username: String) -> String {
        "profile:\(username)"
    }

    static func lookupRecordNames(username: String) -> [String] {
        let current = recordName(username: username)
        let legacy = legacyRecordName(username: username)
        return current == legacy ? [current] : [current, legacy]
    }

    private static func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
