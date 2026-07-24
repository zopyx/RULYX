## ADDED Requirements

### Requirement: Compact list spacing in account switcher sheets
The account switcher sheet SHALL use compact list styling to minimize vertical whitespace between account rows and sections.

#### Scenario: AccountSwitcherTabSheet uses plain list style
- **WHEN** the user opens the "Switch Account" popup from the tab bar
- **THEN** the account list SHALL use `.listStyle(.plain)` instead of the default inset-grouped style
- **AND** the list SHALL have only the default minimum spacing between rows

#### Scenario: Section spacing is compact
- **WHEN** the "Switch Account" popup is open
- **THEN** the list SHALL apply `.listSectionSpacing(.compact)` to reduce the gap between the account list and the "Manage Accounts" section
- **AND** SHALL set `.environment(\.defaultMinListHeaderHeight, 0)` to eliminate hidden section header insets

#### Scenario: Single-section list with proper visual separation
- **WHEN** the account list has multiple accounts
- **THEN** the accounts SHALL be rendered without nested `Section` wrappers dividing them from the "Manage Accounts" button
- **AND** the "Manage Accounts" button SHALL use `listRowSeparator(.hidden)` to avoid double separators
- **AND** the overall layout SHALL fit all accounts in the sheet without requiring scrolling when 3 or fewer accounts are present

#### Scenario: Consistency across all account switcher sheets
- **WHEN** the user opens `AccountSwitcherSheet` (full management) or `AccountQuickSwitcherSheet`
- **THEN** the same compact spacing rules SHOULD be applied for visual consistency
