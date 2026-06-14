# App Review Notes Draft

Liminalog is a native iOS time logging, calendar, stats, widget, and profile app.

The app does not use in-app purchases, ads, third-party tracking SDKs, or social login.

The friend sharing feature uses iCloud/CloudKit. Users create an in-app user ID, search another user's ID, and sharing starts only after mutual consent. Users can choose what is visible to friends, remove a friend, block a user, and report inappropriate profiles or shared content from the friend's profile menu. Reports are sent to the published support email address.

Push notification capability and the `remote-notification` background mode are used for CloudKit friend-sharing sync signals. They are not used for marketing messages. User-facing reminder notifications can be controlled from the app settings.

The privacy policy is available in Settings > Privacy Policy. Support contact: yuhlab.dev@gmail.com.

If friend sharing needs to be reviewed, use two iCloud-enabled devices or accounts, create user IDs on both devices, then send and approve a friend request from the Friends tab.
