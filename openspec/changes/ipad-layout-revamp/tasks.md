## 1. Unify RootView

- [ ] 1.1 Remove `horizontalSizeClass` branching from `RootView.body` — always render the tab bar layout
- [ ] 1.2 Move `Cmd+K` command palette overlay into shared body (conditional on iPad idiom)
- [ ] 1.3 Move keyboard shortcut `.background(Button("")...)` into shared body (conditional on iPad idiom)
- [ ] 1.4 Ensure `ClearskyBanner` + tab bar + onboarding sheet work identically on iPad
- [ ] 1.5 Remove `iPadRootView` invocation from `RootView`
- [ ] 1.6 Verify build: `xcodebuild -project RULYX.xcodeproj -scheme RULYX -destination 'platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`

## 2. Delete thin iPad wrapper views

- [ ] 2.1 Delete `iPadTimelineView.swift` — use `TimelineTab()` directly in content column (if any column switch remains) or rely on tab-based nav
- [ ] 2.2 Delete `iPadNotificationsView.swift` — use `NotificationTab()` directly
- [ ] 2.3 Delete `iPadChatView.swift` — use `ChatTab()` directly
- [ ] 2.4 Delete `iPadMentionsSearchWrapper.swift` — use `MentionsSearchView()` directly
- [ ] 2.5 Update `project.yml` to remove deleted files
- [ ] 2.6 Run `xcodegen generate` and build

## 3. Adapt DashboardView

- [ ] 3.1 Add `@Environment(\.horizontalSizeClass) private var horizontalSizeClass` to `DashboardView`
- [ ] 3.2 In regular width: use `iPadDashboardView`'s grid layout (`LazyVGrid` with `adaptive(minimum: 300, maximum: 450)`)
- [ ] 3.3 In compact width: use current iPhone layout (single-column scroll)
- [ ] 3.4 Copy `accountsCard`, `opsChartCard`, `topModeratedCard`, `blockActivityCard`, `engagementCard` from `iPadDashboardView` into `DashboardView`
- [ ] 3.5 Delete `iPadDashboardView.swift`
- [ ] 3.6 Verify build

## 4. Adapt ListsView for landscape dual-column

- [ ] 4.1 Add `@Environment(\.horizontalSizeClass)` to `ListsView` (or `ModerationSplitView` — determine the right container)
- [ ] 4.2 In regular landscape width: wrap in `NavigationSplitView` with list sidebar + detail column
- [ ] 4.3 In compact: keep current single-column `NavigationStack` with push navigation
- [ ] 4.4 Copy `iPadListsView`'s list-of-lists UI and `iPadListDetailView`'s member viewer into the shared `ListsView`
- [ ] 4.5 Delete `iPadListsView.swift` and `iPadListDetailView.swift`
- [ ] 4.6 Verify build

## 5. Adapt BlueskyProfileView

- [ ] 5.1 Add `@Environment(\.horizontalSizeClass)` to `BlueskyProfileView`
- [ ] 5.2 In regular width: show profile info panel + posts timeline side-by-side (copy layout from `iPadProfileInspector`)
- [ ] 5.3 In compact: keep current stacked layout
- [ ] 5.4 Delete `iPadProfileInspector.swift`
- [ ] 5.5 Verify build

## 6. Clean up navigation infrastructure

- [ ] 6.1 Delete `iPadRootView.swift` — no longer used
- [ ] 6.2 Delete `iPadSidebar.swift` — no longer used
- [ ] 6.3 Delete `iPadNavigationState.swift` — no longer used
- [ ] 6.4 Delete `iPadEmptyDetailPlaceholder.swift` — no longer used
- [ ] 6.5 Remove all references to `SidebarItem`, `iPadNavigationState`, `iPadRootView` across the codebase
- [ ] 6.6 Update `project.yml` to remove deleted files
- [ ] 6.7 Run `xcodegen generate` and build

## 7. Port iPad power features

- [ ] 7.1 Move `iPadCommandPalette` overlay into `RootView` (conditional on iPad idiom)
- [ ] 7.2 Move keyboard shortcut `.background` buttons into `RootView` (conditional on iPad idiom)
- [ ] 7.3 Ensure drag-drop from `iPadDragDrop.swift` works in shared `ListsView` and `BlueskyActorRow`
- [ ] 7.4 Remove `iPadDragDrop.swift` if its modifiers are integrated into shared components
- [ ] 7.5 Verify Cmd+K palette works on iPad
- [ ] 7.6 Verify Cmd+L, Cmd+D, Cmd+F, Cmd+T keyboard shortcuts work on iPad
- [ ] 7.7 Verify build

## 8. Verification

- [ ] 8.1 Build: `xcodebuild -project RULYX.xcodeproj -scheme RULYX -destination 'platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- [ ] 8.2 Run `make lint` — SwiftFormat + SwiftLint pass
- [ ] 8.3 Verify no `iPadRootView` references remain in any source file
- [ ] 8.4 Verify no `iPad*` wrapper files remain in the file system (except preserved: command palette, keyboard shortcuts, drag-drop if not integrated)
- [ ] 8.5 Manual test: iPhone portrait — tab bar works, no layout regression
- [ ] 8.6 Manual test: iPad portrait — tab bar visible, content fills width
- [ ] 8.7 Manual test: iPad landscape — content adapts (dashboard grid, profile side-by-side, etc.)
- [ ] 8.8 Manual test: iPad Cmd+K palette opens and navigates
- [ ] 8.9 Validate OpenSpec: `openspec validate ipad-layout-revamp --json`
