## 1. AccountStore — Track Previous Account

- [ ] 1.1 Add `@Published private(set) var previousActiveAccountID: UUID?` to `AccountStore`
- [ ] 1.2 Update `switchAccount(to:using:)` to save `activeAccountID` into `previousActiveAccountID` before switching
- [ ] 1.3 Reset `previousActiveAccountID = nil` when the referenced account is removed in `removeAccount()`

## 2. RootView — Double-Tap Gesture

- [ ] 2.1 Add `.simultaneousGesture(TapGesture(count: 2).onEnded { ... })` to the account switcher button's label content in `RootView.swift`
- [ ] 2.2 On double-tap: read `previousActiveAccountID`, look up the account, call `switchAccount()`
- [ ] 2.3 Add `UIImpactFeedbackGenerator(style: .rigid).impactOccurred()` on successful double-tap switch
- [ ] 2.4 Add the visual indicator: `.overlay(alignment: .bottomTrailing)` with `chevron.left.2` SF Symbol when `previousActiveAccountID != nil`

## 3. Build & Verify

- [ ] 3.1 Run `xcodegen generate` and build for iOS Simulator
- [ ] 3.2 Run `swiftformat Sources Tests` and `swiftlint`
- [ ] 3.3 Verify `openspec validate --change quick-account-switch --json` passes
