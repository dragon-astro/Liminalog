import Foundation
import SwiftData

/// 自分が公開した個別アイテムの台帳（docs/20 §2.1 のupsert/delete同期用）。
/// 「前回 CloudKit に置いた内容」を指紋で覚えておき、毎回ゾーンを読み直さずに
/// ローカルの可視セットとの差分だけを送信する。LocalCache ストア（CloudKit同期なし）。
@Model
final class FriendSharePublishedItem {
    #Index<FriendSharePublishedItem>([\.targetUserRecordName])

    var targetUserRecordName: String = ""
    /// "plan" / "chapter"
    var kindRawValue: String = ""
    var sourceID: UUID = UUID()
    /// 公開時点の内容の安定ハッシュ。内容・可視性マスクが変わると変化する。
    var fingerprint: String = ""

    init() {}

    init(targetUserRecordName: String, kindRawValue: String, sourceID: UUID, fingerprint: String) {
        self.targetUserRecordName = targetUserRecordName
        self.kindRawValue = kindRawValue
        self.sourceID = sourceID
        self.fingerprint = fingerprint
    }
}

/// 受信側のゾーン変更トークン（docs/20 §2.2 の差分同期用）。友達=共有ゾーン1つにつき1行。
/// LocalCache ストア（CloudKit同期なし）。
@Model
final class FriendShareZoneSyncState {
    /// 共有ゾーンのオーナー（=友達）の user record name。
    var ownerUserRecordName: String = ""
    /// `CKServerChangeToken` をアーカイブしたもの。nil なら次回は全件取得。
    var changeTokenData: Data?
    var updatedAt: Date = Date()

    init() {}

    init(ownerUserRecordName: String) {
        self.ownerUserRecordName = ownerUserRecordName
    }
}
