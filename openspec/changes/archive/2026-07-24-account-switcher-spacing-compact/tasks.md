## 1. Compact AccountSwitcherTabSheet (RootView.swift)

- [x] 1.1 Change `List` to use `.listStyle(.plain)` and `.listSectionSpacing(.compact)`
- [x] 1.2 Merge the two `Section` wrappers into one, adding the "Manage Accounts" button as the last row
- [x] 1.3 Set `.environment(\.defaultMinListHeaderHeight, 0)` to eliminate hidden section header space
- [x] 1.4 Add `.listRowSeparator(.hidden)` to the "Manage Accounts" button row

## 2. Compact AccountSwitcherSheet (AccountSwitcherSheet.swift)

- [x] 2.1 Add `.listStyle(.plain)` to the full management sheet List
- [x] 2.2 Add `.listSectionSpacing(.compact)` and `.environment(\.defaultMinListHeaderHeight, 0)`

## 3. Build Verification

- [x] 3.1 Run `xcodebuild` to verify compilation
- [x] 3.2 Run `swiftformat --lint .` to verify formatting
- [x] 3.3 Run `swiftlint` to verify lint rules
