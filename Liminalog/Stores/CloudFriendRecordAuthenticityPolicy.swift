import CloudKit
import Foundation

/// Public Database のレコードは任意のiCloudユーザーが任意のフィールド値で作成できるため、
/// `ownerUserRecordName` フィールドは自己申告にすぎない。第三者が他人名義の同意レコードを
/// 偽造すると、被害者側のアプリが友達関係を復元して共有を公開してしまう。
/// サーバーが改竄不能な形で付与する `creatorUserRecordID` と照合し、
/// 「名義人が自分で作ったレコード」だけを信頼する。
enum CloudFriendRecordAuthenticityPolicy {
    /// - Parameters:
    ///   - claimedOwnerUserRecordName: レコードのフィールドが名乗る所有者。
    ///   - creatorUserRecordName: サーバーが記録した実際の作成者（`creatorUserRecordID`）。
    ///   - currentUserRecordName: 現在サインイン中のユーザー。
    static func isAuthentic(
        claimedOwnerUserRecordName: String,
        creatorUserRecordName: String?,
        currentUserRecordName: String?
    ) -> Bool {
        guard let creatorUserRecordName, !creatorUserRecordName.isEmpty else {
            // サーバーから取得したレコードには必ず creator が付く。欠けるのは
            // 保存直後に返却された自己生成レコードなどに限られるため、自分名義のみ信頼する。
            return isCurrentUser(claimedOwnerUserRecordName, currentUserRecordName: currentUserRecordName)
        }
        if creatorUserRecordName == CKCurrentUserDefaultName {
            // 自分が作成したレコードの creator は "__defaultOwner__" で返ることがある。
            return isCurrentUser(claimedOwnerUserRecordName, currentUserRecordName: currentUserRecordName)
        }
        return creatorUserRecordName == claimedOwnerUserRecordName
    }

    private static func isCurrentUser(
        _ claimedOwnerUserRecordName: String,
        currentUserRecordName: String?
    ) -> Bool {
        guard let currentUserRecordName, !currentUserRecordName.isEmpty else { return false }
        return claimedOwnerUserRecordName == currentUserRecordName
    }
}
