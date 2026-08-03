# session-reauthentication Specification

## Purpose
When the Bluesky session or token is rejected (expired token, rotated app password, missing credentials), the user gets a visible re-login option instead of being stuck with a retry loop that can never succeed.

## ADDED Requirements

### Requirement: Authentication failures SHALL carry the server message
`BlueskyAPIError.unauthorized` SHALL carry the server-provided error message (e.g. `"Token has expired"`) when the PDS returns one. When no server message is available, the generic message SHALL be used.

#### Scenario: PDS returns an auth error message
- **WHEN** the PDS returns HTTP 401 with a JSON error payload containing a message (e.g. `"Token has expired"`)
- **THEN** the surfaced error SHALL display that server message

#### Scenario: PDS returns 401 without a message
- **WHEN** the PDS returns HTTP 401 without a parseable message
- **THEN** the surfaced error SHALL display the generic "rejected credentials" message

### Requirement: Exhausted authentication retries SHALL trigger a re-login prompt
When `BlueskySessionService.performAuthenticatedRequest` exhausts all recovery attempts (refresh failed, re-authentication with the stored password failed) and throws an authentication error, the system SHALL post an `.authenticationFailed` notification identifying the affected account. The same SHALL apply when no stored password exists (`missingCredentials`) and when chat API calls fail with an auth error.

#### Scenario: Token expired and recovery fails
- **WHEN** an authenticated request fails with 401
- **AND** the refresh-token recovery fails
- **AND** re-authentication with the stored app password fails
- **THEN** the system SHALL post `.authenticationFailed` for that account

#### Scenario: Missing stored credentials
- **WHEN** an authenticated request cannot find a stored password for the account
- **THEN** the system SHALL post `.authenticationFailed` for that account

#### Scenario: Chat authentication failure
- **WHEN** a chat API call fails with an authentication error
- **THEN** the system SHALL post `.authenticationFailed` for the chat account

### Requirement: The app SHALL present a re-authentication sheet
`RootView` (iPhone) and `iPadRootView` (iPad) SHALL observe `.authenticationFailed` and present a re-authentication sheet for the affected account. The sheet SHALL show the account (avatar, display name, handle), a secure password field, and a "Sign In" action. It SHALL be dismissible.

#### Scenario: Auth failure while browsing
- **WHEN** an `.authenticationFailed` notification is posted for an account
- **THEN** the re-authentication sheet SHALL appear for that account

#### Scenario: Sheet dismissed
- **WHEN** the user dismisses the re-authentication sheet without signing in
- **THEN** the sheet SHALL close and the app SHALL remain usable (error states with RETRY remain visible)

### Requirement: Re-authentication SHALL restore the account
The re-authentication sheet SHALL validate the entered app password against the PDS. On success the system SHALL: persist the new password in the Keychain, replace the persisted session, clear account-scoped caches, refresh the account profile, and clear the pending authentication error. The affected views SHALL then be able to reload successfully.

#### Scenario: Successful re-authentication
- **WHEN** the user enters a valid app password in the re-authentication sheet
- **THEN** the Keychain password SHALL be updated
- **THEN** the persisted session SHALL be replaced with a fresh one
- **THEN** the account profile SHALL be refreshed (avatar/display name updated)
- **THEN** chat SHALL reload automatically
- **THEN** previously failing RETRY actions SHALL succeed

#### Scenario: Invalid password entered
- **WHEN** the user enters an invalid app password
- **THEN** the sheet SHALL show an error message and SHALL NOT dismiss

### Requirement: Chat SHALL reload after re-authentication
The app SHALL observe the `.accountReauthenticated` notification and reload the chat conversations for the active account.

#### Scenario: Chat recovers after re-login
- **WHEN** re-authentication succeeds
- **THEN** the chat store SHALL rebuild its conversations for the active account
