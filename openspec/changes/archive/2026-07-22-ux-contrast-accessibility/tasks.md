# Tasks: ux-contrast-accessibility

## 1. Chat Bubble Contrast (wcag-contrast-compliance)

- [x] 1.1 Add `static let chatBubbleOutgoing` to `Sources/Shared/Theme/Color+RULYX.swift` with trait-adaptive variants (light ≈ RGB 0.05/0.45/0.90, dark ≈ RGB 0.10/0.42/0.85), doc comment stating WCAG ≥4.5:1 intent
- [x] 1.2 Switch `Sources/Features/Chat/ChatMessageBubble.swift:96` outgoing background from `Color.skyPrimary` to `Color.chatBubbleOutgoing`; keep incoming `Color(.systemGray5)`
- [x] 1.3 Bump outgoing timestamp `ChatMessageBubble.swift:59` from `.white.opacity(0.6)` to `.white.opacity(0.85)` and `:91` from `.white.opacity(0.8)` to `.white.opacity(0.85)`
- [x] 1.4 Check link/attributed text color in bubble (`ChatMessageBubble.swift:126`) against new background; adjust to `.white` with underline if <4.5:1
- [x] 1.5 Replace `Color(.label).opacity(0.7)` with `Color(.secondaryLabel)` in `Sources/Features/Chat/ConversationListView.swift:403,412`
- [x] 1.6 Write `scripts/check_contrast.py` (WCAG relative-luminance calculator) and assert white on both `chatBubbleOutgoing` variants ≥4.5:1 and 0.85-white ≥4.5:1

## 2. iPad Tertiary Sweep (dark-mode-readability delta)

- [x] 2.1 `Sources/App/iPad/iPadDashboardView.swift:77,149` — user-facing labels `.tertiary` → `.secondary`
- [x] 2.2 `Sources/App/iPad/iPadListsView.swift:74,122,142` — count/subtitle text `.tertiary` → `.secondary`
- [x] 2.3 `Sources/App/iPad/iPadListDetailView.swift:312` — member date `.tertiary` → `.secondary` (keep `:290` avatar placeholder icon decorative)
- [x] 2.4 `Sources/App/iPad/iPadProfileInspector.swift:237` — member count `.tertiary` → `.secondary` (keep `:120` placeholder icon decorative)
- [x] 2.5 `Sources/App/iPad/iPadRootView.swift:215` — onboarding subtitle `.tertiary` → `.secondary`
- [x] 2.6 Verify remaining `.tertiary` in `Sources/App/iPad/` is decorative only (avatar placeholders, `iPadDragDrop:61`) — grep audit, document exceptions

## 3. VoiceOver Labels & Dynamic Type (accessibility-compliance)

- [x] 3.1 Add `.accessibilityLabel(loc("actions.close"))` to icon-only close buttons in `Sources/Features/Lists/Profile/MediaBrowserView.swift:447,541` and `Sources/Shared/Components/ImageCarouselView.swift:75`
- [x] 3.2 Add `.accessibilityValue` / `.isSelected` trait to selection checkmark buttons (`MediaBrowserView:403`, `ActorSearchResultRow:23`, `ListDetailComparisonSection:246`, `ManagePostsView:413`)
- [x] 3.3 Replace fixed badge fonts with scaling styles: `RootView.swift:102` (7pt → `.caption2.weight(.bold)` + `.minimumScaleFactor(0.7)`), `AIModelManagementView.swift:207` (8pt), `ChatMessageBubble.swift:80` (9pt), `ModelDownloadIndicator.swift:31` (9pt)
- [x] 3.4 Re-audit: heuristic scan for icon-only buttons without labels → expect 0 remaining

## 4. Localization (localization-coverage)

- [x] 4.1 Verify whether `actions.close` / `actions.clear_search` keys already exist in `en.json`; create missing keys
- [x] 4.2 Add `lists.members.count` = "{n} members" (EN) + translations to all 16 JSONs via batch Python pattern (AGENTS.md)
- [x] 4.3 Replace hardcoded `"\(count) members"` in `Sources/App/iPad/iPadListsView.swift:122,142` with `loc("lists.members.count").replacingOccurrences(of: "{n}", with: "\(count)")`
- [ ] 4.4 Run `LocalizationCompletenessTests` — all keys present in 16 files

## 5. Semantic Colors & AccentColor (semantic-color-system)

- [x] 5.1 Create `Assets/Assets.xcassets/AccentColor.colorset/Contents.json` with light = `skyPrimary` light, dark = `skyPrimary` dark; run `xcodegen generate` and verify build picks it up
- [x] 5.2 Audit the 63 hardcoded system-color hits; classify status vs decorative (InfoView/Splash gradients stay)
- [x] 5.3 Replace status `.red` → `Color.errorRed` (icons, badges, error text, e.g. `ChatMessageBubble.swift:68`)
- [x] 5.4 Replace status `.orange` → `Color.warningOrange`, `.green` → `Color.successGreen` at user-facing indicator sites
- [x] 5.5 Visual smoke-test: Chat, RelationshipsView, BatchOperationProgressView, AIBatchScreenView in both schemes

## 6. Dismiss-Button Consistency (design-system-consistency)

- [x] 6.1 Migrate direct dismiss `xmark` buttons to `ToolbarCloseButton(action:)` (implemented as: labels added instead — all candidates turned out to be inline-clear/remove/overlay actions, not toolbar dismissals; see design D7 note): `CustomSearchView.swift:200`, `MediaBrowserView.swift:447,541`, `ImageCarouselView.swift:75`, `MediaDownloadProgressView.swift:42`, `UserPostsView.swift:424`, `ManagePostsView.swift:304`, `ReplyComposerView.swift:74`, `iPadCommandPalette.swift:57`
- [x] 6.2 Keep inline search-clear buttons as-is but add `.accessibilityLabel(loc("actions.clear_search"))`
- [x] 6.3 Verify no dismiss uses `checkmark.circle.fill` (grep audit — expect only status/selection uses)

## 7. Verification & Close-out

- [x] 7.1 `xcodegen generate && xcodebuild -project RULYX.xcodeproj -scheme RULYX -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO` — clean build
- [x] 7.2 `swiftformat --lint . && swiftlint` — no new violations
- [x] 7.3 Grep audits: 0 user-facing `.tertiary` in iPad, 0 `Color(.label).opacity` outside decorative, all icon-only buttons labeled
- [x] 7.4 `scripts/check_contrast.py` passes for all new color pairs
- [x] 7.5 Run unit tests (`make test` or xcodebuild test) — no regressions; update `UX.md` scores where fixed
- [ ] 7.6 `openspec validate ux-contrast-accessibility --json` clean, then archive after merge