# App Review Notes Draft

## Current No-Paid-Release Submission

Liminalog is a native iOS time logging, calendar, stats, widget, and profile app.

The app does not use in-app purchases, ads, third-party tracking SDKs, or social login.

The friend sharing feature uses iCloud/CloudKit. Users create an in-app user ID, search another user's ID, and sharing starts only after mutual consent. Users can choose what is visible to friends, remove a friend, block a user, and report inappropriate profiles or shared content from the friend's profile menu. Reports are sent to the published support email address.

Push notification capability and the `remote-notification` background mode are used for CloudKit friend-sharing sync signals. They are not used for marketing messages. User-facing reminder notifications can be controlled from the app settings.

The privacy policy is available in Settings > Privacy Policy. Support contact: yuhlab.dev@gmail.com.

If friend sharing needs to be reviewed, use two iCloud-enabled devices or accounts, create user IDs on both devices, then send and approve a friend request from the Friends tab.

## Paid Release Draft

Use this only after the in-app purchase products are created in App Store Connect and `PurchaseConfiguration.current.purchaseEntryPointIsEnabled` is intentionally enabled.

Liminalog offers optional in-app purchases for Pro features, lifetime support, decoration access, and voluntary support tips. Core logging, calendar browsing, friends, and daily card sharing remain available without purchase. The app does not use external payment links or unlock purchased content outside StoreKit.

Pro subscriptions and lifetime purchase unlock deeper analysis features once feature restrictions are explicitly enabled. Lifetime purchase does not include premium decoration rental. Decoration pass subscriptions are shown in the app only for lifetime owners and provide decoration rental access while active. Support tips are voluntary consumables and do not grant permanent feature access.

The yearly Pro subscription includes a one-week free trial as an App Store introductory offer. Monthly Pro, decoration pass subscriptions, lifetime purchase, and support tips do not include a free trial.

The privacy policy is available in Settings > Privacy Policy. Terms of use must be available at `https://liminalog-lp.vercel.app/terms` before the paid release is submitted. Support contact: yuhlab.dev@gmail.com.
