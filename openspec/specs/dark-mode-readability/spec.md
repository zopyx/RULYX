# dark-mode-readability Specification

## Purpose
TBD - created by archiving change dark-mode-contrast. Update Purpose after archive.
## Requirements
### Requirement: All user-facing text SHALL use at least `.secondary` foreground in Dark Mode
All text elements that convey information to the user (labels, handles, timestamps, descriptions, counts, dates, metadata) SHALL use `.foregroundStyle(.secondary)` or higher contrast (`.primary`) for readability in Dark Mode. The `.tertiary` tint MAY only be used for purely decorative or non-text elements. This applies equally to iPhone views and iPad views under `Sources/App/iPad/`.

#### Scenario: Handle labels in search views
- **GIVEN** the app is in Dark Mode
- **WHEN** viewing search results in `CustomSearchView` or `MentionsSearchView`
- **THEN** user handles and descriptions SHALL be rendered in `.secondary` or higher

#### Scenario: Profile metadata
- **GIVEN** the app is in Dark Mode
- **WHEN** viewing a Bluesky profile (`BlueskyProfileView`)
- **THEN** section labels, stats, and metadata SHALL be readable (`.secondary` minimum)

#### Scenario: Chat timestamps
- **GIVEN** the app is in Dark Mode
- **WHEN** viewing chat messages (`ConversationDetailView`, `ChatMessageBubble`)
- **THEN** message timestamps, reaction labels, and system messages SHALL be readable

#### Scenario: Relationship counts
- **GIVEN** the app is in Dark Mode
- **WHEN** viewing `RelationshipsView`
- **THEN** follower/following counts and date labels SHALL use `.secondary` or higher

#### Scenario: iPad list member counts and dates
- **GIVEN** the app is in Dark Mode on iPad
- **WHEN** viewing `iPadListsView`, `iPadListDetailView`, or `iPadProfileInspector`
- **THEN** member counts, "members" subtitles, and membership dates SHALL use `.secondary` or higher (`.tertiary` is not permitted for these texts)

#### Scenario: iPad dashboard and onboarding labels
- **GIVEN** the app is in Dark Mode on iPad
- **WHEN** viewing `iPadDashboardView` chart labels or the onboarding subtitle in `iPadRootView`
- **THEN** these labels SHALL use `.secondary` or higher

### Requirement: Decorative elements SHALL remain at `.tertiary`
Non-text decorative elements such as `Divider()`, placeholder shapes in skeleton loaders, disabled-state icons, and purely visual indicators SHALL remain at `.foregroundStyle(.tertiary)`.

#### Scenario: Separators unaffected
- **GIVEN** the app is in Dark Mode
- **WHEN** viewing any screen with `Divider()` elements
- **THEN** separators MAY remain at their current contrast level

### Requirement: Opacity-based text colors SHALL be replaced with semantic colors
Patterns using `Color(.label).opacity(n)` SHALL be replaced with the equivalent semantic color (`.secondaryLabel` for ~0.6 opacity, `.tertiaryLabel` for ~0.4 opacity) to ensure proper Dark Mode contrast. White-on-accent text MAY use white opacity only when the resulting contrast against the actual bubble/background color stays ≥4.5:1 in both schemes; otherwise the background SHALL be darkened or the opacity raised.

#### Scenario: Chat bubble text opacity
- **GIVEN** the app is in Dark Mode
- **WHEN** viewing timestamps in `ChatMessageBubble`
- **THEN** outgoing timestamps SHALL use `.white.opacity(0.8)` or higher on a contrast-safe bubble background, and incoming timestamps SHALL use `Color(.secondaryLabel)`

#### Scenario: Conversation list preview opacity
- **GIVEN** the app is in either color scheme
- **WHEN** viewing previews in `ConversationListView`
- **THEN** preview text SHALL use `Color(.secondaryLabel)` instead of `Color(.label).opacity(0.7)`

