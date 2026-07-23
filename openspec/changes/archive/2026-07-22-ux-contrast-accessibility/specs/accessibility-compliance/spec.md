# accessibility-compliance Specification

## Purpose
Ensures VoiceOver completeness for icon-only controls and Dynamic Type scaling for fixed-size badge/count text. Closes findings 4 and 8 of the 360° UX review (`UX.md`).

## ADDED Requirements

### Requirement: Icon-only buttons SHALL have localized accessibility labels
Every button whose visible content is exclusively an `Image(systemName:)` or `Label` with `.iconOnly` style SHALL have an `.accessibilityLabel` using a `loc()` key (or use `.appButtonAccessibility(label:hint:)`). Labels MUST exist in all 16 localization files.

#### Scenario: Media browser close buttons
- **GIVEN** VoiceOver is enabled
- **WHEN** focus lands on the close buttons in `MediaBrowserView` (fullscreen viewer and download-progress overlay) or `ImageCarouselView`
- **THEN** VoiceOver SHALL announce a meaningful localized label (e.g. "Close") instead of "Button"

#### Scenario: Toolbar icon buttons
- **GIVEN** VoiceOver is enabled
- **WHEN** focus lands on any icon-only toolbar button
- **THEN** VoiceOver SHALL announce the localized action label

### Requirement: State-dependent controls SHALL expose accessibility values
Controls that represent an on/off or selection state (toggles rendered as custom buttons, selection checkmarks) SHALL expose their state via `.accessibilityValue` or the appropriate trait (`.isSelected`) so VoiceOver users can perceive state.

#### Scenario: Selection checkmark rows
- **GIVEN** VoiceOver is enabled
- **WHEN** focus lands on a selectable row showing `checkmark.circle.fill` vs `circle`
- **THEN** VoiceOver SHALL announce the selection state

### Requirement: Badge and count text SHALL scale with Dynamic Type
Badge and count text currently using fixed `.font(.system(size: 7…9))` SHALL scale relative to a Dynamic Type text style (e.g. `.caption2`-based) or use `@ScaledMetric`, so the text remains legible when the user increases text size.

#### Scenario: Unread badge at largest text size
- **GIVEN** the device is set to the largest Dynamic Type size
- **WHEN** viewing tab badges or count badges (`RootView`, `AIModelManagementView`, `ChatMessageBubble`, `ModelDownloadIndicator`)
- **THEN** badge text SHALL be scaled up proportionally and remain unclipped inside its badge container
