## ADDED Requirements

### Requirement: Leading swipe action adds actor to a list
The system SHALL provide a leading swipe action (left-to-right) on every member profile row in Followers, Following, Blocking, and Blocked by views that adds the actor to a moderation, internal, or curation list.

#### Scenario: Leading swipe opens list picker
- **WHEN** the user swipes left-to-right on a member row in any RelationshipsView mode
- **THEN** a `ListPickerSheet` is presented showing the user's available moderation, internal, and curation lists
- **AND** the leading swipe button is labeled "Add to List" with a `list.bullet` icon using `.tint(.blue)`

#### Scenario: Leading swipe allows full swipe for speed
- **WHEN** the user performs a full leading swipe gesture
- **THEN** the action triggers immediately without an intermediate confirmation step
- **AND** `allowsFullSwipe` SHALL be `true` for the leading swipe action

#### Scenario: List picker sheet closes after selection
- **WHEN** the user selects a list from the picker
- **THEN** the actor is added to the selected list
- **AND** the sheet dismisses automatically

#### Scenario: Leading swipe works identically in all four modes
- **WHEN** the user is viewing Followers, Following, Blocking, or Blocked by
- **THEN** the leading swipe action behaves identically, prompting the list picker
- **AND** no mode-specific customization is applied to the leading swipe

### Requirement: Trailing swipe blocks the actor
The system SHALL retain the existing trailing swipe action (right-to-left) on every member profile row that blocks the actor, with confirmation behavior driven by the existing `confirmBlocks` user preference.

#### Scenario: Trailing swipe shows block label
- **WHEN** the user swipes right-to-left on a member row
- **THEN** a red "Block" button with `hand.raised.fill` icon is shown with `.tint(.red)`
- **AND** `allowsFullSwipe` SHALL be `false` (requires explicit tap)

#### Scenario: Block confirmation respects preference
- **WHEN** the user taps the trailing swipe Block button AND `confirmBlocks` is `true`
- **THEN** the existing confirmation dialog is shown before blocking
- **AND** the block action only executes after the user confirms in the dialog

#### Scenario: Block bypasses confirmation when disabled
- **WHEN** the user taps the trailing swipe Block button AND `confirmBlocks` is `false`
- **THEN** the actor is blocked immediately without a confirmation dialog
- **AND** the actor is removed from the visible list

### Requirement: Context menu offers both block and add-to-list
The system SHALL retain the existing `.contextMenu` on member rows offering both "Block" and "Add to List" actions, serving as the non-swipe access path.

#### Scenario: Context menu duplicates swipe actions
- **WHEN** the user long-presses a member row
- **THEN** the context menu shows "Block" (destructive) and "Add to List"
- **AND** both actions behave identically to their swipe counterparts

### Requirement: Redundant .onDelete modifier is removed
The `.onDelete` modifier on the `ForEach` in RelationshipsView SHALL be removed, as it duplicates the trailing-swipe Block action without adding functionality and conflicts with swipe gesture semantics in SwiftUI lists.

#### Scenario: No onDelete behavior
- **WHEN** the user swipes with a delete gesture (full left swipe on iOS)
- **THEN** no system delete action is triggered
- **AND** the only trailing action is the explicit Block button
