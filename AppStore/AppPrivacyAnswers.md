# App Privacy Answers Draft

App Store ConnectのApp Privacy入力前に、実装と公開プライバシーポリシーを最終確認してください。

## Tracking

Tracking: No

理由:
- 広告SDKや第三者トラッキングSDKは使用していない
- ATTを必要とする用途は実装していない

## Data Linked to the User

入力候補:
- User Content: app activity records, notes, profile image, shared calendar/profile content
- Identifiers: in-app user ID, CloudKit user record identifier
- Contact Info: email address only when the user sends a support or report email

用途候補:
- App Functionality
- Customer Support

## Data Not Linked to the User

入力候補:
- Diagnostics, if App Store Connect crash logs or diagnostics are used for support and stability investigation

## Not Collected /確認注意

以下は現時点の実装では明示的な収集・第三者提供を確認していません。

- Location
- Contacts
- Browsing History
- Search History
- Purchases
- Financial Info
- Health and Fitness
- Sensitive Info
- Advertising Data

## Notes

CloudKitのPrivate DatabaseやShared Databaseに保存されるユーザー本人の記録内容は、原則として開発者が直接閲覧するものではありません。ただし、友達共有、ユーザーID検索、通報/問い合わせ、App Store Connect診断に関わる情報は、App Privacyとプライバシーポリシーの説明に含めてください。
