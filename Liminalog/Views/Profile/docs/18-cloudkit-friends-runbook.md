# CloudKit Friends Runbook

このメモは、ユーザーID検索、相互同意、公開設定に従う友達共有を実機で確認するためのチェックリスト。

## Data Model

Public Database:

- `PublicProfile`
  - record name: `profile:<normalizedUserID>`
  - fields: `username`, `displayName`, `ownerUserRecordName`, `ownerAppUserID`, `createdAt`, `updatedAt`
  - exact search is done by record name, not by a public query.
- `FriendConsent`
  - record name: `consent:<ownerUserRecordName>:<targetUserRecordName>`
  - fields: `ownerUserRecordName`, `targetUserRecordName`, `ownerUsername`, `targetUsername`, `ownerDisplayName`, `shareURL`, `status`, `createdAt`, `updatedAt`
  - public data is limited to profile, consent status, and the private share URL. Schedule and activity details must not be stored in the public database.

Private/shared database:

- `FriendShareSnapshot`
  - root record name: `friend-share:<ownerUserRecordName>:<targetUserRecordName>`
  - shared through `CKShare` with `publicPermission = none` and the target iCloud user as a read-only participant.
  - fields: `ownerUsername`, `ownerDisplayName`, `targetUserRecordName`, `currentStatusTitle`, `currentStatusIcon`, `currentStatusColorHex`, `currentMoodText`, `currentStatusStartedAt`, `todayScore`, `yesterdayScore`, `weekScore`, `monthScore`, `yearScore`, `streakCount`, `sharedPlansJSON`, `sharedActivitiesJSON`, `updatedAt`

## Dashboard Requirements

- CloudKit container: `iCloud.app.YasudaRyuga.Liminalog`
- `FriendConsent.targetUserRecordName` must be queryable because incoming requests and CloudKit subscriptions filter by it.
- Deploy the development schema to production before TestFlight or App Store distribution.
- Confirm silent push capability is active: `UIBackgroundModes` includes `remote-notification`, and devices can register for remote notifications.
- Confirm subscriptions are created for both public `FriendConsent` changes and shared database `FriendShareSnapshot` changes.
- Confirm `FriendShareSnapshot` records only appear in the owner private database and recipient shared database, never in the public database.

## Device Test Matrix

Use two real devices with different iCloud accounts.

1. Account A creates a user ID with the 3-character minimum-length rule.
2. Account B creates a different user ID.
3. Account B tries Account A's ID and sees a duplicate/taken error.
4. Account A deletes/reinstalls or clears local data, enters the same user ID, and the existing CloudKit profile is reclaimed instead of showing a duplicate error.
5. Account A searches Account B's ID and sends a request.
6. Before Account B accepts, confirm Account A's outgoing `FriendConsent` is `requested` with no `shareURL`, and no readable `FriendShareSnapshot` is available to Account B.
7. Account B receives the request after CloudKit push or manual refresh.
8. Account B accepts.
9. Account A receives the accepted consent after CloudKit push or manual refresh.
10. Both sides receive the other's shared snapshot.
11. Set visibility to none and confirm scores, plans, active activity, and mood do not leak.
12. Set visibility to selected friends and confirm only accepted selected friends receive the data.
13. Exclude categories and confirm those plans/activities are not present in `sharedPlansJSON` or `sharedActivitiesJSON`.
14. Change a friend's visibility preset or category audience, then confirm the recipient's `FriendShareSnapshot` updates by shared database push. Use manual refresh only as a fallback.
15. Delete or block a friend, then confirm the outgoing `FriendShareSnapshot`/`CKShare` is revoked, own `FriendConsent` becomes `blocked`, and the other device stops sharing back after refresh or push.
16. Kill and relaunch both apps, then confirm user ID, friend list, and latest accepted snapshots remain.
17. Delete and reinstall the app on one device, sign into the same iCloud account, then confirm CloudKit profile/consent/share can be restored by opening Friends and refreshing.

## Latency Notes

CloudKit query/database subscriptions and silent pushes are best-effort and can be delayed or coalesced by the system. The Friends screen registers a public `FriendConsent` query subscription for the current user and a shared database subscription for accepted `FriendShareSnapshot` updates. The app-level refresh coordinator refetches accepted incoming shares when the shared database push arrives. The manual refresh button must remain available as the fallback path during real-device testing.

Record p50/p95 latency during the two-account test:

- request creation -> recipient request visible
- accept -> requester accepted state visible
- visibility change/share update -> recipient snapshot updated
