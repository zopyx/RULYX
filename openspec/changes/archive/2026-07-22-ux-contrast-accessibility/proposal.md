# Proposal: ux-contrast-accessibility

## Why

The 360° UX review (see `UX.md`, 2026-07-22, overall score 7.4/10) found concrete WCAG contrast violations and accessibility gaps: white chat text on `skyPrimary` fails WCAG-AA in both color schemes (~3.6:1 light, ~1.9:1 dark), 11+ user-facing `.tertiary` texts in iPad views are near-invisible in Dark Mode, 3 icon-only buttons have no VoiceOver labels, and one user-facing string bypasses localization. These are the highest-impact, lowest-risk items from the review.

## What Changes

1. **Chat bubble contrast fix**: outgoing bubble background gets a dark-mode-specific darker variant so white text reaches ≥4.5:1; outgoing timestamps bumped from `.white.opacity(0.6/0.8)` to contrast-safe values.
2. **iPad tertiary sweep**: 11 user-facing `.foregroundStyle(.tertiary)` sites in `Sources/App/iPad/` → `.secondary` (decorative uses stay).
3. **Opacity → semantic**: `Color(.label).opacity(0.7)` in `ConversationListView` → `Color(.secondaryLabel)`.
4. **VoiceOver labels**: add `.accessibilityLabel(loc(...))` to 3 icon-only buttons (`MediaBrowserView` ×2, `ImageCarouselView` ×1); audit rule: every icon-only button SHALL have a localized label.
5. **Localization gap**: replace hardcoded `"\(count) members"` in `iPadListsView` with `loc("lists.members.count")` in all 16 JSON files.
6. **Semantic color consolidation**: replace hardcoded system colors (`.red`, `.orange`, …) at text/icon sites with palette colors (`errorRed`, `warningOrange`, `successGreen`); add an `AccentColor` asset with brand `skyPrimary` light/dark variants.
7. **Dynamic Type for badges**: fixed 7–9pt badge fonts scale via `.caption2`-relative styles or `@ScaledMetric`.
8. **Dismiss-button consistency**: direct `xmark` dismiss buttons migrated to `ToolbarCloseButton`.

## Capabilities

### New Capabilities
- `wcag-contrast-compliance`: minimum contrast ratios for text on brand/semantic backgrounds in both color schemes; covers chat bubble, timestamp opacity, and ConversationListView semantic replacement.
- `accessibility-compliance`: VoiceOver labels for icon-only buttons, `accessibilityValue` for toggle states, Dynamic Type scaling for badge/count text.
- `semantic-color-system`: brand AccentColor asset and consolidation of hardcoded system colors onto the semantic palette.
- `localization-coverage`: guarantee that all user-facing strings go through `loc()` with entries in all 16 language files.
- `design-system-consistency`: standardized dismiss buttons (`ToolbarCloseButton`) and toolbar rule conformance.

### Modified Capabilities
- `dark-mode-readability`: extend the `.secondary`-minimum requirement to iPad views (`Sources/App/iPad/`); update chat timestamp scenario to the new opacity values.

## Impact

- **Code**: `Sources/Features/Chat/ChatMessageBubble.swift`, `Sources/Features/Chat/ConversationListView.swift`, `Sources/Shared/Theme/Color+RULYX.swift`, 6 files under `Sources/App/iPad/`, `Sources/Features/Lists/Profile/MediaBrowserView.swift`, `Sources/Shared/Components/ImageCarouselView.swift`, `Sources/App/RootView.swift`, `Sources/App/AIModelManagementView.swift`, `Sources/Shared/Components/ModelDownloadIndicator.swift`, assorted views with hardcoded system colors and direct `xmark` dismiss buttons.
- **Assets**: `Assets/Assets.xcassets/AccentColor.colorset` (new).
- **Localization**: 16 JSON files (`Sources/Shared/Localizations/*.json`) — new keys for close/member-count labels.
- **Risk**: low — mechanical color/label replacements, no structural or API changes. Verification via build + grep audits + WCAG luminance check script.
- **Reference**: `UX.md` (full review, evidence with `path:line`).
