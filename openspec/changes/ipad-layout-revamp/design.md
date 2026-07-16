## Context

The current iPad layout has 15 files (~1,536 lines) maintaining a parallel navigation system:

| Group | Files | Purpose |
|-------|-------|---------|
| Root + Navigation | `iPadRootView.swift`, `iPadSidebar.swift`, `iPadNavigationState.swift` | `NavigationSplitView` + sidebar + column state |
| Tab wrappers | `iPadTimelineView.swift`, `iPadNotificationsView.swift`, `iPadChatView.swift`, `iPadMentionsSearchWrapper.swift` | Thin wrappers injecting environment objects into iPhone views |
| View replacements | `iPadListsView.swift`, `iPadListDetailView.swift`, `iPadProfileInspector.swift`, `iPadDashboardView.swift` | iPad-specific implementations with different layouts |
| Power features | `iPadCommandPalette.swift`, `iPadKeyboardShortcuts.swift`, `iPadDragDrop.swift` | iPad-only enhancements (command palette, keyboard shortcuts, drag-and-drop) |

The iPhone uses a custom `HStack` tab bar with account switcher, double-tap quick-switch, and moderation badge — none of which exist on iPad today.

## Goals / Non-Goals

**Goals:**
- Same tab bar navigation on iPhone and iPad
- Remove 9 iPad-specific wrapper files (~800 lines deleted)
- Per-view responsive layouts using size classes instead of separate views
- Preserve Cmd+K palette, keyboard shortcuts, drag-drop
- iPad landscape dual-column within tabs (not as top-level nav)

**Non-Goals:**
- Completely removing all iPad-specific code (command palette, drag-drop, keyboard shortcuts stay)
- Changing the iPhone layout at all
- Adding new features beyond layout unification
- macOS Catalyst support

## Implementation Strategy

### Phase 1 — RootView unification (smallest change, highest impact)

**Before:**
```swift
var body: some View {
    if horizontalSizeClass == .regular {
        iPadRootView()
            .environmentObject(...)
    } else {
        compactBody
    }
}
```

**After:**
```swift
var body: some View {
    VStack(spacing: 0) {
        ClearskyBanner()  // if needed
        ZStack { /* tab content */ }
    }
    .safeAreaInset(edge: .bottom) { /* tab bar */ }
    .overlay { /* Cmd+K palette on iPad */ }
    .background { /* keyboard shortcut buttons */ }
    .environment(\.layoutDirection, ...)
    .preferredColorScheme(...)
    // ... existing modifiers ...
}
```

The key: `compactBody` moves into `body` directly, and iPad-only overlays/backgrounds are added conditionally with `if UIDevice.current.userInterfaceIdiom == .pad`.

### Phase 2 — Delete wrapper views

These files wrap an iPhone view in environment objects and nothing else:

| File | Content | Action |
|------|---------|--------|
| `iPadTimelineView.swift` | Wraps `TimelineTab()` | Delete; use `TimelineTab` directly |
| `iPadNotificationsView.swift` | Wraps `NotificationTab()` | Delete; use `NotificationTab` directly |
| `iPadChatView.swift` | Wraps `ChatTab()` | Delete; use `ChatTab` directly |
| `iPadMentionsSearchWrapper.swift` | Wraps `MentionsSearchView` | Delete; use `MentionsSearchView` directly |

### Phase 3 — Merge adaptive views

| iPad File | Target | Adaptation |
|-----------|--------|------------|
| `iPadDashboardView.swift` | `DashboardView.swift` | `horizontalSizeClass` → grid columns |
| `iPadListsView.swift` + `iPadListDetailView.swift` | `ListsView.swift` | `horizontalSizeClass` → `NavigationSplitView` within tab |
| `iPadProfileInspector.swift` | `BlueskyProfileView.swift` | `horizontalSizeClass` → side-by-side layout |

### Phase 4 — Remove navigation framework

Delete `iPadRootView.swift`, `iPadSidebar.swift`, `iPadNavigationState.swift`, `iPadEmptyDetailPlaceholder.swift`.

### Phase 5 — Port power features

| Feature | Current home | New home |
|---------|-------------|----------|
| Cmd+K palette | `iPadRootView` | Shared `RootView` (`.overlay`) |
| Keyboard shortcuts | `iPadKeyboardShortcuts.swift` | Shared `RootView` (`.background` buttons) |
| Drag-drop | `iPadDragDrop.swift` | Shared views (`ListsView`, `BlueskyActorRow`) |

## Risks

| Risk | Mitigation |
|------|------------|
| **Tab bar looks cramped on iPhone with all items** | Not a risk — the current iPhone tab bar already handles all items. No change. |
| **iPad landscape feels underutilized** | Per-view adaptive layouts add columns. Dashboard uses 3+ column grid. Profile uses side-by-side. Lists use optional split-view. |
| **Command palette activation conflicts** | Cmd+K is only captured when no text field is focused. Same as current behavior. |
| **Keyboard shortcuts on iPhone cause false activations** | Restrict keyboard shortcuts to iPad idiom only (`if UIDevice.current.userInterfaceIdiom == .pad`). |
| **Drag-drop won't work without iPadListDetailView** | Move drag-drop modifiers to shared `BlueskyActorRow` and `ListsView` components. |
