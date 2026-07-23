# semantic-color-system Specification

## Purpose
TBD - created by archiving change ux-contrast-accessibility. Update Purpose after archive.
## Requirements
### Requirement: Status colors SHALL use the semantic palette
User-facing status, error, warning, and success indicators SHALL use the semantic palette colors (`errorRed`, `warningOrange`, `successGreen`, `infoBlue`) instead of raw system colors (`.red`, `.orange`, `.green`, `.blue`) so hues stay consistent and scheme-adaptive.

#### Scenario: Error and destructive indicators
- **GIVEN** any error icon, failure badge, or destructive-status text
- **WHEN** it is rendered in either color scheme
- **THEN** it SHALL use `Color.errorRed` instead of `.red` / `Color.red`

#### Scenario: Warning and success indicators
- **GIVEN** any warning or success indicator
- **WHEN** it is rendered in either color scheme
- **THEN** it SHALL use `Color.warningOrange` / `Color.successGreen` instead of `.orange` / `.green`

### Requirement: The app SHALL define a brand AccentColor asset
The asset catalog SHALL contain an `AccentColor` colorset with light and dark appearances matching the brand palette (`skyPrimary` variants), so all default tinting (`.tint(.accentColor)`, links, controls) uses the brand color.

#### Scenario: Default control tint
- **GIVEN** any control relying on the default accent color
- **WHEN** rendered in light or dark mode
- **THEN** its tint SHALL resolve to the brand `skyPrimary` variant for that scheme

### Requirement: New hardcoded RGB colors SHALL be justified
New `Color(red:green:blue:)` literals outside decorative contexts (splash screen, marketing/claim tiles) SHALL NOT be introduced; colors SHALL be added to `Color+RULYX.swift` with light/dark variants instead.

#### Scenario: Adding a new UI color
- **GIVEN** a developer adds a new non-decorative color
- **WHEN** the change is reviewed
- **THEN** the color SHALL be defined in `Color+RULYX.swift` with both scheme variants, not as an inline literal

