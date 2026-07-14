## Context

Users with multiple Bluesky accounts (e.g., personal + moderation alt) frequently switch between the last two accounts. The current flow is: tap account icon → sheet appears → tap target account → sheet dismisses. This is 3 taps and a sheet animation.

The new feature reduces this to a single double-tap on the same icon when switching between the last two accounts. The account switcher sheet is still available via single tap for full account selection.

## Goals / Non-Goals

**Goals:**
- Double-tap account icon in tab bar → instant switch to previous account
- Single tap still opens the account switcher sheet
- Haptic feedback (impact rigid) confirms the switch
- Subtle visual badge on the avatar when quick-switch is available

**Non-Goals:**
- No changes to the account switcher sheet itself
- No changes to account authentication or session management
- No keyboard shortcuts (Cmd+Tab is separate)
- No support for switching beyond the last two accounts (previous only)
- No configurable gesture (always double-tap)

## Decisions

### Decision 1: Store previous account ID in AccountStore

**Choice**: Add `previousActiveAccountID: UUID?` property to `AccountStore`, updated in `switchAccount()`.

**Rationale**:
- `AccountStore` already owns `activeAccountID` and all account-switching logic
- The switch happens inside `switchAccount(to:using:)` which is `@MainActor` — no threading concerns
- Persisting to UserDefaults is unnecessary — `previousActiveAccountID` is ephemeral state that resets on app relaunch, which is correct behavior (no expectation of remembering across sessions)

**Implementation**:
```swift
// In AccountStore
@Published private(set) var previousActiveAccountID: UUID?

// In switchAccount(to:using:):
let previousID = activeAccountID
activeAccountID = account.id
previousActiveAccountID = previousID
```

### Decision 2: Combined single-tap and double-tap on same button

**Choice**: Use `.simultaneousGesture` with a `TapGesture(count: 2)` for double-tap, while the existing `.onTapGesture` for single-tap is replaced by the button's primary action.

**Rationale**:
- SwiftUI's `.onTapGesture(count: 2)` would block single-tap
- Using `Button` action for single-tap (already exists) + a separate `highPriorityGesture` for double-tap doesn't compose well
- Best approach: use the existing `Button` for the single-tap action, and add a `simultaneousGesture(TapGesture(count: 2).onEnded { ... })` to the button's label content

**Implementation**:
```swift
// Inside the account switcher Button
.simultaneousGesture(TapGesture(count: 2).onEnded {
    guard let prevID = accountStore.previousActiveAccountID,
          let prevAccount = accountStore.accounts.first(where: { $0.id == prevID })
    else { return }
    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    switchAccount(prevAccount)
})
```

### Decision 3: Visual indicator

**Choice**: A small `chevron.left.2` SF Symbol badge on the account avatar when `previousActiveAccountID` is non-nil.

**Rationale**:
- Chevron implies "switch back" direction
- Overlay badge is non-intrusive but visible
- Matches iOS conventions for quick-switch indicators

**Implementation**: `.overlay(alignment: .bottomTrailing) { ... }` with small font symbol.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Double-tap conflicts with single-tap on same button | SwiftUI `Button` with `simultaneousGesture` works: double-tap fires both a single-tap (opens sheet) and a double-tap (switches account). The single-tap opens the sheet which immediately closes as the switch happens. This is acceptable — the double-tap is fast enough that the sheet flash is barely visible. Mitigation: add a 0.15s delay on the sheet open to detect double-tap? Not needed for v1. |
| User expects the switcher sheet on double-tap | The sheet already opens briefly on double-tap (from single-tap part), but the switch closes it quickly. This is intuitive. |
| Haptic not felt | Fallback: no haptic. The visual switch is sufficient feedback. |

## Migration Plan

1. Add `previousActiveAccountID` to `AccountStore`
2. Update `switchAccount()` to track the previous
3. Add double-tap gesture to the account switcher button in `RootView`
4. Add visual indicator overlay
5. Build and verify

## Open Questions

- Should the previous account ID reset when an account is removed? (Yes — if the previous account is deleted, set to nil.)
- Should switching to the same account that's already active be a no-op? (Already handled — `switchAccount` likely checks `activeAccountID`.)
