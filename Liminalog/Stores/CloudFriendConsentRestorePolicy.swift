import Foundation

enum CloudFriendConsentDirection: Equatable {
    case incoming
    case outgoing
}

struct CloudFriendConsentRestoration: Equatable {
    let consent: CloudFriendConsent
    let direction: CloudFriendConsentDirection
    let status: FriendStatus
}

enum CloudFriendConsentRestorePolicy {
    static func restorations(
        incomingConsents: [CloudFriendConsent],
        outgoingConsents: [CloudFriendConsent]
    ) -> [CloudFriendConsentRestoration] {
        var merged: [String: ConsentMerge] = [:]
        var orderedFriendRecordNames: [String] = []

        func upsert(
            consent: CloudFriendConsent,
            direction: CloudFriendConsentDirection
        ) {
            let friendRecordName = friendUserRecordName(from: consent, direction: direction)
            if merged[friendRecordName] == nil {
                orderedFriendRecordNames.append(friendRecordName)
            }
            var merge = merged[friendRecordName] ?? ConsentMerge()
            switch direction {
            case .incoming:
                merge.incoming = consent
            case .outgoing:
                merge.outgoing = consent
            }
            merged[friendRecordName] = merge
        }

        for consent in outgoingConsents {
            upsert(consent: consent, direction: .outgoing)
        }
        for consent in incomingConsents {
            upsert(consent: consent, direction: .incoming)
        }

        return orderedFriendRecordNames.compactMap { friendRecordName in
            guard let merge = merged[friendRecordName],
                  let representative = merge.representative
            else { return nil }
            return CloudFriendConsentRestoration(
                consent: representative.consent,
                direction: representative.direction,
                status: mergedStatus(incoming: merge.incoming, outgoing: merge.outgoing)
            )
        }
    }

    static func friendStatus(
        consentStatus: CloudFriendConsent.Status,
        direction: CloudFriendConsentDirection
    ) -> FriendStatus {
        switch consentStatus {
        case .accepted:
            return .accepted
        case .blocked:
            return .blocked
        case .requested:
            return direction == .incoming ? .pendingIncoming : .pendingOutgoing
        }
    }

    static func friendUserRecordName(
        from consent: CloudFriendConsent,
        direction: CloudFriendConsentDirection
    ) -> String {
        switch direction {
        case .incoming:
            return consent.ownerUserRecordName
        case .outgoing:
            return consent.targetUserRecordName
        }
    }

    static func friendUsername(
        from consent: CloudFriendConsent,
        direction: CloudFriendConsentDirection
    ) -> String {
        switch direction {
        case .incoming:
            return consent.ownerUsername
        case .outgoing:
            return consent.targetUsername
        }
    }

    static func friendDisplayName(
        from consent: CloudFriendConsent,
        direction: CloudFriendConsentDirection
    ) -> String {
        switch direction {
        case .incoming:
            return consent.ownerDisplayName
        case .outgoing:
            return "@\(consent.targetUsername)"
        }
    }

    static func incomingShareURL(
        from consent: CloudFriendConsent,
        direction: CloudFriendConsentDirection
    ) -> String? {
        direction == .incoming && consent.status == .accepted ? consent.shareURL : nil
    }

    static func incomingShareURL(
        from consent: CloudFriendConsent,
        direction: CloudFriendConsentDirection,
        restoredStatus: FriendStatus
    ) -> String? {
        guard restoredStatus == .accepted else { return nil }
        return incomingShareURL(from: consent, direction: direction)
    }

    static func acceptedFriendUserRecordNames(
        in restorations: [CloudFriendConsentRestoration]
    ) -> Set<String> {
        Set(restorations.compactMap { restoration in
            guard restoration.status == .accepted else { return nil }
            return friendUserRecordName(
                from: restoration.consent,
                direction: restoration.direction
            )
        })
    }

    private static func mergedStatus(
        incoming: CloudFriendConsent?,
        outgoing: CloudFriendConsent?
    ) -> FriendStatus {
        let statuses = [incoming?.status, outgoing?.status]
        if statuses.contains(where: { $0 == .blocked }) {
            return .blocked
        }
        if incoming?.status == .accepted,
           outgoing?.status == .requested || outgoing?.status == .accepted {
            return .accepted
        }
        if outgoing?.status == .accepted,
           incoming?.status == .requested || incoming?.status == .accepted {
            return .accepted
        }
        if incoming?.status == .requested, outgoing?.status == .requested {
            return .accepted
        }
        if incoming?.status == .requested {
            return .pendingIncoming
        }
        if outgoing?.status == .requested {
            return .pendingOutgoing
        }
        if incoming?.status == .accepted {
            return .pendingIncoming
        }
        return .pendingOutgoing
    }

    private struct ConsentMerge {
        var incoming: CloudFriendConsent?
        var outgoing: CloudFriendConsent?

        var representative: (consent: CloudFriendConsent, direction: CloudFriendConsentDirection)? {
            if let incoming {
                return (incoming, .incoming)
            }
            if let outgoing {
                return (outgoing, .outgoing)
            }
            return nil
        }
    }
}
