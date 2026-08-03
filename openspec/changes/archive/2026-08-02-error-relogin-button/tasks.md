# Tasks — error-relogin-button

- [x] Add `ReauthenticationPromptState` (observes `.authenticationFailed` / `.accountReauthenticated` / `.accountWillSwitch`, `presentReauthentication()`)
- [x] `ErrorRetryBanner`: prominent "Re-Login" button when `isAuthFailure`
- [x] `ConversationListView`: Re-Login button on auth failure
- [x] `ConversationDetailView`: Re-Login button on auth failure
- [x] `FeedTimelineView`: `.failed` state gets Retry + Re-Login actions
- [x] `RootView` + `iPadRootView`: fall back to active account when no accountID in notification
- [x] Add `account.reauth.relogin` to all 16 localization files
- [x] Verify: build, swiftformat, swiftlint, unit tests (AppErrorTests), `openspec validate`, archive
