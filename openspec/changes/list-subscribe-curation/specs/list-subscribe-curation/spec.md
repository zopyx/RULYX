## ADDED Requirements

### Requirement: Subscribe/Unsubscribe SHALL be available for all non-owned list kinds
The list detail view SHALL display subscribe/unsubscribe controls for any list the current user does not own, regardless of list kind (moderation, internal, or regular).

#### Scenario: Viewing a non-owned moderation list
- **WHEN** the user opens the detail view of a moderation list they do not own
- **THEN** the subscribe/unsubscribe section SHALL be visible with the current subscription state

#### Scenario: Viewing a non-owned curation list (internal)
- **WHEN** the user opens the detail view of an internal curation list they do not own
- **THEN** the subscribe/unsubscribe section SHALL be visible with the current subscription state

#### Scenario: Viewing a non-owned curation list (regular)
- **WHEN** the user opens the detail view of a regular curation list they do not own
- **THEN** the subscribe/unsubscribe section SHALL be visible with the current subscription state

#### Scenario: Viewing an owned list
- **WHEN** the user opens the detail view of a list they own (any kind)
- **THEN** no subscribe/unsubscribe section SHALL be shown (owner cannot subscribe to their own list)

### Requirement: Subscription state SHALL be checked on view load for all non-owned lists
When the list detail view loads a non-owned list, the system SHALL query the API to determine whether the current user is subscribed.

#### Scenario: Subscription check for moderation list
- **WHEN** the list detail view loads a non-owned moderation list
- **THEN** the system SHALL call `isSubscribedToModerationList` to set the initial toggle state

#### Scenario: Subscription check for curation list
- **WHEN** the list detail view loads a non-owned internal or regular list
- **THEN** the system SHALL call `isSubscribedToModerationList` (same endpoint) to set the initial toggle state

### Requirement: Subscribe/Unsubscribe API SHALL work for all list kinds
The existing `subscribeToModerationList` and `unsubscribeFromModerationList` methods SHALL be used for all list kinds. The underlying AT Protocol endpoints (`app.bsky.graph.muteActorList` / `unmuteActorList`) are list-kind-agnostic and SHALL be called identically regardless of list kind.

#### Scenario: Subscribing to a curation list
- **WHEN** the user taps "Subscribe" on a non-owned internal list
- **THEN** the system SHALL call `subscribeToModerationList` with the list URI
- **THEN** the toggle SHALL switch to subscribed state on success

#### Scenario: Unsubscribing from a curation list
- **WHEN** the user taps "Unsubscribe" on a non-owned regular list
- **THEN** the system SHALL call `unsubscribeFromModerationList` with the list URI
- **THEN** the toggle SHALL switch to unsubscribed state on success

### Requirement: Error handling SHALL be consistent across all list kinds
Subscribe/unsubscribe errors SHALL display the same error UI regardless of list kind.

#### Scenario: Subscribe fails for curation list
- **WHEN** the subscribe API call fails for a curation list
- **THEN** an error message SHALL appear in the subscribe section (same as for moderation lists)
- **THEN** the toggle SHALL remain in its previous state
