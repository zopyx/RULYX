# Design — error-relogin-button

## Context

`account-avatar-and-reauth` added the auto-presented re-auth sheet, but error surfaces (banners, chat error states, timeline failed state) still show only "Retry". The Retry button can never succeed while the stored app password is stale.

## Decisions

### D1 — Shared prompt state, zero call-site changes for banners
New `ReauthenticationPromptState` (`@MainActor final class`, `ObservableObject`, `static let shared` — same pattern as `AppLockManager.shared`/`ClearskyHeartbeatService.shared`):
- Observes `.authenticationFailed` → sets `isAuthFailure = true`, stores `reason` + `failedAccountID`.
- Observes `.accountReauthenticated` and `.accountWillSwitch` → resets all fields.
- `presentReauthentication()` re-posts `.authenticationFailed` (with stored accountID + reason) so the existing root-level observers (`RootView` / `iPadRootView`) present the sheet — single presentation path.

`ErrorRetryBanner` holds `@ObservedObject private var reauthPrompt = ReauthenticationPromptState.shared` and renders a prominent "Re-Login" button when `reauthPrompt.isAuthFailure`. All 8 call sites are covered without modification.

### D2 — Direct checks where the full Error is available
Chat surfaces hold the real `Error` (`chatStore.error`, `chatStore.messageError`): show Re-Login when `AppError.isAuthenticationFailure(error)`; the button action calls `ReauthenticationPromptState.shared.presentReauthentication()`.

### D3 — Timeline failed state
`FeedTimelineView` `.failed(msg)` currently has no actions. Add Retry (reload) + Re-Login (state-driven) via `ContentUnavailableView` actions.

### D4 — Robust re-presentation fallback
`RootView`/`iPadRootView` `.authenticationFailed` handlers fall back to `accountStore.activeAccount` when no `accountID` is in `userInfo` (so re-posts without an ID still present the sheet).

## Files

| File | Change |
|------|--------|
| `Sources/Shared/Components/ReauthenticationSheet.swift` | + `ReauthenticationPromptState` |
| `Sources/Shared/Components/StatePanels.swift` | `ErrorRetryBanner` Re-Login button |
| `Sources/Features/Chat/ConversationListView.swift` | Re-Login in chat error state |
| `Sources/Features/Chat/ConversationDetailView.swift` | Re-Login in message error state |
| `Sources/Features/Timeline/FeedTimelineView.swift` | `.failed` actions (Retry + Re-Login) |
| `Sources/App/RootView.swift`, `Sources/App/iPad/iPadRootView.swift` | active-account fallback in handler |
| `Sources/Shared/Localizations/*.json` (16) | `account.reauth.relogin` |

## Risks
- Notification observers on the shared state live for the app lifetime (intentional — same as `AccountStore`'s own observers).
- `@ObservedObject` singleton in a View property initializer: established pattern in this codebase (`RULYXApp` uses `AppLockManager.shared` the same way).
