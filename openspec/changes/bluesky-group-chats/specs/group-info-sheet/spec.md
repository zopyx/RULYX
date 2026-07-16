## ADDED Requirements

### Requirement: Group info sheet shows full group metadata
A `GroupInfoSheet` SHALL present a comprehensive view of a group conversation, accessible from the conversation detail toolbar. The sheet SHALL display:
- Group name (editable — see `group-name-editing` spec)
- Number of members (e.g., "8 members")
- Creation date (formatted medium style)
- Lock status ("Locked" / "Unlocked") with lock/unlock toggle button
- Full scrollable list of members with avatar, display name, handle, and role indicator (admin vs member)

#### Scenario: Open group info
- **WHEN** the user taps "Group Info" in the conversation detail toolbar
- **THEN** a sheet opens showing group name, member count, creation date, lock status, and member list

#### Scenario: Member list is scrollable
- **WHEN** the group has more members than fit on screen
- **THEN** the member list scrolls
- **WHEN** the user taps a member row
- **THEN** that member's profile is opened in a sheet

### Requirement: Group info sheet shows member role indicators
Members with administrative privileges SHALL be visually distinguished from regular members (e.g., an "Admin" badge next to their name).

#### Scenario: Admin badge visible
- **WHEN** viewing group info
- **THEN** admin members show an "Admin" badge or icon

(Note: This depends on the Bluesky API returning role/permission data per member. If the API does not support roles yet, this requirement is deferred.)
