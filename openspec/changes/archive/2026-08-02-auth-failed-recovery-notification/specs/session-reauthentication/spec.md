# auth-failed-recovery-notification Specification

## MODIFIED Requirements

### Requirement: Exhausted authentication retries SHALL trigger a re-login prompt
When `BlueskySessionService.performAuthenticatedRequest` fails with an authentication error, the system SHALL post an `.authenticationFailed` notification identifying the affected account. This SHALL apply when:
- the original operation throws `.unauthorized` or `.missingCredentials` and all recovery attempts fail (existing behavior), AND
- the **credential-recovery path itself** throws `.unauthorized` or `.missingCredentials` — i.e. session restore (`cachedSession`) or in-loop recovery (`recoverSession`) fails because the stored refresh token and/or app password are rejected (e.g. the app password was rotated on bsky.social).

The notification SHALL carry `userInfo["accountID"]` (UUID string) and, when available, `userInfo["message"]` with the server-provided error message.

#### Scenario: Token expired and recovery fails
- **WHEN** an authenticated request fails with 401
- **AND** the refresh-token recovery fails
- **AND** re-authentication with the stored app password fails with 401
- **THEN** the system SHALL post `.authenticationFailed` for that account

#### Scenario: Session restore fails with rejected credentials
- **WHEN** `cachedSession` cannot restore a session because the stored password is rejected (createSession returns 401)
- **THEN** the system SHALL post `.authenticationFailed` for that account
- **AND** the original error SHALL still be rethrown

#### Scenario: Missing stored credentials
- **WHEN** an authenticated request cannot find a stored password for the account
- **THEN** the system SHALL post `.authenticationFailed` for that account

#### Scenario: Chat authentication failure
- **WHEN** a chat API call fails with an authentication error
- **THEN** the system SHALL post `.authenticationFailed` for the chat account
