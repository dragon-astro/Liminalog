enum CloudFriendConsentSubscriptionScope: CaseIterable, Equatable {
    case incomingTarget
    case outgoingOwner

    var fieldName: String {
        switch self {
        case .incomingTarget:
            "targetUserRecordName"
        case .outgoingOwner:
            "ownerUserRecordName"
        }
    }

    var idComponent: String {
        switch self {
        case .incomingTarget:
            "target"
        case .outgoingOwner:
            "owner"
        }
    }
}

enum CloudFriendConsentSubscriptionPolicy {
    static func subscriptionID(
        forOwnUserRecordName ownUserRecordName: String,
        scope: CloudFriendConsentSubscriptionScope
    ) -> String {
        "\(CloudKitFriendEventBridge.friendConsentSubscriptionPrefix)\(scope.idComponent):\(ownUserRecordName)"
    }
}
