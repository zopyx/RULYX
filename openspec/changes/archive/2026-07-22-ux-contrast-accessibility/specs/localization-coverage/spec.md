# localization-coverage Specification

## Purpose
Guarantees that every user-facing string is routed through the custom `LocalizationManager` (`loc()`) with entries in all 16 language files. Closes finding 5 of the 360° UX review (`UX.md`).

## ADDED Requirements

### Requirement: User-facing strings SHALL NOT be hardcoded
All user-facing text (labels, counts with units, button titles, placeholders, alerts) SHALL use `loc()` / `String.localized()` / `Text(loc:)` with the key present in all 16 JSON localization files. Hardcoded string literals are only acceptable in internal debug tooling (`HTTPRequestDebugView`, `HTTPDebugStatsView`, `PerformanceMonitorOverlay`).

#### Scenario: iPad list member counts
- **GIVEN** the app language is set to any of the 16 supported languages
- **WHEN** viewing list rows in `iPadListsView`
- **THEN** the member count subtitle SHALL be rendered via `loc("lists.members.count")` (with `{n}` replacement) instead of the hardcoded literal `"\(count) members"`

#### Scenario: New key completeness
- **GIVEN** a new localization key is introduced
- **WHEN** the change is built and tested
- **THEN** the key SHALL exist in all 16 files under `Sources/Shared/Localizations/` and `LocalizationCompletenessTests` SHALL pass

### Requirement: Parameterized strings SHALL use the `{n}` replacement pattern
Strings containing dynamic values SHALL use `replacingOccurrences(of: "{n}")` (or the `String.localized(_:replacements:)` helper) — never `String(format:)` or manual concatenation of translated fragments.

#### Scenario: Count rendering
- **GIVEN** a string containing a dynamic count
- **WHEN** it is rendered in any language
- **THEN** the count SHALL be substituted via the `{n}` placeholder so word order stays correct per language
