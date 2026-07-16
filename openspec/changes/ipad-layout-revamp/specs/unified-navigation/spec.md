## ADDED Requirements

### Requirement: iPad uses the same tab bar as iPhone
`RootView` SHALL render the same `TabView`-based layout (custom `HStack` tab bar in `.safeAreaInset(edge: .bottom)`) regardless of `horizontalSizeClass`. The `iPadRootView` branch SHALL be removed.

The tab bar SHALL contain:
- Moderation, Timeline, Notifications, Chat, Info, Settings tabs
- Account switcher with double-tap quick-switch gesture
- All tab items visible without overflow on iPad

#### Scenario: iPad in portrait shows tab bar
- **GIVEN** an iPad in portrait orientation
- **WHEN** `RootView` appears
- **THEN** the custom bottom tab bar is shown with all 6 tabs + account switcher
- **THEN** no sidebar is visible

#### Scenario: iPad in landscape shows tab bar
- **GIVEN** an iPad in landscape orientation
- **WHEN** `RootView` appears
- **THEN** the bottom tab bar is shown
- **THEN** content fills the full width (no sidebar column)

#### Scenario: horizontalSizeClass branching removed
- **WHEN** `RootView.body` is evaluated
- **THEN** there is no `if horizontalSizeClass == .regular` branch
- **THEN** both iPhone and iPad render the same tab-based layout

### Requirement: iPad-only power features are preserved
iPad-specific enhancements (Cmd+K command palette, keyboard shortcuts, drag-and-drop) SHALL be integrated into the shared `RootView` via conditional modifiers, not removed.

#### Scenario: Cmd+K palette on iPad
- **GIVEN** an iPad with a hardware keyboard
- **WHEN** the user presses Cmd+K
- **THEN** the command palette opens (same as current `iPadCommandPalette`)
- **WHEN** an item is selected
- **THEN** the corresponding tab is selected

#### Scenario: Keyboard shortcuts work on iPad
- **GIVEN** an iPad with a hardware keyboard
- **WHEN** the user presses Cmd+L, Cmd+D, Cmd+F, Cmd+T
- **THEN** the corresponding tab or section navigates
- **WHEN** on iPhone with a hardware keyboard
- **THEN** the same shortcuts work (no platform restriction)
