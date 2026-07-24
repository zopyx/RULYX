## Why

The "Switch Account" popup (AccountSwitcherTabSheet) uses default iOS List styling with Section groupings, creating excessive vertical whitespace between account rows and between the account list and the "Manage Accounts" section. This wastes sheet real estate, especially on compact devices where users may need to scroll to see all accounts.

## What Changes

- Apply `.listStyle(.plain)` to the AccountSwitcherTabSheet List
- Apply `.listSectionSpacing(.compact)` to reduce section-to-section gap
- Apply `.environment(\.defaultMinListHeaderHeight, 0)` to suppress hidden section header heights
- Remove unnecessary `Section` wrappers — use a single flat List with the "Manage Accounts" button at the bottom, styled consistently
- Optionally apply the same optimizations to `AccountSwitcherSheet` (full management sheet) and `AccountQuickSwitcherSheet` for consistency

## Capabilities

### New Capabilities
- `account-switcher-compact-layout`: Defines the visual density and spacing rules for account list views in sheets.

### Modified Capabilities
- *(none — this is a pure UI layout change, no behavior or requirement changes)*

## Impact

- **Files modified**:
  - `Sources/App/RootView.swift` — AccountSwitcherTabSheet List style and spacing
  - `Sources/Shared/Components/AccountSwitcherSheet.swift` — optional consistency improvements
  - `Sources/Shared/Components/AccountQuickSwitcherSheet.swift` — already partially done, verify consistency
- No API, data model, or behavior changes
- No localization changes
