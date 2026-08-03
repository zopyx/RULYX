# error-relogin-button Specification

## ADDED Requirements

### Requirement: Authentication-failure error states SHALL offer a Re-Login action
Any error state that displays an authentication failure (rejected/expired credentials) SHALL show a "Re-Login" button alongside the Retry button. Tapping Re-Login SHALL present the re-authentication sheet for the affected account.

#### Scenario: Token expired in a banner-based error state
- **WHEN** an account's session is rejected and `.authenticationFailed` is posted
- **THEN** every visible `ErrorRetryBanner` SHALL additionally show a "Re-Login" button
- **AND** tapping it SHALL present the re-authentication sheet

#### Scenario: Chat error state with auth failure
- **WHEN** the chat list or conversation detail shows an authentication error
- **THEN** a "Re-Login" button SHALL be shown next to Retry

#### Scenario: Timeline load failure with auth failure
- **WHEN** the timeline is in the failed state due to an authentication error
- **THEN** the failed state SHALL offer "Re-Login" (and Retry)

#### Scenario: Non-auth error
- **WHEN** the error is a network or server error (not authentication)
- **THEN** no "Re-Login" button SHALL appear; only Retry is shown

#### Scenario: Re-auth succeeds or account switches
- **WHEN** re-authentication succeeds or the active account switches
- **THEN** the "Re-Login" buttons SHALL disappear from error states
