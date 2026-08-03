# quick-account-switch Delta Specification

## ADDED Requirements

### Requirement: The account switcher icon SHALL always display the active account's avatar
The account switcher icon in the bottom tab bar SHALL display the active account's avatar whenever an active account exists, including the case where the avatar image has not been fetched yet (initial-letter placeholder) or fails to load. The generic `person.crop.circle` icon SHALL only be used when no account exists.

#### Scenario: Avatar not yet fetched
- **WHEN** an active account exists but its avatar URL has not been populated yet
- **THEN** the account switcher icon SHALL show the initial-letter placeholder instead of the generic person icon

#### Scenario: Avatar fetch fails
- **WHEN** the active account has an avatar URL but the image cannot be loaded
- **THEN** the account switcher icon SHALL keep showing the initial-letter placeholder
