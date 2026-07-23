# design-system-consistency Specification

## Purpose
TBD - created by archiving change ux-contrast-accessibility. Update Purpose after archive.
## Requirements
### Requirement: Sheet and overlay dismissal SHALL use ToolbarCloseButton
All dismiss/close affordances for sheets, fullscreen covers, and overlay viewers SHALL use `ToolbarCloseButton` (`xmark.circle.fill`, `.topBarTrailing` placement) instead of ad-hoc `Image(systemName: "xmark")` / `xmark.circle.fill` buttons. Non-dismiss "remove item" actions MAY keep custom icons.

#### Scenario: Overlay viewer dismissal
- **GIVEN** a fullscreen media viewer, carousel, or progress overlay
- **WHEN** the user looks for the close affordance
- **THEN** it SHALL be a `ToolbarCloseButton`-style `xmark.circle.fill` in the trailing position with a localized accessibility label

#### Scenario: Search field clearing
- **GIVEN** a search text field with a clear affordance
- **WHEN** text is present
- **THEN** clearing MAY use a plain `xmark`/`xmark.circle.fill` inline button, but it SHALL carry a localized `.accessibilityLabel`

### Requirement: Dismiss buttons SHALL NOT use confirmation iconography
Dismiss/close controls SHALL NOT use `checkmark.circle.fill`; checkmark iconography is reserved for status/success indicators and selection marks.

#### Scenario: No checkmark dismissals
- **GIVEN** any sheet or dialog
- **WHEN** it offers a dismiss affordance
- **THEN** the icon SHALL be `xmark.circle.fill` (never `checkmark.circle.fill`)

