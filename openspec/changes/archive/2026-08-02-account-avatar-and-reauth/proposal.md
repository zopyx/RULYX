## Why

Two account-related UX gaps in the bottom tab bar / error handling:

1. The account switcher button (bottom-right tab bar item) shows the current account's avatar only after a successful profile refresh has populated `avatarURL`. On a cold launch — or when the profile refresh fails (e.g. expired token) — it falls back to a generic `person.crop.circle` icon or an initials circle, so the user can't see at a glance which account is active.
2. When the Bluesky session expires (e.g. the user rotated/revoked the app password on bsky.social), every surface shows an authentication error with only a RETRY button. Retry can never succeed because the stored password is stale — there is no way to re-authenticate, leaving the user locked out of the account.

## What Changes

- **Account switcher avatar (tab bar):** The bottom-right account switcher icon always renders the active account's avatar. The bare `AsyncImage` is replaced with the app's standard `FreshAvatarImage` (ThumbnailPipeline caching, 24h TTL, failure fallback), account profiles are refreshed eagerly at launch, and the avatar is refreshed again after a successful re-authentication.
- **Carry server auth messages:** `BlueskyAPIError.unauthorized` now carries the server-provided error message (e.g. `"Token has expired"`) instead of dropping it, so the user sees the real reason for the failure.
- **Re-authentication flow:** When authentication fails (`unauthorized` / `missingCredentials`), the app posts an `.authenticationFailed` notification; `RootView` (iPhone) and `iPadRootView` (iPad) present a new `ReauthenticationSheet` for the affected account. The sheet lets the user enter a new app password, which re-authenticates against the PDS, updates the Keychain password, replaces the persisted session, clears stale caches, and refreshes the account profile. After success, chat reloads automatically and all RETRY actions succeed again.
- No changes to the account-switch state-reset contract (`switchAccount` remains the only path for switching).

## Capabilities

### New Capabilities

- `account-switcher-avatar`: The bottom-right account switcher icon always displays the active account's avatar (eager profile refresh at launch, cached image loading, refresh after re-auth).
- `session-reauthentication`: When the Bluesky session/token is rejected, the user gets a visible re-login option that updates stored credentials and restores all account-scoped functionality.

### Modified Capabilities

- `quick-account-switch`: The account switcher icon in the tab bar now uses the avatar-based rendering (visual change of the switcher entry point). No requirement changes to switching behavior itself.

## Impact

- `Sources/App/RootView.swift` — tab-bar account switcher icon (avatar rendering, reauth sheet presentation)
- `Sources/App/iPad/iPadRootView.swift` — reauth sheet presentation on iPad
- `Sources/App/RULYXApp.swift` — eager `refreshAccountProfiles` at launch; chat reload on `.accountReauthenticated`
- `Sources/Domain/Models/AppAccount.swift` — unchanged (avatarURL already persisted)
- `Sources/Domain/Services/BlueskyAPIError.swift` — `unauthorized` carries optional server message
- `Sources/Domain/Services/BlueskyRequestExecutor.swift` — pass server message on 401
- `Sources/Domain/Services/ChatService.swift` — pass server message + post `.authenticationFailed`
- `Sources/Domain/Services/BlueskySessionService.swift` — post `.authenticationFailed` when retries are exhausted; new notification names
- `Sources/Domain/Services/AccountStore.swift` — new `reauthenticate(account:appPassword:client:)`; `.accountReauthenticated` notification
- `Sources/Shared/Components/ReauthenticationSheet.swift` — NEW sheet component
- `Sources/Shared/Support/AppError.swift` — auth-error detection helper
- `Sources/Shared/Localizations/*.json` (16 files) — new `account.reauth.*` keys
- UI tests / screenshot tests: unaffected (no launch-flow changes)
