# Design — account-avatar-and-reauth

## Context

Two independent account UX gaps (both small, both in the account layer):

### 1. Tab-bar account switcher icon
`RootView.accountSwitcherButton` (`Sources/App/RootView.swift:89`) renders:
- `AccountAvatarView` — bare SwiftUI `AsyncImage` fed by `account.avatarURL`
- initials circle when `avatarURL == nil`
- `person.crop.circle` when `activeAccount == nil`

`avatarURL` is only populated by `AccountStore.refreshAccountProfiles`, which today runs on `didBecomeActive` and when the Accounts tab / switcher sheet opens. On a cold launch the tab bar therefore shows initials; if the refresh fails (expired token) the avatar never appears. Bare `AsyncImage` also has no failure fallback and no cache — the rest of the app uses `FreshAvatarImage` (ThumbnailPipeline, 24h TTL).

### 2. Auth failure → no re-login option
`BlueskySessionService.performAuthenticatedRequest` (3 attempts: refresh → recreate-with-keychain-password → throw `.unauthorized`) is the single choke point for all authenticated XRPC calls. Chat has its own error mapping in `ChatService` (401 or errorCode containing token/auth → `.unauthorized`, otherwise `.server(message)` — this is where "Token has expired" text can leak through today). When the stored app password is stale (rotated on bsky.social), every surface shows an error with only RETRY; the retry can never succeed because the stored password is stale. The 401 mapping in `BlueskyRequestExecutor` also drops the server message, so the user sees a generic message instead of "Token has expired".

## Decisions

### D1 — Avatar rendering: `FreshAvatarImage` + eager profile refresh
- Replace the private `AccountAvatarView`'s `AsyncImage` with `FreshAvatarImage` (same component as `AccountRowView`, `AccountSummaryCard`, `AccountChip`). Keep the stroke ring + quick-switch chevron overlays unchanged.
- Add `await deps.accountStore.refreshAccountProfiles(using: deps.blueskyClient)` to the launch task chain in `RULYXApp` (new step, runs in background, non-blocking; failures are already swallowed inside `refreshAccountProfiles`).
- After successful re-auth (D3), call `refreshAccountProfiles` again so previously failed avatar fetches recover.

### D2 — `BlueskyAPIError.unauthorized` carries the server message
- Change `case unauthorized` → `case unauthorized(String?)` (message = server payload message, `nil` = generic).
- `BlueskyRequestExecutor` 401 path: `throw BlueskyAPIError.unauthorized(errorPayload.message)` (fall back to `nil` when payload unparseable).
- `ChatService` auth-error path: same, pass `errorPayload.message`.
- `BlueskySessionService`: pattern-match `.unauthorized(_)` in `performAuthenticatedRequest` and `refreshSession`.
- `AppError.from`: `.unauthorized(let message)` → message = `message ?? "Bluesky rejected the credentials. Check the handle and app password."`; keep category `.authentication`.
- Add `AppError.isAuthenticationFailure(_:) -> Bool` helper (true for `.unauthorized`, `.missingCredentials` — used by D4).
- This is a source-compatible change at call sites that only construct/destructure the bare case (`case .unauthorized:` in switches must become `.unauthorized(_)`).

### D3 — `AccountStore.reauthenticate(account:appPassword:client:)`
New `@MainActor` async method:
1. `client.authenticate(handle: account.handle, appPassword: trimmed, entrywayURL: account.entrywayURL ?? account.pdsURL)` → new session (authenticate already resolves the PDS when entryway is nil; pass `account.entrywayURL` to honor custom PDS).
2. `keychain.save(trimmed, service: passwordService, account: account.id.uuidString)` — overwrites the stale password.
3. `client.persistSession(newSession, for: account)` — replaces the cached + persisted session (the session-mismatch guard in `persistSession` checks DID/handle — same account, so it passes).
4. `await client.clearAllCaches()` — drop stale HTTP/API caches (mirrors `switchAccount`).
5. Update account record fields from the session (did/handle/pdsURL may have changed) and `persist()`.
6. `errorMessage = nil`; post `.accountReauthenticated` (object: account).
7. Callers then run `refreshAccountProfiles` (avatar + display name refresh).
Returns `Bool` (success) / sets `errorMessage` on failure (2FA-required accounts surface the error message; app passwords do not trigger 2FA).

No changes to `switchAccount` or the `.accountWillSwitch` contract.

### D4 — Global re-auth prompt via notification
- New notification names (in the existing `Notification.Name` extensions): `.authenticationFailed` (userInfo: `["accountID": String]`) and `.accountReauthenticated` (object: `AppAccount`).
- **Posting side (service layer — covers ALL surfaces automatically):**
  - `BlueskySessionService.performAuthenticatedRequest`: when it throws `.unauthorized(_)` or `.missingCredentials` after exhausting recovery, post `.authenticationFailed` with `account.id`.
  - `ChatService`: on auth-error mapping (the `isAuthError` branch), post `.authenticationFailed` with the account.
- **Presenting side:**
  - `RootView` and `iPadRootView`: `@State reauthRequest: ReauthenticationRequest?` + `.onReceive(publisher(for: .authenticationFailed))` → resolve account by ID → set state → `.sheet(item:)` presenting `ReauthenticationSheet`.
  - `ReauthenticationRequest`: `Identifiable` struct `{ id: UUID, account: AppAccount, reason: String? }` — reason shows the surfaced server message ("Token has expired") above the password field.
- **Recovery side:**
  - `ReauthenticationSheet` "Sign In" → `accountStore.reauthenticate(...)` → on success: dismiss, `refreshAccountProfiles`, post `.accountReanimated`... no — the store posts `.accountReauthenticated`; `RULYXApp` observes it and calls `reloadChatForActiveAccount(showPrompts: true)` (chat auto-recovery). Other surfaces keep their existing RETRY banners; those retries now succeed because the session is valid. A repeated auth failure immediately re-presents the sheet (notification again).

### D5 — New component `ReauthenticationSheet`
`Sources/Shared/Components/ReauthenticationSheet.swift`, NavigationStack + Form:
- Account row (avatar via `FreshAvatarImage`, display name, handle)
- Reason text (when provided, e.g. "Token has expired")
- `SecureField` ("App Password" — reuses `account.add.placeholder.password` key)
- Sign In button (confirmationAction, disabled while `isReauthenticating` / empty field), Cancel (reuses `actions.cancel`)
- Error text inline on failure; sheet stays open
- Localization keys (new, all 16 files): `account.reauth.title`, `account.reauth.message`, `account.reauth.sign_in`, `account.reauth.failed`. Non-translated languages use the existing "(XX)" marker convention (cf. `list.detail.retry_failed` in th/ar/pl).

## Files

| File | Change |
|------|--------|
| `Sources/App/RootView.swift` | `AccountAvatarView` → `FreshAvatarImage`; reauth sheet presentation |
| `Sources/App/iPad/iPadRootView.swift` | reauth sheet presentation |
| `Sources/App/RULYXApp.swift` | launch `refreshAccountProfiles`; `.accountReauthenticated` → chat reload |
| `Sources/Domain/Services/BlueskyAPIError.swift` | `unauthorized(String?)` |
| `Sources/Domain/Services/BlueskyRequestExecutor.swift` | pass server message on 401 |
| `Sources/Domain/Services/ChatService.swift` | pass server message; post `.authenticationFailed` |
| `Sources/Domain/Services/BlueskySessionService.swift` | post `.authenticationFailed`; pattern-match `.unauthorized(_)`; new notification names |
| `Sources/Domain/Services/AccountStore.swift` | `reauthenticate(...)`; `.accountReauthenticated` notification |
| `Sources/Shared/Components/ReauthenticationSheet.swift` | NEW |
| `Sources/Shared/Support/AppError.swift` | `.unauthorized(let msg)` message; `isAuthenticationFailure` |
| `Sources/Shared/Localizations/*.json` (16) | `account.reauth.*` keys |

## Open questions / risks
- Presenting `.sheet` from `RootView` while another sheet is up: iOS queues nested presentation; acceptable (same pattern as existing root-level sheets).
- `unauthorized` is a public-ish enum used in previews/mocks — grep for all usages before changing (see tasks).
- Screenshot tests use `--test-account`; the new launch step (profile refresh) is async and failure-tolerant — no test impact expected.
