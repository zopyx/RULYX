## Context

The "Switch Account" popup (`AccountSwitcherTabSheet`) is used from the tab bar and shows all saved accounts for quick switching. The current implementation wraps account rows in a `Section {}` and the "Manage Accounts" button in a separate `Section {}`, with default iOS list styling (`.insetGrouped`) that adds significant vertical padding between rows and sections. On devices with 3-4 accounts, the extra spacing forces scrolling unnecessarily.

The `AccountQuickSwitcherSheet` already applies `.listStyle(.plain)`, `.listSectionSpacing(.compact)`, and hides default list headers — but it's not actually wired into the app. The `AccountSwitcherSheet` (full management) also uses a default `List` without spacing optimizations.

## Goals / Non-Goals

**Goals:**
- Reduce vertical whitespace between account rows in `AccountSwitcherTabSheet`
- Reduce the gap between the account list and the "Manage Accounts" section
- Make the sheet compact enough to show 3-4 accounts without scrolling
- Apply consistent spacing rules to `AccountSwitcherSheet` (full management)

**Non-Goals:**
- Not changing the layout, size, or content of individual account rows
- Not changing the `AccountQuickSwitcherSheet` (it's unused in production — would need wiring, which is out of scope)
- Not changing any behavior, data flow, or API calls
- Not changing iPad-specific account switcher views (if any)

## Decisions

**Decision 1: Use `.listStyle(.plain)` instead of default inset-grouped**
- Default iOS List style (`.insetGrouped` in iOS 17+) adds rounded corners, background insets, and section padding that inflate vertical space
- `.plain` style keeps the list flush with sheet edges, with minimal row spacing
- Already proven in `AccountQuickSwitcherSheet` (existing pattern in the codebase)

**Decision 2: Merge sections — accounts + manage button in one flat Section**
- Current code wraps account rows in `Section {}` and manage button in a separate `Section {}`
- Two sections means section-to-section spacing (even with `.compact`)
- Merging into one `Section {}` with the manage button as the last row eliminates the gap
- The manage button uses `.listRowSeparator(.hidden)` to avoid an orphaned separator line

**Decision 3: Also clean up `AccountSwitcherSheet`**
- Uses the same default List styling, suffers from the same spacing issue
- Apply `.listStyle(.plain)` there too
- However, `AccountSwitcherSheet` has drag-to-reorder (`.onMove`) and swipe-to-delete (`.onDelete`) — `.plain` list still supports these

**Decision 4: Add `.padding(.vertical, 2)` reduction to row spacing in AccountSwitcherTabSheet (if needed)**
- The `AccountRowView` already has `.padding(.vertical, 2)` on its VStack
- Additional row-level padding should be avoided — the list style change should be sufficient

## Risks / Trade-offs

- **[Minor] Plain list removes rounded corners and inset background** — The sheet's `presentationBackground` is already set to `.systemBackground` in `AccountSwitcherTabSheet`, so row backgrounds will be flush with the sheet edge. This is consistent with modern iOS design patterns (the Settings app uses inset-grouped, but quick-action sheets use plain).
- **[Low] `.onMove` / `.onDelete` still work with `.plain`** — Confirmed: these are List-level modifiers, not style-dependent.
- **[Low] `AccountSwitcherSheet` has a `ContentUnavailableView` for empty state** — Already inside a `List`, so `.listStyle(.plain)` won't affect it negatively.
