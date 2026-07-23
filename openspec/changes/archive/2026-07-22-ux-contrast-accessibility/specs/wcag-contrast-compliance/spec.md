# wcag-contrast-compliance Specification

## Purpose
Guarantees WCAG 2.1 AA contrast ratios (≥4.5:1 for normal text, ≥3:1 for large text) for all text rendered on brand or semantic backgrounds, in both light and dark color schemes. Closes the chat-bubble contrast break found in the 360° UX review (`UX.md`, finding 1 and 3).

## ADDED Requirements

### Requirement: Outgoing chat bubble text SHALL meet WCAG-AA contrast in both color schemes
Text and icons rendered on the outgoing chat bubble background SHALL have a contrast ratio of at least 4.5:1 against the bubble background in both light and dark mode. The bubble background SHALL use a scheme-adaptive color whose dark variant is dark enough for white text (target luminance contrast ≥4.5:1).

#### Scenario: Outgoing message in Dark Mode
- **GIVEN** the app is in Dark Mode
- **WHEN** viewing an outgoing message in `ChatMessageBubble`
- **THEN** message text and metadata on the bubble SHALL have ≥4.5:1 contrast against the bubble background

#### Scenario: Outgoing message in Light Mode
- **GIVEN** the app is in Light Mode
- **WHEN** viewing an outgoing message in `ChatMessageBubble`
- **THEN** message text and metadata on the bubble SHALL have ≥4.5:1 contrast against the bubble background

#### Scenario: Outgoing timestamp contrast
- **GIVEN** the app is in either color scheme
- **WHEN** viewing the timestamp of an outgoing message
- **THEN** the timestamp SHALL use white at ≥0.8 opacity (or an equivalent ≥4.5:1 treatment) instead of `.white.opacity(0.6)`

### Requirement: Opacity-dimmed text on label colors SHALL be replaced by semantic colors
User-facing text colored via `Color(.label).opacity(n)` SHALL be replaced with the matching semantic color (`Color(.secondaryLabel)` for ~0.7 and below, `Color(.tertiaryLabel)` only for decorative use) so contrast adapts correctly per scheme.

#### Scenario: Conversation list preview text
- **GIVEN** the app is in either color scheme
- **WHEN** viewing the message preview rows in `ConversationListView`
- **THEN** preview and timestamp text SHALL use `Color(.secondaryLabel)` instead of `Color(.label).opacity(0.7)`

### Requirement: Brand background colors SHALL declare a matching foreground
Every brand/semantic background color used behind text (`skyPrimary`, `skyAccent`, `errorRed`, `warningOrange`, `successGreen`) SHALL have a documented foreground choice that reaches ≥4.5:1 for normal text or ≥3:1 for large text in both schemes.

#### Scenario: Accent-colored badges and chips
- **GIVEN** any view rendering text on `skyPrimary`, `skyAccent`, `errorRed`, `warningOrange`, or `successGreen`
- **WHEN** the color scheme changes
- **THEN** the foreground/background pair SHALL keep ≥4.5:1 (normal text) or ≥3:1 (large text) contrast
