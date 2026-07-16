## Why

The current iPad layout uses `NavigationSplitView` with a sidebar, which differs significantly from the iPhone's `TabView`-based layout. This creates several problems:

- **Inconsistency**: iPad users get a completely different navigation paradigm (sidebar + 3-column split) than iPhone users (tab bar). Users switching between devices must learn two UIs.
- **Wasted space in portrait**: The sidebar + content + detail three-column layout compresses content in portrait orientation, leaving the detail column nearly empty most of the time.
- **No tab bar**: The custom bottom tab bar on iPhone (with account switcher, quick-switch, moderation badge) is entirely absent on iPad. Key features like the double-tap account switch are missing.
- **Complexity**: 15 iPad-specific files (~1,500 lines) maintain a parallel navigation system that duplicates functionality.
- **Split-view burden**: Many iPad-specific views (`iPadListsView`, `iPadListDetailView`, `iPadProfileInspector`, `iPadDashboardView`) are thin wrappers that add complexity without meaningful iPad optimization.

The goal is to unify iPhone and iPad navigation — use the same `TabView`-based layout everywhere, with adaptive layouts that respond to the iPad's larger canvas in portrait and landscape.

## What Changes

- **Remove `NavigationSplitView`**: Replace `iPadRootView`'s `NavigationSplitView` + sidebar with a shared `TabView`-based layout identical to the iPhone's `compactBody`
- **Remove iPad-specific wrapper views**: Delete or inline thin wrappers (`iPadTimelineView`, `iPadNotificationsView`, `iPadChatView`, `iPadMentionsSearchWrapper`, `iPadDashboardView`, `iPadListsView`, `iPadListDetailView`, `iPadProfileInspector`, `iPadEmptyDetailPlaceholder`)
- **Adaptive content sizing**: Use `horizontalSizeClass` and `verticalSizeClass` to adjust layouts within views — wider grids in landscape, narrower in portrait
- **Keep iPad-only enhancements**: Preserve `iPadCommandPalette` (Cmd+K), keyboard shortcuts, drag-and-drop (`iPadDragDrop`), and the onboarding sheet — but integrate them as modifiers on the shared `TabView` body rather than requiring `iPadRootView`
- **Simplify `RootView`**: Remove the `horizontalSizeClass` branching entirely — iPad and iPhone use the same `compactBody` tab layout
- **Two-column landscape layout**: In landscape on iPad, explore using a `NavigationSplitView` only within specific tabs (e.g., lists) rather than as the top-level navigation

## Capabilities

### New Capabilities

- `unified-navigation`: Shared `TabView`-based layout for both iPhone and iPad — same tab bar, same account switcher, same quick-switch gesture
- `ipad-adaptive-layouts`: Per-view responsive layouts that adjust columns, spacing, and presentation based on horizontal/vertical size class — wider in landscape, narrower in portrait
- `ipad-landscape-dual-column`: Optional `NavigationSplitView` inside individual tabs (e.g., moderation → lists) when in landscape regular width, providing a detail column without a global sidebar

### Modified Capabilities

- `quick-account-switch`: Extended to iPad — double-tap account switcher currently only works on iPhone; iPad users get the same gesture
- `performance-monitor`: Performance overlay visibility and gesture toggle extended to iPad

## Impact

| Area | Files | Change |
|------|-------|--------|
| **Removed iPad wrappers** | `iPadTimelineView.swift`, `iPadNotificationsView.swift`, `iPadChatView.swift`, `iPadMentionsSearchWrapper.swift`, `iPadDashboardView.swift`, `iPadListsView.swift`, `iPadListDetailView.swift`, `iPadProfileInspector.swift`, `iPadEmptyDetailPlaceholder.swift` | Delete these files (their content is already available via iPhone views) |
| **Removed iPad navigation** | `iPadSidebar.swift`, `iPadNavigationState.swift` | Delete — no longer needed |
| **Removed iPad root** | `iPadRootView.swift` | Delete — replaced by shared `compactBody` |
| **Kept iPad-only** | `iPadCommandPalette.swift`, `iPadDragDrop.swift`, `iPadKeyboardShortcuts.swift` | Preserved, integrated into shared layout |
| **Modified** | `RootView.swift` | Remove `horizontalSizeClass` branch; apply iPad-only modifiers (Cmd+K palette, keyboard shortcuts, drag-drop) conditionally; remove `compactBody` wrapper |
| **Per-view adaptation** | `DashboardView`, `ListsView`, `RelationshipsView`, `BlueskyProfileView`, `ConversationListView`, etc. | Add `horizontalSizeClass`-responsive grids, columns, and spacing |
| **Landscape dual-column** | Optional: `ListsView` or `ModerationSplitView` | In landscape regular width, wrap in `NavigationSplitView` for list+detail |

## Design Decisions

### 1. Same tab bar everywhere (no sidebar)

**Decision**: iPad uses the identical custom tab bar as iPhone — `HStack` with 6 tabs + account switcher in `safeAreaInset(edge: .bottom)`. No sidebar.

**Rationale**: Consistency. The tab bar already works well. The sidebar duplicates this navigation in a different form. iPad users get the account switcher, double-tap quick-switch, and moderation tab badge they're missing today.

**Trade-off**: The sidebar's sectioned layout (Moderation / Search / Social / System) is lost. Users navigate by tapping tabs, not browsing sections. This is acceptable because:
- The tab bar fits 5-6 items comfortably on iPad (more horizontal space)
- The "More" overflow on iPhone is not needed on iPad
- Frequently-used items (timeline, chat, moderation) are always one tap away

### 2. Remove `horizontalSizeClass` branching

**Decision**: `RootView` always renders the tab bar layout. No `if horizontalSizeClass == .regular { iPadRootView() }` branch.

**Rationale**: The branching was the source of the inconsistency. A single code path means any improvement to the tab bar benefits both platforms.

### 3. Per-view responsive layouts instead of iPad wrapper views

**Decision**: Instead of creating `iPad*View` files that wrap iPhone views, the existing views check `@Environment(\.horizontalSizeClass)` and adjust their internal layout (column count, spacing, presentation style).

**Examples:**
- `DashboardView` / `iPadDashboardView` → `DashboardView` checks `horizontalSizeClass` and uses `.adaptive(minimum:)` grid columns accordingly
- `ListsView` → in regular width, shows a two-column list+detail layout within the tab
- `BlueskyProfileView` → in regular width, shows info and timeline side-by-side instead of stacked

### 4. Preserve iPad-only power features

**Decision**: Cmd+K command palette, keyboard shortcuts (Cmd+L lists, Cmd+D dashboard, etc.), and drag-and-drop are kept and integrated into the shared layout via conditional modifiers.

```swift
// RootView body becomes:
TabBarLayout()
    .if(UIDevice.current.userInterfaceIdiom == .pad) {
        $0.background(Button("") { showCommandPalette.toggle() }
            .keyboardShortcut("k", modifiers: .command)
            .opacity(0))
        .environmentObject(iPadKeyboardShortcuts.shared)
    }
```

### 5. Keyboard shortcuts become global

**Decision**: Keyboard shortcuts (`.commands` builder in `RULYXApp.swift`) are always active, not iPad-only. Mac Catalyst compatibility is a side benefit.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| **Tab bar items won't all fit on iPad landscape** (6+ tabs + accounts) | iPad has enough width for all items without overflow. If needed, combine Info/Accounts into a "More" menu like iPhone. |
| **Content feels stretched in landscape** | Per-view adaptive layouts use `LazyVGrid` with `adaptive(minimum:)` to add columns as width increases. Max widths on list views prevent line-length readability issues. |
| **Cmd+K palette defined in iPadRootView** | Extract `iPadCommandPalette` as a reusable modifier/overlay that works on any root view. |
| **iPadDragDrop only wired in iPadListDetailView** | Move drag-drop support into the shared `ListsView` and `BlueskyActorRow` components so it works regardless of platform. |
| **15 iPad files to remove + modify** | Each file is small (avg ~100 lines). The total deletion is ~1,200 lines. Can be done incrementally per view. |

## Migration Plan

1. **Phase 1 — Unify RootView**: Remove `horizontalSizeClass` branching. Move iPad-only modifiers (command palette, keyboard shortcuts) into the shared body. Verify build.
2. **Phase 2 — Delete iPad wrapper views**: Remove `iPadTimelineView`, `iPadNotificationsView`, `iPadChatView`, `iPadMentionsSearchWrapper`. Verify each tab still works.
3. **Phase 3 — Adapt Dashboard**: Merge `iPadDashboardView`'s grid layout into `DashboardView` via `horizontalSizeClass` check. Remove `iPadDashboardView`.
4. **Phase 4 — Adapt Lists**: Merge `iPadListsView` + `iPadListDetailView` into shared `ListsView` with optional landscape dual-column layout. Remove iPad files.
5. **Phase 5 — Adapt Profile**: Merge `iPadProfileInspector` into `BlueskyProfileView` with responsive layout. Remove iPad file.
6. **Phase 6 — Cleanup**: Remove `iPadSidebar.swift`, `iPadNavigationState.swift`, `iPadRootView.swift`, `iPadEmptyDetailPlaceholder.swift`. Update project.yml.
7. **Phase 7 — Polish**: Keyboard shortcut integration, drag-drop in shared components, onboarding sheet unification.

Each phase is independently buildable and testable — no need to remove all iPad files at once.
