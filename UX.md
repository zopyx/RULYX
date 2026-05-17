# UX Review & Visual Improvement Proposal

## Executive Summary

The app has a strong foundation with a defined design token system (AppTextStyle, named colors, card styles) but suffers from **inconsistent adoption** — 95% of views bypass the typography system via direct `.font()` calls, colors are hard-coded per-view, and accessibility patterns are uneven. The result is a fragmented user experience where each screen feels like it was built independently.

**Total views analyzed:** 45+ views across 6 feature areas
**Primary issues:** Inconsistency (60%), Accessibility gaps (25%), Localization (15%)

---

## 1. Color System

### Current State
- 6 brand colors defined (`skyPrimary`, `skyAccent`, `skyOrange`, `skyPurple`, surface variants)
- 4 semantic colors (`successGreen`, `warningOrange`, `errorRed`, `infoBlue`)
- All colors used directly in views — no semantic mapping layer
- `skyPurple` defined but never used
- Global tint `.skyPrimary` set on `TabView`

### Issues

| Issue | Severity | Details |
|-------|----------|---------|
| No semantic color tokens | High | Colors like `.skyPrimary` are used for everything (brand accent, active state, info badges, link text, icons). Changing the brand color would require hunting down 200+ direct references. |
| Hard-coded opacities | High | `.skyPrimary.opacity(0.12)`, `.skyPrimary.opacity(0.16)`, `.skyPrimary.opacity(0.07)` etc. scattered across views with no standardized opacity scale. |
| `skyPurple` dead code | Low | Defined but zero usage. Either remove or adopt for a purpose (e.g., "reported" status). |
| Gradient inconsistencies | Medium | Card gradients defined inline with different opacities and color combinations rather than reusing `LinearGradient.skySubtleGradient`. |

### Proposal

1. **Introduce semantic color tokens** mapped to brand colors:

```swift
enum AppSemanticColor {
    case accent           // primary interactive elements → skyPrimary
    case accentSecondary  // secondary accents → skyAccent
    case moderation       // mod list indicators → skyOrange
    case success          // positive states → successGreen
    case warning          // caution states → warningOrange
    case error            // destructive states → errorRed
    case surface          // card/panel backgrounds → surfacePrimary
    case surfaceSubtle    // secondary surfaces → surfaceSecondary
    case textPrimary      // primary text → primary (system)
    case textSecondary    // secondary text → secondary (system)
    case textTertiary     // tertiary text → tertiary (system)
}
```

2. **Standardize opacity scale** (matching Material Design levels):

```swift
enum AppOpacity {
    case emphasized  // 0.90 — primary text, icons
    case high        // 0.74 — body text
    case medium      // 0.60 — secondary text
    case disabled    // 0.38 — disabled elements
    case subtle      // 0.12 — background tints
    case faint       // 0.06 — divider lines
}
```

3. **Replace all inline `.opacity()` calls** with these tokens.

---

## 2. Typography

### Current State
- `AppTextStyle` enum with 10 styles defined in `AppStyling.swift`
- **Only 17 uses of `appFont()`** across the codebase
- **322 direct `.font()` calls** bypassing the system
- 4 of 10 styles never used via `appFont()`: `.largeTitle`, `.title`, `.body`, `.buttonLabel`
- `sectionHeaderStyle()` helper exists but is never used

### Issues

| Issue | Severity | Details |
|-------|----------|---------|
| Dual font system | Critical | Two competing approaches mean inconsistent sizing. E.g., list names use `.subheadline.weight(.semibold)` (direct) but the style is called `.heading` in AppTextStyle. Changing font sizes globally is impossible. |
| Missing type scale rationale | High | No documented hierarchy. It's unclear when to use `.heading` vs `.subheading` vs `.caption`. |
| `.largeTitle` and `.title` unused | Medium | Missing opportunity for hero text in profile headers and empty states. |
| `.body` style unused via appFont | Medium | All body text uses direct `.font(.body)` — can't be tuned globally. |
| `sectionHeaderStyle()` unused | Medium | List section headers use direct font + `.textCase(.none)` individually. |

### Proposed Typography Scale

```
.largeTitle  (28pt)  → Hero titles (splash, profile header)
.title       (22pt)  → Screen titles (list detail name, section headers)
.heading     (17pt)  → Card/row primary labels
.subheading  (15pt)  → Secondary labels, list names
.body        (17pt)  → Continuous text, descriptions
.caption     (12pt)  → Timestamps, counts, metadata
.captionSmall(11pt)  → Badge text, tertiary info
.statistic   (20pt)  → Numeric values (follower counts, stats)
.label       (15pt)  → State panel messages, empty states
.buttonLabel (17pt)  → Button text
```

### Migration Plan
1. Audit all 322 direct `.font()` calls
2. Map each to the closest AppTextStyle
3. Replace with `.appFont(.xxx)`
4. Remove unused AppTextStyle cases that have no mapping

---

## 3. Accessibility

### Current State
| Area | Coverage | Gaps |
|------|----------|------|
| Accessibility Labels | ~100 uses, widespread | Inconsistent — some buttons lack labels entirely |
| Accessibility Hints | ~90 uses | Verbose hints on simple actions; missing on complex interactions |
| Dynamic Type | 5 `@ScaledMetric` usages | Only 1 of 5 ties scaling to a text style via `relativeTo` |
| Reduce Motion | Handled in splash, profile, animation helpers | `appScrollTransition()` NOT gated |
| VoiceOver | Basic label/hint/trait coverage | No custom rotors, no custom actions on swipe rows |
| Focus management | `@FocusState` in search fields | No programmatic focus navigation |
| Accessibility inputs | ~8 uses of `accessibilityInputLabels` | Only on alert buttons |

### Critical Fixes Needed

1. **`@ScaledMetric` relativeTo** — All avatar/image sizes must specify `relativeTo`:
   - `ListRowView.iconSize` → `relativeTo: .body`
   - `AccountSummaryCard.avatarSize` → `relativeTo: .title1`
   - `AccountRowView.avatarSize` → `relativeTo: .body`
   - `AccountChip.avatarSize` → `relativeTo: .caption`

2. **Reduce Motion gate on `appScrollTransition()`** — Must check `UIAccessibility.isReduceMotionEnabled` before applying scroll transitions in `ListRowView` and `RelationshipsView`.

3. **AsyncImage accessibility** — Every `AsyncImage` needs:
   ```swift
   .accessibilityLabel(loc("avatar.label", name))
   .accessibilityAddTraits(.isImage)
   ```

4. **Custom VoiceOver rotor** — Add rotor for "Members" in list detail view to let users navigate between members without swiping each row.

5. **Swipe action VoiceOver** — `.swipeActions` in `ListDetailMembersSection` should expose custom actions:
   ```swift
   .accessibilityAction(named: loc("actions.remove")) { ... }
   ```

6. **Keyboard navigation** — Add focus management for all search fields and action sheets.

---

## 4. View Uniformity

### Current Inconsistencies

| Pattern | Inconsistent Usage | Example |
|---------|-------------------|---------|
| **Card styles** | 3 different gradient fills for cards | ListsView uses inline gradient, AccountSummaryCard uses its own, InfoView uses another — none reuse `.gradientCardStyle()` |
| **Corner radii** | 14 vs 18 vs 12 for similar cards | RelationshipsView uses 14, AccountSummaryCard uses 18, StatePanels use 12 |
| **List styles** | 17 views use `.insetGrouped`, 5 use `.plain` | No rationale for choice — e.g., ThreadView uses `.plain` while FollowerDiffView uses `.insetGrouped` |
| **Horizontal padding** | 16, 14, 12, 8, 6, 10 | 6 different values across different views |
| **Row vertical padding** | 10, 8, 4, 2 | BlueskyActorRow: v:10, ListRowView: v:4, ActivityLog: v:2 |
| **Chevron usage** | `.caption` vs `.subheadline` vs `.title3` | ListsView cards use `.caption`, AccountSummaryCard uses `.subheadline` |

### Proposed Uniform Spec

| Element | Value |
|---------|-------|
| Card corner radius | **16pt** (standard), **12pt** (compact/subtle) |
| Avatar corner radius | **`.continuous`** style everywhere |
| Row vertical padding | **10pt** (standard rows), **4pt** (compact/list rows) |
| Horizontal padding | **16pt** (screen edges), **12pt** (card internal) |
| Chevron | **`.subheadline.weight(.semibold)`** consistently |
| Section header | **`.sectionHeaderStyle()`** everywhere |
| List style | **`.insetGrouped`** (data/settings), **`.plain`** (feeds/timelines) |

---

## 5. Screen-by-Screen Review

### 5.1 SplashScreen
| Element | Current | Proposed |
|---------|---------|----------|
| Spacing | 24pt above tagline, 8pt below | 16pt both sides (done) |
| Logo size | Fixed 240pt height | Use `@ScaledMetric` for accessibility |
| Animation | No reduce-motion fast-skip | Already handled — good |

### 5.2 ListsView (Main Page)
| Element | Current | Proposed |
|---------|---------|----------|
| Account card | 60pt avatar, custom gradient | Reuse `.gradientCardStyle()` |
| Relationship grid | Inline gradient, 14pt radius | Extract to reusable card component |
| Follower/Following counts | `.appFont(.statistic)` | Good — keep |
| Section headers | Direct `.font()` | Replace with `.sectionHeaderStyle()` |

### 5.3 ListDetailView
| Element | Current | Proposed |
|---------|---------|----------|
| List name | `.title2.weight(.bold)` | Use `.appFont(.title)` |
| Members section | Members use `.subheadline` handle | Increase to `.body` for readability |
| Empty state | Standard `EmptyStatePanel` | Good — consistent |

### 5.4 BlueskyProfileView (933 lines)
| Element | Current | Proposed |
|---------|---------|----------|
| Display name | `.title3.weight(.semibold)` | Use `.appFont(.heading)` |
| Stats | Direct `.font(.subheadline)` | Use `.appFont(.subheading)` |
| Description | `.body` | Use `.appFont(.body)` |
| Badges | `.caption.weight(.semibold)` | Use `.appFont(.caption)` |
| Layout | Mixed padding (10, 6, 4) | Standardize to 8/12/16 |

### 5.5 RelationshipsView
| Element | Current | Proposed |
|---------|---------|----------|
| Row layout | Avatar | handle | compact labels | Increase avatar to 44pt, add display name |
| Block date | `.formatted(.relative(presentation: .named))` | Good — keep |
| Spacing | h:5, v:1 | Increase to h:12, v:2 |

### 5.6 InfoView
| Element | Current | Proposed |
|---------|---------|----------|
| Tab picker | Custom segmented control with `.ultraThinMaterial` | Consider `.pickerStyle(.segmented)` for native feel |
| Feature cards | GradientCardStyle | Good — consistent |
| Legal links | `.subheadline.weight(.semibold)` | Use `.appFont(.subheading)` |

---

## 6. Localization

### Issues
| File | Keys | Gap vs en.json |
|------|------|----------------|
| `en.json` | 937 | Reference |
| `de.json` | 886 | **-51 keys** |
| Other 13 langs | 882 each | **-55 keys each** |

### Critical Action
1. Audit which 55 keys are missing from non-English files
2. Prioritize: accessibility hints/labels, timeline features, chat features
3. For non-English: require native translation — no English fallbacks

### Missing Key Categories (Likely)
- Timeline/beta feature keys
- Accessibility `*.hint` and `*.label` keys
- Chat feature keys
- Block-back feature keys

---

## 7. Priority Roadmap

### P0 — Critical (Accessibility & Consistency)
1. Add `relativeTo` to all `@ScaledMetric` usages
2. Gate `appScrollTransition()` behind reduce-motion check
3. Add `accessibilityLabel` to all `AsyncImage` instances
4. Standardize section headers with `sectionHeaderStyle()`
5. Audit all 322 `.font()` calls and map to `AppTextStyle`

### P1 — High (Visual Cohesion)
1. Standardize card corner radii (14→16, or create a spec)
2. Unify row padding across all list views
3. Consolidate inline gradients into named gradient constants
4. Standardize chevron font/size across views
5. Add semantic color tokens and opacity scale

### P2 — Medium (Feature Parity)
1. Bridge 55-key localization gap in all non-English files
2. Add VoiceOver custom actions on swipeable list rows
3. Add keyboard navigation for search fields
4. Standardize list style choice across views
5. Adopt consistent horizontal padding (16pt standard)

### P3 — Low (Polish)
1. Use `.largeTitle` for hero text in profile headers
2. Use `.title` for screen titles consistently
3. Add custom VoiceOver rotor for member lists
4. Remove dead code (`skyPurple`, unused AppTextStyle cases)
5. Document design token system in project README
