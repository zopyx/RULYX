---
source: Bluesky AT Protocol Lexicons (github.com/bluesky-social/atproto)
library: Bluesky Social
package: chat.bsky
topic: Group Chats (creating, managing, join links)
fetched: 2026-06-12T18:30:00Z
official_docs: https://github.com/bluesky-social/atproto/tree/main/lexicons/chat/bsky
---

# Bluesky Group Chat API

**Status:** [NOTE: This is under active development and should be considered unstable while this note is here] (per multiple lexicon files)

## Group Chat Concepts

Bluesky group chats have the following characteristics:

- Groups are conversations of `kind: "group"` (vs `"direct"`)
- Each group has **one owner** (the creator, with `memberRole: "owner"`)
- All other members have `memberRole: "standard"`
- Groups have a **name** (required, min 1, max 50 graphemes for creation, 128 for editing)
- Groups have a **member limit** (returned by `getStatus`)
- Groups can be **locked** (prevents new content) or **unlocked**
- Groups support **join links** for invitation sharing
- Group members are added in **`"request"` status** and must accept

## Creating Groups

### `chat.bsky.group.createGroup` (procedure)

Creates a new group conversation. Unlike `getConvoForMembers` (which is idempotent for direct convos), this **always creates a new group**, even if identical membership exists.

**Input:**
```json
{
  "members": ["did:plc:member1", "did:plc:member2", ...],  // Max 49 DIDs
  "name": "My Awesome Group"  // Min 1, max 50 graphemes / 500 chars
}
```

**Response:**
```json
{
  "convo": chat.bsky.convo.defs#convoView
}
```

**Errors:**
- `AccountSuspended`: Creator's account is suspended
- `BlockedActor` / `BlockedSubject`: Block relationships prevent adding
- `NewAccountCannotCreateGroup`: New accounts restricted
- `NotFollowedBySender`: Member doesn't follow creator (depends on their `allowIncoming` / `allowGroupInvites`)
- `RecipientNotFound`: Member doesn't exist
- `UserForbidsGroups`: Member has `allowGroupInvites: "none"`

**Behavior:**
- All non-owner members are added with `status: "request"`
- Owner is automatically `status: "accepted"`
- Members get a `logBeginConvo` event
- System message `systemMessageDataAddMember` is created for added members

## Managing Group Members

### `chat.bsky.group.addMembers` (procedure)

Adds members to an existing group.

**Input:**
```json
{
  "convoId": "string",
  "members": ["did:plc:newmember1", ...]  // At least 1 DID
}
```

**Response:**
```json
{
  "convo": chat.bsky.convo.defs#convoView,
  "addedMembers": [profileViewBasic, ...]  // The members successfully added
}
```

**Errors:** `AccountSuspended`, `BlockedActor`, `BlockedSubject`, `ConvoLocked`, `InsufficientRole`, `InvalidConvo`, `MemberLimitReached`, `NotFollowedBySender`, `RecipientNotFound`, `UserForbidsGroups`

### `chat.bsky.group.removeMembers` (procedure)

Removes members from a group (deletes membership, doesn't just set status).

**Input:**
```json
{
  "convoId": "string",
  "members": ["did:plc:member1", ...]  // At least 1 DID
}
```

**Response:**
```json
{
  "convo": chat.bsky.convo.defs#convoView
}
```

**Errors:** `InvalidConvo`, `InsufficientRole` (only owner can remove)

### `chat.bsky.convo.leaveConvo` (procedure)

Voluntarily leaves a conversation.

**Input:** `{ "convoId": "string" }`

**Response:** `{ "convoId": "string", "rev": "string" }`

**Error:** `OwnerCannotLeave` — The owner cannot leave without first locking the group.

**Behavior:**
- For direct convos, membership is never fully deleted, only removed from enumerations
- For group convos, membership is deleted
- The removed member gets a `logLeaveConvo` event
- Other members get a `logMemberLeave` or `logRemoveMember` event

### `chat.bsky.convo.getConvoMembers` (query)

Lists all members of a conversation (paginated).

**Parameters:** `convoId` (required), `limit` (1-100, default 50), `cursor`

**Response:**
```json
{
  "cursor": "optional",
  "members": [profileViewBasic, ...]
}
```

Members include their role and membership type:
- `groupConvoMember`: Has `role` ("owner" or "standard") and optional `addedBy`
- `pastGroupConvoMember`: No role data (past member)
- `directConvoMember`: No extra data (1-1 conversation)

## Member Roles

Defined in `chat.bsky.actor.defs#memberRole`:
- `"owner"`: Group creator, can add/remove members, lock/unlock, edit group, manage join links
- `"standard"`: Regular member with limited permissions

## Editing Groups

### `chat.bsky.group.editGroup` (procedure)

Updates group name/settings.

**Input:**
```json
{
  "convoId": "string",
  "name": "New Group Name"  // Min 1, max 128 graphemes / 1280 chars
}
```

**Response:** `{ "convo": convoView }`

**Errors:** `ConvoLocked`, `InvalidConvo`, `InsufficientRole`

A `systemMessageDataEditGroup` system message is generated in the convo.

## Group Locking

Group convos can be locked to prevent new messages and reactions.

**Lock status values** (`convoLockStatus`):
- `"unlocked"`: Normal operation
- `"locked"`: No new content; owner can unlock
- `"locked-permanently"`: Permanently locked; cannot be unlocked

### `chat.bsky.convo.lockConvo` (procedure)
Locks a group. **Errors:** `ConvoLocked`, `InvalidConvo`, `InsufficientRole`

### `chat.bsky.convo.unlockConvo` (procedure)
Unlocks a group. **Errors:** `InvalidConvo`, `InsufficientRole`, `ConvoLockedByModeration`

### `chat.bsky.group.listMutualGroups` (query)

Lists groups that both the requester and a specified actor are members of.

**Parameters:**
- `subject` (required DID)
- `limit`, `cursor`

**Response:** `{ "cursor", "convos": [convoView, ...] }`

## Join Links

Groups can have invite links that allow people to join without being directly added.

### Join Link Properties (`joinLinkView`):
```json
{
  "code": "string",              // Unique code for the link
  "enabledStatus": "enabled" | "disabled",
  "requireApproval": false,      // If true, owner must approve join requests
  "joinRule": "anyone" | "followedByOwner",
  "createdAt": "2024-01-01T00:00:00Z"
}
```

- `requireApproval`: When `true`, requesting to join creates a pending request; when `false`, the user joins immediately
- `joinRule`: `"anyone"` (open to all) or `"followedByOwner"` (only those followed by owner)

### Join Link Management

| Endpoint | Action |
|----------|--------|
| `chat.bsky.group.createJoinLink` | Create a join link |
| `chat.bsky.group.editJoinLink` | Edit requireApproval/joinRule |
| `chat.bsky.group.enableJoinLink` | Re-enable a disabled link |
| `chat.bsky.group.disableJoinLink` | Disable a link |
| `chat.bsky.group.getJoinLinkPreviews` | Get public group info from codes (up to 50 at once) |

### `createJoinLink` Input:
```json
{
  "convoId": "string",
  "requireApproval": false,
  "joinRule": "anyone"
}
```
**Errors:** `EnabledJoinLinkAlreadyExists`, `InvalidConvo`, `InsufficientRole`

### `editJoinLink` Input:
```json
{
  "convoId": "string",
  "requireApproval": true|false,
  "joinRule": "anyone" | "followedByOwner"
}
```

### `getJoinLinkPreviews` Input/Output:
```json
// Input:
{ "codes": ["code1", "code2", ...] }  // 1-50 codes

// Response:
{
  "joinLinkPreviews": [
    joinLinkPreviewView | disabledJoinLinkPreviewView | invalidJoinLinkPreviewView
  ]
}
```

The output array matches the input codes **one-to-one by position**.

### `joinLinkPreviewView`:
An unauthenticated/authenticated preview of a group from a join link:
```json
{
  "convoId": "string",
  "code": "string",
  "name": "Group Name",
  "owner": profileViewBasic,
  "memberCount": 42,
  "memberLimit": 50,
  "requireApproval": false,
  "joinRule": "anyone",
  "convo": convoView,         // Only if viewer is authenticated and a member
  "viewer": { "requestedAt": "..." }  // Only if viewer has a pending request
}
```

### Requesting to Join via Join Link:
```json
// chat.bsky.group.requestJoin
{ "code": "join-link-code" }

// Response:
{
  "status": "joined" | "pending",
  "convo": convoView  // Only present when status = "joined"
}
```

**Errors:** `ConvoLocked`, `FollowRequired` (joinRule is followedByOwner but user doesn't follow), `InvalidCode`, `LinkDisabled`, `MemberLimitReached`, `UserKicked`

### Join Request Management (Owner):

**`listJoinRequests`:** Lists pending requests for a group the user owns
```json
// Parameters: { "convoId", "limit", "cursor" }
// Response:
{
  "cursor": "...",
  "requests": [
    {
      "convoId": "string",
      "requestedBy": profileViewBasic,
      "requestedAt": "datetime"
    }
  ]
}
```

**`approveJoinRequest`:** `{ "convoId", "member": "did:plc:..." }` → `{ "convo": convoView }`
**`rejectJoinRequest`:** `{ "convoId", "member": "did:plc:..." }` → `{}`
**`updateJoinRequestsRead`:** `{ "convoId" }` → `{}`

## Group Convo View (within convoView.kind)

When `convoView.kind` has `$type: "chat.bsky.convo.defs#groupConvo"`, it includes:
```json
{
  "createdAt": "datetime",
  "name": "Group Name",
  "memberCount": 42,
  "memberLimit": 50,
  "lockStatus": "unlocked" | "locked" | "locked-permanently",
  "lockStatusModerationOverride": false,
  "joinLink": joinLinkView,     // Optional
  "joinRequestCount": 5,        // Owner only, capped at 21
  "unreadJoinRequestCount": 2   // Owner only
}
```

## Embedding Join Links in Messages

Messages can embed a join link using `chat.bsky.embed.joinLink`:

```json
{
  "$type": "chat.bsky.embed.joinLink",
  "code": "the-join-link-code"
}
```

When rendered (in `messageView.embed`), it becomes a `chat.bsky.embed.joinLink#view` containing a `joinLinkPreviewView`.

## Group Chat Limitations

- **New accounts** cannot create groups (`NewAccountCannotCreateGroup` error)
- **Member limit** is returned by `getStatus` (typically 50)
- **Owner cannot leave** a group without first locking it
- **Locking** prevents all new content (messages, reactions)
- **Permanent locking** is irreversible
