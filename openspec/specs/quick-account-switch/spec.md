# quick-account-switch Specification

## Purpose
TBD - created by archiving change quick-account-switch. Update Purpose after archive.
## Requirements
### Requirement: The system SHALL track the previously active account
`AccountStore` SHALL maintain a `previousActiveAccountID` property that stores the ID of the account that was active before the current one. This SHALL be updated atomically whenever `switchAccount()` is called.

#### Scenario: First account switch
- **WHEN** the user switches from account A to account B
- **THEN** `previousActiveAccountID` SHALL be set to account A's ID

#### Scenario: Subsequent switch
- **WHEN** the user switches from account B to account C
- **THEN** `previousActiveAccountID` SHALL be updated to account B's ID (the account that was active before the switch)

#### Scenario: No previous account
- **WHEN** only one account exists
- **THEN** `previousActiveAccountID` SHALL be `nil`

#### Scenario: Preferred search account unchanged
- **WHEN** `switchAccount()` updates the active and previous account IDs
- **THEN** the `preferredSearchAccountID` SHALL remain unchanged

### Requirement: Double-tapping the account switcher SHALL switch to the previous account
The account avatar button in the bottom tab bar SHALL support a double-tap gesture. On double-tap, if a previous account exists, the system SHALL switch to that account.

#### Scenario: Double-tap with previous account
- **WHEN** the user double-taps the account avatar
- **AND** `previousActiveAccountID` is set
- **THEN** the app SHALL switch to the previous account
- **THEN** the system SHALL play an impact (rigid) haptic

#### Scenario: Double-tap without previous account
- **WHEN** the user double-taps the account avatar
- **AND** `previousActiveAccountID` is `nil`
- **THEN** nothing SHALL happen (no switch, no error)

#### Scenario: Single tap still opens switcher
- **WHEN** the user single-taps the account avatar
- **THEN** the account switcher sheet SHALL still open as before

### Requirement: A visual indicator SHALL show when quick-switch is available
When `previousActiveAccountID` is set, the account avatar in the tab bar SHALL display a subtle visual hint that a double-tap will switch accounts.

#### Scenario: Previous account available
- **WHEN** `previousActiveAccountID` is not `nil`
- **THEN** a small arrow badge (chevron.left.2) SHALL appear over the account avatar

