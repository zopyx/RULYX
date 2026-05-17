# BlueskyModeration Design Guide

## Color System

### Brand Colors

| Token | Light | Dark | Usage |
|-------|-------|------|-------|
| `Color.skyPrimary` | 0.07, 0.53, 0.98 | 0.20, 0.65, 1.00 | Primary accent, interactive elements, active states |
| `Color.skyAccent` | 0.02, 0.78, 0.82 | 0.15, 0.88, 0.92 | Secondary accent, gradient component |
| `Color.skyOrange` | 0.96, 0.60, 0.18 | 0.95, 0.60, 0.20 | Moderation list indicators, warning states |

### Semantic Colors

| Token | Usage |
|-------|-------|
| `Color.successGreen` | Positive states (`StatusChip.positive`) |
| `Color.warningOrange` | Caution states (`StatusChip.warning`) |
| `Color.errorRed` | Destructive actions, block badges (`StatusChip.destructive`) |
| `Color.infoBlue` | Informational states — alias of `skyPrimary` |

### Surface Colors

| Token | Light | Dark | Used By |
|-------|-------|------|---------|
| `Color.surfacePrimary` | 1.0, 1.0, 1.0 | 0.12, 0.13, 0.15 | `.appCardStyle(style: .standard)` |
| `Color.surfaceSecondary` | 0.96, 0.97, 0.98 | 0.16, 0.17, 0.19 | `.appCardStyle(style: .subtle)` |

### Adaptive System Colors

```swift
Color.cardBackground  // .secondarySystemFill
Color.subtleBackground // .tertiarySystemFill  
Color.appDivider      // .separator
Color.iconBackground  // .quaternarySystemFill
```

### Gradients

| Gradient | Colors | Usage |
|----------|--------|-------|
| `LinearGradient.skyPrimaryGradient` | skyPrimary → skyAccent | Account card avatars, hero sections |
| `LinearGradient.skySubtleGradient` | skyPrimary(0.14) → skyAccent(0.06) | Default gradient card style |
| `LinearGradient.semanticGradient(for:)` | color(0.14) → color(0.04) | Generic semantic gradient |

### Global Tint

`.tint(.skyPrimary)` set on `TabView` in `RootView.swift`.

---

## Typography

### AppTextStyle Scale

| Style | Font | Weight | Usage |
|-------|------|--------|-------|
| `.largeTitle` | `.largeTitle` | Bold | Hero titles (splash, profile header) |
| `.title` | `.title2` | Bold | Screen titles (list detail name, section headers) |
| `.heading` | `.headline` | Semibold | Card/row primary labels |
| `.subheading` | `.subheadline` | Semibold | Secondary labels, list names |
| `.body` | `.body` | Regular | Continuous text, descriptions |
| `.caption` | `.caption` | Semibold | Timestamps, counts, metadata |
| `.captionSmall` | `.caption2` | Semibold | Badge text, tertiary info |
| `.statistic` | `.title3` | Semibold, monospacedDigit | Numeric values, follower counts |
| `.label` | `.subheadline` | Regular | State panel messages, empty states |
| `.buttonLabel` | `.headline` | Regular | Button text |

### Usage

```swift
// Preferred — uses AppTextStyle enum
Text("Hello").appFont(.heading)

// Avoid — direct font calls
Text("Hello").font(.headline.weight(.semibold))
```

### Section Headers

Always use the provided modifier:
```swift
Text("Section Name").sectionHeaderStyle()
// Applied: .font(.subheadline.weight(.semibold)).textCase(.none)
```

---

## Card & Row Design

### Card Styles

```swift
// Standard card (most common)
view.appCardStyle(cornerRadius: 16, style: .standard)

// Subtle card
view.appCardStyle(cornerRadius: 12, style: .subtle)

// Gradient card
view.gradientCardStyle(gradient: .skySubtleGradient, cornerRadius: 18)
```

### Standard Dimensions

| Element | Value |
|---------|-------|
| Card corner radius | 16pt (standard), 12pt (compact/subtle) |
| Avatar size (rows) | 40pt (`.body` scaled) |
| Avatar size (account card) | 60pt |
| Row vertical padding | 10pt (standard), 4pt (compact/list) |
| Horizontal padding | 16pt (screen edges), 12pt (card internal) |
| Chevron | `.subheadline.weight(.semibold)` |
| Section header | `.sectionHeaderStyle()` |

### Row Patterns

**Actor row** — use `BlueskyActorRow`:
```swift
BlueskyActorRow(actor: actor) {
    // Optional extra content inline after display name
}
```
Layout: `[Circle avatar 40pt] [Display Name .heading | Handle .subheadline]`

**List row** — use `ListRowView`:
```swift
ListRowView(list: list)
```
Layout: `[RoundedRect icon 32pt] [Name .subheading | Description .caption] [count]`

---

## Accessibility

### Dynamic Type

All size constants must use `@ScaledMetric` with `relativeTo`:
```swift
@ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 40
```

### Reduce Motion

Gate animations and scroll transitions:
```swift
if !UIAccessibility.isReduceMotionEnabled {
    // animated content
}
```

### AsyncImage

Every `AsyncImage` must have an accessibility label:
```swift
AsyncImage(url: url) { ... }
    .accessibilityLabel(loc("avatar.label", name))
    .accessibilityAddTraits(.isImage)
```

### VoiceOver

- All buttons: `.accessibilityLabel()` + `.accessibilityHint()`
- Swipe actions: expose as `.accessibilityAction(named:)`
- Custom rotors for lists of items

### Focus Management

```swift
@FocusState private var fieldFocused: Bool
TextField(...).focused($fieldFocused)
```

---

## List Styles

| Context | Style |
|---------|-------|
| Data, settings, profiles | `.insetGrouped` |
| Feeds, timelines, chat | `.plain` |

---

## Animation

Use the app animation helpers (gated on Reduce Motion):

```swift
// Spring animation
.animation(.appSpring(), value: someValue)

// Ease in/out
.animation(.appEaseInOut(duration: 0.3), value: someValue)

// Transitions
view.appTransition(.opacity.combined(with: .scale(scale: 0.96)))

// Scroll transitions (must gate on Reduce Motion)
if !UIAccessibility.isReduceMotionEnabled {
    view.appScrollTransition()
}
```

---

## Localization

All user-facing strings use `loc("key")` — never hardcoded English.

### Key Naming

`scren.component.description` dot notation:
- `profile.badge.following` — profile screen, badge section, "following" label
- `list.members.load_more` — list screen, members section, "load more" button
- `actions.cancel` — reusable action labels

### Coverage

16 language files: `en.json`, `de.json`, `fr.json`, `it.json`, `ja.json`, `zh.json`, `es.json`, `pt.json`, `ko.json`, `ru.json`, `ar.json`, `nl.json`, `pl.json`, `tr.json`, `th.json`, `vi.json`

**Must update all 16 files when adding keys.** Non-English translations require native language — no English fallbacks.

### Accessibility Keys

Accessibility strings follow the same pattern with `*.label` and `*.hint` suffixes:
```json
"list.members.load_more.label": "Load more members",
"list.members.load_more.hint": "Shows the next page of list members"
```
