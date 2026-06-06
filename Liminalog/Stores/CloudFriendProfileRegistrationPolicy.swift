import Foundation

enum CloudFriendProfileRegistrationPolicy {
    static func registeredUsername(
        requestedUsername: String,
        ownerIndexUsername: String?,
        ownedProfileUsernames: [String]
    ) -> String? {
        if let ownerIndexUsername {
            return ownerIndexUsername
        }

        let uniqueUsernames = Set(ownedProfileUsernames).sorted()
        if uniqueUsernames.count <= 1 {
            return uniqueUsernames.first
        }
        return uniqueUsernames.first { $0 != requestedUsername } ?? uniqueUsernames[0]
    }

    static func canRegister(
        requestedUsername: String,
        registeredUsername: String?
    ) -> Bool {
        guard let registeredUsername else {
            return true
        }
        return registeredUsername == requestedUsername
    }
}
