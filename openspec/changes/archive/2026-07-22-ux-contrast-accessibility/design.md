# Design: ux-contrast-accessibility

## Context

The 360° UX review (`UX.md`, overall 7.4/10) identified contrast breaks and accessibility gaps with file:line evidence. The most severe: `ChatMessageBubble` renders white text on `Color.skyPrimary`, whose dark-mode variant (RGB 0.40/0.78/1.00) is *lighter* than its light variant — dropping contrast from ~3.6:1 (light) to ~1.9:1 (dark), both below WCAG-AA 4.5:1. Additionally, the earlier dark-mode cleanup (spec `dark-mode-readability`) deliberately excluded `Sources/App/iPad/`, leaving 11+ user-facing `.tertiary` texts there. All fixes are mechanical color/label replacements — no architectural changes, no API surface changes.

Constraints:
- Swift 6 strict concurrency; changes are view-layer only.
- All new strings must go into all 16 localization JSONs (batch-add pattern from AGENTS.md).
- `patch` tool can mangle Swift string interpolations — verify with `git diff` after every Swift edit.

## Goals / Non-Goals

**Goals**
- Chat outgoing bubble ≥4.5:1 text contrast in both schemes.
- Zero user-facing `.tertiary` foreground in `Sources/App/iPad/`.
- Zero `Color(.label).opacity(...)` for user-facing text.
- VoiceOver labels on all icon-only buttons (3 known sites + audit rule).
- `iPadListsView` member count fully localized.
- Brand `AccentColor` asset; status colors consolidated onto semantic palette.
- Badge fonts scale with Dynamic Type.
- Dismiss affordances unified on `ToolbarCloseButton`.

**Non-Goals**
- Redesign of the color palette or chat UI.
- Migrating decorative `Color(red:…)` literals in `InfoView`/`SplashScreenView` (explicitly allowed as decorative).
- Full app-wide WCAG AAA compliance.
- Fixing the 9 hardcoded debug-tool strings (internal only, spec allows them).

## Decisions

### D1: Chat bubble — darken the dark-mode bubble, keep brand hue
Add `static let chatBubbleOutgoing` to `Color+RULYX.swift`: light = current `skyPrimary` light value kept only if it reaches 4.5:1 with white — it does not (~3.6:1), so light variant darkens slightly to RGB ≈(0.05, 0.45, 0.90) and dark variant to RGB ≈(0.10, 0.42, 0.85). White text on both ≥4.6:1.
*Alternative considered*: keep `skyPrimary` and switch text to `.black` in dark mode — rejected, breaks the visual identity (white-on-blue chat metaphor) and inverts between schemes.
*Alternative considered*: use system `.accentColor` — rejected until D4 lands; also same contrast problem.

### D2: Outgoing timestamps — `.white.opacity(0.9)` minimum
Bump `ChatMessageBubble.swift:59` (0.6→0.9) and `:91` (0.8→0.9). *Correction during implementation:* 0.85 white computed to 4.50:1 (boundary) — 0.9 yields 4.59–4.66:1 on both bubble variants, verified by `scripts/check_contrast.py`.
*Alternative*: `.white` full — rejected, timestamps should stay visually subordinate.

### D3: iPad tertiary sweep — same rules as the iPhone cleanup
Replace `.tertiary` → `.secondary` at the 11 user-facing sites (`iPadDashboardView:77,149`, `iPadListsView:74,122,142`, `iPadListDetailView:290,312`, `iPadProfileInspector:237`, `iPadRootView:215`). Keep `.tertiary` for decorative avatar placeholders (`iPadDragDrop:61`, `iPadListDetailView:290` icon, `iPadProfileInspector:120` icon), separators, and overflow badges — consistent with spec `dark-mode-readability` ("decorative SHALL remain tertiary").

### D4: AccentColor asset with brand variants
Create `Assets/Assets.xcassets/AccentColor.colorset/Contents.json` with light = `skyPrimary` light, dark = `skyPrimary` dark. Existing `.tint(.accentColor)` call sites (45) adopt it automatically.
*Alternative*: set `AccentColor` in code via `.tint(.skyPrimary)` at root — rejected, asset catalog is the idiomatic mechanism and also covers UIKit bridges.

### D5: System-color consolidation — targeted, not sweeping
Replace only user-facing *status* usages of `.red`/`.orange`/`.green` (icons, badges, error text) with `errorRed`/`warningOrange`/`successGreen`. Decorative gradient stops (InfoView, Splash) are out of scope. Estimated ~30 of the 63 hits; the remainder are verified decorative and documented in tasks.

### D6: Badge Dynamic Type — relative font, not @ScaledMetric everywhere
Replace `.font(.system(size: 7…9, weight:))` on badges with `.font(.caption2.weight(...))` plus `.minimumScaleFactor(0.7)` inside the fixed badge circle. The badge *container* stays fixed-size (visual dot); only glyphs scale.
*Alternative*: `@ScaledMetric` the container too — rejected, a 30pt+ badge circle at AX5 breaks tab bar layout.

### D7: Dismiss unification — labels first, ToolbarCloseButton where applicable
*Updated during implementation:* audit showed none of the direct `xmark` sites were actual toolbar dismissals — they are inline search-clear buttons, remove-item actions, or styled overlay dismissals on dark media (where `ToolbarCloseButton`'s `.secondary` foreground would be illegible). All received localized `.accessibilityLabel`s instead (`actions.clear_search`, `actions.remove`, `actions.close`, `actions.dismiss`). Original intent follows.
Replace direct `xmark`/`xmark.circle.fill` dismiss buttons in `CustomSearchView:200`, `MediaBrowserView:447,541`, `ImageCarouselView:75`, `MediaDownloadProgressView:42`, `UserPostsView:424`, `ManagePostsView:304`, `ReplyComposerView:74`, `iPadCommandPalette:57` with `ToolbarCloseButton(action:)` (supports custom close logic already). Inline "clear search text" buttons keep their icon but gain `.accessibilityLabel(loc("actions.clear_search"))`.

### D8: New localization keys — batch-add via Python pattern
Keys: `actions.close` (likely exists — verify first), `actions.clear_search`, `lists.members.count` ("{n} members"), `a11y.selected` / `a11y.not_selected`. Add to all 16 JSONs with native translations (project convention: English stubs acceptable per commit `5032d1c`, but native translations preferred where confident; completeness enforced by `LocalizationCompletenessTests`).

### D9: Contrast verification — scripted luminance check
Add a small Python script (`scripts/check_contrast.py`, not shipped) that computes WCAG relative luminance for the new color pairs and asserts ≥4.5:1. Run in CI-manual verification, plus `xcodegen generate && xcodebuild … build`.

## Risks / Trade-offs

- [Darker light-mode bubble changes brand look slightly] → Keep hue identical, only lower lightness; verify screenshots (`make screenshots`) before/after.
- [Semantic color swap changes hues subtly in ~30 places] → Single commit per file group for easy `git revert`; visual spot-check of Chat, Relationships, Batch views.
- [`patch` escaping mangles Swift interpolations (known tool issue)] → `git diff` after every edit; fall back to `execute_code` string replacement for interpolation-heavy lines.
- [AccentColor asset could change UIKit control tints unexpectedly] → Build + smoke-test forms/pickers; the asset matches `skyPrimary`, which is the intended brand tint anyway.
- [Localization stubs in non-English files] → Acceptable per established pattern; completeness test enforces key presence.

## Migration Plan

1. Land in five reviewable commits: (a) chat bubble + theme color, (b) iPad tertiary sweep, (c) a11y labels + badge fonts, (d) localization + AccentColor, (e) semantic color consolidation + ToolbarCloseButton sweep.
2. No data migration, no API changes, rollback = `git revert` per commit.
3. Verify: `xcodegen generate`, simulator build, grep audits (0 user-facing `.tertiary` in iPad, 0 `Color(.label).opacity` outside decorative, 0 icon-only buttons without labels), `swiftlint`, contrast script.

## Open Questions

- Should `AccentColor` dark variant equal `skyPrimary` dark (lighter blue) or the darker chat-bubble blue? Default: `skyPrimary` dark — accent is a foreground tint, lighter reads better on dark surfaces. Confirm during implementation review.
- Native translations for the 3–4 new keys in all 15 non-English languages, or English stubs? Default: provide native translations for de/fr/it/es/ja/zh (high confidence), stubs elsewhere.
