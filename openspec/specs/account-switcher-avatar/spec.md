# account-switcher-avatar Specification

## Purpose
TBD - created by archiving change account-avatar-and-reauth. Update Purpose after archive.
## Requirements
### Requirement: The account switcher icon SHALL display the active account's avatar
The account switcher button in the bottom-right of the tab bar SHALL render the active account's avatar image whenever an active account exists. The avatar SHALL be loaded through the app's standard cached avatar pipeline (`FreshAvatarImage` / `ThumbnailPipeline`) so it survives view reappearances and app relaunches. When no avatar image is available yet, the button SHALL render the account's initial-letter placeholder; the generic `person.crop.circle` icon SHALL only appear when no account exists at all.

#### Scenario: Active account with avatar URL
- **WHEN** an active account exists and its `avatarURL` is set
- **THEN** the tab bar account switcher icon SHALL render that avatar image

#### Scenario: Active account without avatar URL yet
- **WHEN** an active account exists but its `avatarURL` is `nil`
- **THEN** the tab bar account switcher icon SHALL render the initial-letter placeholder (tinted circle with the account's first initial)

#### Scenario: No accounts at all
- **WHEN** no accounts are saved
- **THEN** the tab bar account switcher icon SHALL render the generic `person.crop.circle` icon

#### Scenario: Avatar image load failure
- **WHEN** the avatar image fails to load from the network
- **THEN** the tab bar account switcher icon SHALL keep showing the initial-letter placeholder instead of a blank area

### Requirement: Account profiles SHALL be refreshed eagerly at launch
The app SHALL call `AccountStore.refreshAccountProfiles` as part of its launch task chain so avatar URLs are populated before the user inspects the tab bar. The refresh SHALL NOT block the UI.

#### Scenario: Cold launch with saved accounts
- **WHEN** the app launches with saved accounts
- **THEN** the account profiles (including avatars) SHALL be fetched in the background shortly after launch

#### Scenario: Profile refresh fails
- **WHEN** the profile refresh fails (e.g. network error or expired token)
- **THEN** the launch flow SHALL continue normally and the tab bar SHALL keep showing the initial-letter placeholder

### Requirement: The avatar SHALL refresh after re-authentication
After a successful re-authentication (see `session-reauthentication` capability), the app SHALL refresh account profiles so an avatar that previously failed to load appears once the session is valid again.

#### Scenario: Avatar appears after re-login
- **WHEN** the user successfully re-authenticates an account whose avatar previously failed to load
- **THEN** the app SHALL refetch the account profile and update the tab bar icon with the avatar

