## Why

Users managing multiple Bluesky accounts (e.g., personal + moderation) frequently switch between them. Currently this requires tapping the account icon, waiting for the sheet, then tapping the target account — a 3-step process. A double-tap gesture on the account switcher button to toggle between the last two active accounts reduces this to a single double-tap, making multi-account workflows dramatically faster.

## What Changes

- **Track previous active account**: `AccountStore` remembers the previously active account ID. Every time `switchAccount()` is called, the current account becomes the "previous" before switching.
- **Double-tap gesture on account switcher**: The account avatar button in the bottom tab bar (rightmost position) supports double-tap to switch to the previous account.
- **Haptic feedback**: A distinct haptic (impact rigid) on double-tap switch to confirm the action.
- **Visual indicator**: When a previous account is available, a subtle visual hint (e.g., a small arrow badge) appears on the account avatar.

## Capabilities

### New Capabilities
- `quick-account-switch`: Double-tap the account switcher to toggle between the last two active accounts.

### Modified Capabilities
- *(none — pure new feature, no spec-level requirement changes)*

## Impact

- **Files modified**: `Sources/Domain/Services/AccountStore.swift`, `Sources/App/RootView.swift`
- **No API changes** — all internal to the app
- **No data model changes** — new property only on `AccountStore`
- **No new dependencies**
