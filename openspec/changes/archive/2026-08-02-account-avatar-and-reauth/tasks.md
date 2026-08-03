# Tasks — account-avatar-and-reauth

## Avatar (tab-bar account switcher)

- [x] Replace bare `AsyncImage` with `FreshAvatarImage` in `RootView.AccountAvatarView` (keep stroke ring, quick-switch chevron overlays, initials fallback)
- [x] Add eager `refreshAccountProfiles` step to the `RULYXApp` launch task chain (non-blocking)
- [x] Call `refreshAccountProfiles` after successful re-authentication

## Auth error plumbing

- [x] Change `BlueskyAPIError.unauthorized` → `unauthorized(String?)`; update `errorDescription`
- [x] `BlueskyRequestExecutor`: pass `errorPayload.message` on 401
- [x] `ChatService`: pass server message in the `isAuthError` branch
- [x] `BlueskySessionService`: pattern-match `.unauthorized(_)` in `performAuthenticatedRequest` + `refreshSession`; verify no other bare `.unauthorized` matches remain (grep all usages)
- [x] `AppError.from`: use server message when present; add `AppError.isAuthenticationFailure(_:)`

## Re-authentication flow

- [x] `AccountStore.reauthenticate(account:appPassword:client:) -> Bool` (authenticate → save keychain password → persist session → clear caches → update account record → post `.accountReauthenticated` → clear errorMessage)
- [x] New notification names: `.authenticationFailed` (userInfo accountID), `.accountReauthenticated` (object account)
- [x] `BlueskySessionService.performAuthenticatedRequest`: post `.authenticationFailed` on exhausted `.unauthorized(_)` / `.missingCredentials`
- [x] `ChatService`: post `.authenticationFailed` in the auth-error branch (covered via `performAuthenticatedRequest` — chat requests run through the session service, which is the single posting point)
- [x] New `ReauthenticationSheet` component (`Sources/Shared/Components/ReauthenticationSheet.swift`)
- [x] `RootView`: observe `.authenticationFailed` → present `ReauthenticationSheet` (`.sheet(item:)`)
- [x] `iPadRootView`: same presentation for iPad
- [x] `RULYXApp`: observe `.accountReauthenticated` → `reloadChatForActiveAccount(showPrompts: true)`

## Localization (all 16 files)

- [x] Add `account.reauth.title`, `account.reauth.message`, `account.reauth.sign_in`, `account.reauth.failed` to `en.json`
- [x] Add keys to `de.json` (native German)
- [x] Add keys to remaining 14 language files (native where possible, "(XX)" marker convention otherwise)

## Verification

- [x] `swiftformat --lint .` / `swiftlint` clean (changed files: 0 format issues; no new serious lint violations)
- [x] `xcodegen generate` + `xcodebuild build-for-testing` succeeds (iPhone Simulator, CODE_SIGNING_ALLOWED=NO)
- [x] `openspec validate account-avatar-and-reauth --json` passes
- [x] Grep confirms no remaining bare `BlueskyAPIError.unauthorized` constructions/matches (tests updated: AppErrorTests, AccountStoreTests, BlueskySessionService401RetryTests, TestHelpers)
- [x] Unit tests run green (`AppErrorTests`, `BlueskySessionService401RetryTests`, `AccountStoreTests` — 147-test suite: only pre-existing `LiveBlueskyClientTests` network-mock failures remain, verified identical on main)
- [x] Fixed pre-existing broken tests on the way: `BlueskySessionService401RetryTests.test401WithRecoveryFailureThrowsUnauthorized` and `ServiceIntegrationTests` (3 tests) failed on main because the mock keychain never seeded the app password — seeded it in setUp/helper so recovery reaches `.unauthorized` as intended
