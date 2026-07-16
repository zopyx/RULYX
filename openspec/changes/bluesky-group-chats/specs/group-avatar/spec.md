## ADDED Requirements

### Requirement: Group conversation rows show a generated group avatar
In the conversation list, group conversations SHALL display a generated avatar instead of a single member's avatar. The generated avatar SHALL combine the first few member avatars in a stacked layout (max 4), overlaid with a member count badge when >4 members. When member avatars are unavailable, fall back to initials of the group name or "G" for group.

#### Scenario: Group with member avatars
- **WHEN** a group conversation has 3 members with avatar URLs
- **THEN** the cell shows a 2×2 grid with the 3 member avatars (one slot empty)
- **WHEN** a group has 5+ members
- **THEN** the cell shows a +N badge in the last slot

#### Scenario: Group without avatars
- **WHEN** a group conversation has no member avatars
- **THEN** the cell shows the group name initials (or "G" for unnamed groups) as a centered letter avatar

### Requirement: Conversation detail shows group indicator
The navigation bar for a group conversation SHALL display:
- The group avatar (same generated style)
- The group name (truncated to one line)
- Subtitle showing member count (e.g., "8 members")

#### Scenario: Group conversation header
- **WHEN** viewing a group conversation
- **THEN** the navigation bar shows the group avatar + name + member count subtitle
