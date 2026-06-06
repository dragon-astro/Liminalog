import Foundation

enum CloudFriendProfileRegistrationPolicy {
    static func canRegister(
        requestedUsername: String,
        existingOwnerUsername: String?
    ) -> Bool {
        guard let existingOwnerUsername else {
            return true
        }
        return existingOwnerUsername == requestedUsername
    }
}
