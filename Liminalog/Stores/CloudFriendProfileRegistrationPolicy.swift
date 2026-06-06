import Foundation

enum CloudFriendProfileRegistrationPolicy {
    static func registeredUsername(
        requestedUsername: String,
        ownerIndexUsername: String?,
        ownedProfileUsernames: [String]
    ) -> String? {
        if let ownerIndexUsername {
            return normalizedUsername(ownerIndexUsername)
        }

        let uniqueUsernames = Set(ownedProfileUsernames.map(normalizedUsername)).sorted()
        if uniqueUsernames.count <= 1 {
            return uniqueUsernames.first
        }
        let requestedUsername = normalizedUsername(requestedUsername)
        return uniqueUsernames.first { $0 != requestedUsername } ?? uniqueUsernames[0]
    }

    static func canRegister(
        requestedUsername: String,
        registeredUsername: String?
    ) -> Bool {
        guard let registeredUsername else {
            return true
        }
        return normalizedUsername(registeredUsername) == normalizedUsername(requestedUsername)
    }

    private static func normalizedUsername(_ username: String) -> String {
        UserIDNormalizer.normalizedValue(username) ?? username
    }
}
