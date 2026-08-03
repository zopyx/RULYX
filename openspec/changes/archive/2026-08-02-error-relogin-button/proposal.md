## Why

After the `account-avatar-and-reauth` change, an expired/rejected Bluesky session auto-presents the re-authentication sheet — but the error surfaces themselves still only show a "Retry" button. Retry can never succeed while the stored password is stale, so the user must find the re-login option elsewhere. Requirement: every auth-failure error state must offer "Re-Login" directly.

## What Changes

- New shared `ReauthenticationPromptState` (ObservableObject singleton): tracks whether the most recent account-scoped failure was an authentication failure (observes `.authenticationFailed`, clears on `.accountReauthenticated` / `.accountWillSwitch`) and re-triggers the root-level re-auth sheet via `presentReauthentication()`.
- `ErrorRetryBanner` shows a prominent "Re-Login" button next to "Retry" whenever the state says the failure is an auth failure — automatically covers all 8 banner call sites (Lists, Relationships, Profile, Bulk Lookup, List Search/Members, Profile Inspector) without changing them.
- Chat list + chat detail error states show "Re-Login" when the error is an auth failure (direct `AppError.isAuthenticationFailure` check).
- Timeline `.failed` state gets Retry + Re-Login actions.
- Root-level `.authenticationFailed` handlers fall back to the active account when no accountID is supplied (robust re-presentation).
- New localization key `account.reauth.relogin` in all 16 files.

## Capabilities

### New Capabilities

- `error-relogin-button`: Authentication-failure error states offer a visible "Re-Login" action alongside Retry.

### Modified Capabilities

(none — implementation detail of `session-reauthentication`)

## Impact

- `Sources/Shared/Components/ReauthenticationSheet.swift` — add `ReauthenticationPromptState`
- `Sources/Shared/Components/StatePanels.swift` — `ErrorRetryBanner` Re-Login button
- `Sources/Features/Chat/ConversationListView.swift`, `ConversationDetailView.swift` — Re-Login button
- `Sources/Features/Timeline/FeedTimelineView.swift` — `.failed` actions
- `Sources/App/RootView.swift`, `Sources/App/iPad/iPadRootView.swift` — active-account fallback
- `Sources/Shared/Localizations/*.json` (16 files) — `account.reauth.relogin`
