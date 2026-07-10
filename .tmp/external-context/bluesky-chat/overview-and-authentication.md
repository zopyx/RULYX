---
source: Bluesky AT Protocol Lexicons (github.com/bluesky-social/atproto)
library: Bluesky Social
package: chat.bsky
topic: Overview, Authentication, and Architecture
fetched: 2026-06-12T18:30:00Z
official_docs: https://github.com/bluesky-social/atproto/tree/main/lexicons/chat/bsky
---

# Bluesky Chat API — Overview & Architecture

## Namespace & Base Path

The Bluesky Chat API lives under the **`chat.bsky.*`** lexicon namespace (NOT `com.atproto.chat.*`). All endpoint paths follow the standard AT Protocol XRPC convention:

```
https://{PDS_HOST}/xrpc/chat.bsky.{namespace}.{action}
```

**Lexicon structure:**
```
chat/bsky/
├── actor/           # Chat actor declarations, status, account management
│   ├── declaration.json    # Per-user chat preferences (record)
│   ├── defs.json           # Profile views, member roles, convo member types
│   ├── deleteAccount.json  # Delete chat account data
│   ├── exportAccountData.json  # Export all chat data
│   └── getStatus.json      # Get viewer's chat status
├── convo/           # Core conversation operations
│   ├── defs.json           # Message types, convo views, log event types
│   ├── listConvos.json     # List user's conversations
│   ├── listConvoRequests.json  # List incoming chat requests
│   ├── getConvo.json       # Get single conversation
│   ├── getConvoForMembers.json  # Get/create 1-1 convo for members
│   ├── getConvoMembers.json     # List convo members (paginated)
│   ├── getMessages.json    # Get messages in a convo
│   ├── sendMessage.json    # Send a message
│   ├── sendMessageBatch.json   # Send batch of messages
│   ├── acceptConvo.json    # Accept a conversation request
│   ├── leaveConvo.json     # Leave a conversation
│   ├── deleteMessageForSelf.json  # Soft-delete a message
│   ├── addReaction.json    # Add emoji reaction
│   ├── removeReaction.json # Remove emoji reaction
│   ├── getLog.json         # Subscribe to real-time events (polling)
│   ├── updateRead.json     # Mark convo read (specific message)
│   ├── updateAllRead.json  # Mark all convos read
│   ├── getUnreadCounts.json    # Get unread counts
│   ├── getConvoAvailability.json  # Check if chat available with members
│   ├── muteConvo.json      # Mute a conversation
│   └── unmuteConvo.json    # Unmute a conversation
│   ├── lockConvo.json      # Lock a group convo (prevents messages)
│   └── unlockConvo.json    # Unlock a group convo
├── group/           # Group chat operations
│   ├── defs.json           # Join link types, join request views
│   ├── createGroup.json    # Create a group conversation
│   ├── addMembers.json     # Add members to group
│   ├── removeMembers.json  # Remove members from group
│   ├── editGroup.json      # Edit group name
│   ├── listMutualGroups.json   # List groups both user and another share
│   ├── createJoinLink.json # Create a group invite link
│   ├── editJoinLink.json   # Edit join link settings
│   ├── enableJoinLink.json # Re-enable a join link
│   ├── disableJoinLink.json    # Disable a join link
│   ├── getJoinLinkPreviews.json  # Preview groups from join links
│   ├── requestJoin.json    # Request to join via link
│   ├── withdrawJoinRequest.json  # Withdraw join request
│   ├── listJoinRequests.json    # List join requests (owner view)
│   ├── approveJoinRequest.json  # Approve a join request
│   ├── rejectJoinRequest.json   # Reject a join request
│   └── updateJoinRequestsRead.json  # Mark join requests read
├── embed/           # Chat-specific embed types
│   └── joinLink.json       # Embed a join link in a message
├── moderation/      # Moderation-specific views (admin tools)
│   ├── defs.json           # Moderation convo views
│   ├── getActorMetadata.json   # Chat usage metadata for actor
│   ├── getConvo.json       # Get convo as moderator
│   ├── getConvoMembers.json    # Get convo members as moderator
│   ├── getConvos.json      # Get multiple convos as moderator
│   ├── getMessageContext.json  # Get message context
│   ├── subscribeModEvents.json # WebSocket subscription for mod events
│   └── updateActorAccess.json  # Enable/disable chat for actor
└── authFullChatClient.json    # Permission set definition
```

## Authentication

The Bluesky Chat API uses **standard AT Protocol authentication** — the same session/Access JWT used for `com.atproto.*` and `app.bsky.*` endpoints.

**Auth mechanism:**
- All chat endpoints require authentication (`Authorization: Bearer {accessJwt}`)
- The `chat.bsky.authFullChatClient` lexicon defines a permission set that scopes which RPC methods a chat client can call
- The permission set grants access to all `chat.bsky.convo.*`, `chat.bsky.group.*`, and `chat.bsky.actor.*` RPCs + `chat.bsky.actor.declaration` CRUD

## User Chat Declaration (Preferences)

Each user has a **declaration record** at `chat.bsky.actor.declaration` that controls who can DM them:

```json
{
  "lexicon": 1,
  "id": "chat.bsky.actor.declaration",
  "type": "record",
  "key": "literal:self",
  "record": {
    "allowIncoming": "all" | "none" | "following",
    "allowGroupInvites": "all" | "none" | "following"
  }
}
```

- `allowIncoming`: Controls who can start 1-1 conversations with the user
  - `"all"`: Anyone can message
  - `"none"`: No one can message
  - `"following"`: Only users the user follows can message
- `allowGroupInvites` (unstable/experimental): Controls group chat invites
  - Same value set: `"all"`, `"none"`, `"following"`

This record lives at the AT URI: `at://{did}/chat.bsky.actor.declaration/self`

## Actor Status

The `chat.bsky.actor.getStatus` endpoint returns the authenticated viewer's chat status:

```json
{
  "chatDisabled": false,           // True if viewer's account cannot participate
  "canCreateGroups": true,         // New accounts restricted from creating groups
  "groupMemberLimit": 50           // Max group members allowed
}
```

## Real-time Updates: Polling (WebSocket-like via getLog)

The chat API uses a **polling-based approach** called `chat.bsky.convo.getLog` rather than a standard WebSocket. The client periodically polls this endpoint to receive a stream of log events.

**`chat.bsky.convo.getLog`** (query):
- `cursor` (string, optional): Last known event cursor for backfill
- Returns:
  - `cursor`: New cursor for next poll
  - `logs[]`: Array of typed log events, each with `rev`, `convoId`, and event-specific data

**Log event types:**

| Event | Description |
|-------|-------------|
| `logBeginConvo` | Convo containing viewer was started (direct or group) |
| `logAcceptConvo` | Viewer accepted a convo |
| `logLeaveConvo` | Viewer left a convo |
| `logMuteConvo` | Viewer muted a convo |
| `logUnmuteConvo` | Viewer unmuted a convo |
| `logCreateMessage` | User-originated message created (not system messages) |
| `logDeleteMessage` | User-originated message deleted |
| `logAddReaction` | Reaction added to message |
| `logRemoveReaction` | Reaction removed from message |
| `logReadConvo` | Convo marked read (replaces deprecated `logReadMessage`) |
| `logAddMember` | Member added to group (the added member also gets `logBeginConvo`) |
| `logRemoveMember` | Member removed from group |
| `logMemberJoin` | Member joined group via join link (no approval needed) |
| `logMemberLeave` | Member voluntarily left group |
| `logLockConvo` | Group convo was locked |
| `logUnlockConvo` | Group convo was unlocked |
| `logLockConvoPermanently` | Group convo locked permanently |
| `logEditGroup` | Group info was edited |
| `logCreateJoinLink` | Join link created |
| `logEditJoinLink` | Join link settings edited |
| `logEnableJoinLink` | Join link enabled |
| `logDisableJoinLink` | Join link disabled |
| `logIncomingJoinRequest` | Someone requested to join a group the viewer owns |
| `logApproveJoinRequest` | Viewer approved a join request |
| `logRejectJoinRequest` | Viewer rejected a join request |
| `logOutgoingJoinRequest` | Viewer sent a join request |
| `logWithdrawIncomingJoinRequest` | Prospective member withdrew join request (owner sees) |
| `logWithdrawOutgoingJoinRequest` | Viewer withdrew their own join request |
| `logReadJoinRequests` | Owner marked join requests as read |

**Polling strategy:** Clients poll `chat.bsky.convo.getLog` periodically (e.g., every few seconds) with the last known cursor to get new events.

## Convo Status (Request vs Accepted)

Conversations have a **per-member** status:
- `"request"`: The conversation is in the member's request inbox (not yet accepted)
- `"accepted"`: The member has accepted the conversation

This is stored in `convoView.status`, which reflects the viewer's own membership status.

## Convo Kind (Direct vs Group)

Conversations can be:
- `"direct"`: 1-1 conversations (immutable 2-member list)
- `"group"`: Multi-member conversations

## Message Types

Three types of messages can appear in a conversation:

1. **`messageView`**: A regular user message with:
   - `id`, `rev`, `text` (max 1000 graphemes/10000 chars)
   - `facets` (optional): Rich text annotations (mentions, URLs, etc.)
   - `embed` (optional): Either `app.bsky.embed.record` (a post record) or `chat.bsky.embed.joinLink`
   - `reactions[]`: Array of `reactionView` objects
   - `sender`: `{ did: string }`
   - `sentAt`: ISO datetime

2. **`deletedMessageView`**: A deleted message placeholder with `id`, `rev`, `sender`, `sentAt` (no text)

3. **`systemMessageView`** (unstable): System-generated messages for group events:
   - `systemMessageDataAddMember`, `systemMessageDataRemoveMember`
   - `systemMessageDataMemberJoin`, `systemMessageDataMemberLeave`
   - `systemMessageDataLockConvo`, `systemMessageDataUnlockConvo`, `systemMessageDataLockConvoPermanently`
   - `systemMessageDataEditGroup`
   - `systemMessageDataCreateJoinLink`, `systemMessageDataEditJoinLink`, etc.

## Message Reactions

Messages support emoji reactions:
- `addReaction`: Add a single-emoji reaction (idempotent)
- `removeReaction`: Remove a single-emoji reaction (idempotent)
- Reactions have `value` (the emoji string, max 1 grapheme), `sender.did`, `createdAt`
- Constraint: `maxLength 64, maxGraphemes 1, minGraphemes 1` — exactly one emoji
- Errors: `ReactionNotAllowed`, `ReactionMessageDeleted`, `ReactionLimitReached`, `ReactionInvalidValue`

## Convo View Structure

```json
{
  "id": "string",
  "rev": "string",
  "members": [{"did": "...", "handle": "...", ...}],  // Sample members (not full list for groups)
  "lastMessage": messageView | deletedMessageView | systemMessageView,
  "lastReaction": messageAndReactionView,
  "muted": false,
  "status": "request" | "accepted",
  "unreadCount": 0,
  "kind": directConvo | groupConvo
}
```

For groups, `kind` includes additional fields:
- `createdAt`, `name`, `memberCount`, `memberLimit`, `lockStatus`, `lockStatusModerationOverride`
- `joinLink` (optional): Join link view
- `joinRequestCount`, `unreadJoinRequestCount` (owner only)
