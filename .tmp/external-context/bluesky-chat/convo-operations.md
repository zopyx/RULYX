---
source: Bluesky AT Protocol Lexicons (github.com/bluesky-social/atproto)
library: Bluesky Social
package: chat.bsky
topic: Core Conversation Operations (sending, listing, reading)
fetched: 2026-06-12T18:30:00Z
official_docs: https://github.com/bluesky-social/atproto/tree/main/lexicons/chat/bsky
---

# Bluesky Chat — Core Conversation Operations

## Listing Conversations

### `chat.bsky.convo.listConvos` (query)

Returns a page of conversations for the user, with rich filter support.

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `limit` | integer (1-100, default 50) | Page size |
| `cursor` | string | Pagination cursor |
| `readState` | `"unread"` | Filter to only unread convos |
| `status` | `"request"` \| `"accepted"` | Filter by convo status (use `listConvoRequests` for requests) |
| `kind` | `"direct"` \| `"group"` | Filter by conversation type |
| `lockStatus` | `"unlocked"` \| `"locked"` \| `"locked-permanently"` | Filter by lock status |

**Response:**
```json
{
  "cursor": "string",
  "convos": [convoView, ...]
}
```

## Getting a Single Conversation

### `chat.bsky.convo.getConvo` (query)

**Parameters:** `convoId` (required, string)

**Response:**
```json
{
  "convo": convoView
}
```

## Getting/Creating a 1-1 Conversation

### `chat.bsky.convo.getConvoForMembers` (query)

Gets or creates a direct (non-group) conversation for the given members. **Idempotent** — always returns the same conversation for a given member set.

**Parameters:**
```json
{
  "members": ["did:plc:user1"]   // 1-10 DIDs
}
```

**Note:** Despite allowing up to 10 DIDs, the description says this always returns a **direct (non-group)** conversation. For group conversations, use `createGroup`.

**Errors:**
- `AccountSuspended`
- `BlockedActor` / `BlockedSubject`
- `MessagesDisabled`
- `NotFollowedBySender`
- `RecipientNotFound`

### `chat.bsky.convo.getConvoAvailability` (query)

Checks whether a 1-1 chat can be started with the given members. Does **not** create a conversation.

**Parameters:** `{ "members": ["did:plc:..."] }` (1-10 DIDs)

**Response:**
```json
{
  "canChat": true|false,
  "convo": convoView  // Present if convo already exists
}
```

## Messages

### `chat.bsky.convo.getMessages` (query)

Returns a page of messages from a conversation.

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `convoId` | string (required) | The conversation ID |
| `limit` | integer (1-100, default 50) | Page size |
| `cursor` | string | Pagination cursor (for older messages) |

**Response:**
```json
{
  "cursor": "string",
  "messages": [
    messageView | deletedMessageView | systemMessageView, ...
  ],
  "relatedProfiles": [profileViewBasic, ...]
  // All members who authored or reacted to messages + system message referents
}
```

**Pagination:** The cursor points backward. To get the full history, paginate from the most recent message backward.

### `chat.bsky.convo.sendMessage` (procedure)

Sends a message to a conversation.

**Input:**
```json
{
  "convoId": "string",
  "message": {
    "text": "Hello world!",    // Max 1000 graphemes / 10000 chars
    "facets": [...],           // Optional: rich text facets (app.bsky.richtext.facet)
    "embed": {                 // Optional: one of:
      "$type": "app.bsky.embed.record",
      "record": "..."
    } | {
      "$type": "chat.bsky.embed.joinLink",
      "code": "join-link-code"
    }
  }
}
```

**Response:** `messageView` (the created message)

**Errors:** `ConvoLocked`, `InvalidConvo`

### `chat.bsky.convo.sendMessageBatch` (procedure)

Sends a batch of messages (max 100 items) to one or more conversations.

**Input:**
```json
{
  "items": [
    {
      "convoId": "string",
      "message": messageInput
    },
    ...
  ]
}
```

**Response:**
```json
{
  "items": [messageView, ...]
}
```

### `chat.bsky.convo.deleteMessageForSelf` (procedure)

Soft-deletes a message for the viewer only. Other participants can still see it.

**Input:**
```json
{
  "convoId": "string",
  "messageId": "string"
}
```

**Response:** `deletedMessageView`

**Errors:** `InvalidConvo`, `MessageDeleteNotAllowed` (can't delete system messages)

## Read State

### `chat.bsky.convo.updateRead` (procedure)

Marks a conversation as read.

**Input:**
```json
{
  "convoId": "string",        // Required
  "messageId": "string"       // Optional: last read message
}
```

**Response:** `{ "convo": convoView }`

### `chat.bsky.convo.updateAllRead` (procedure)

Marks all conversations as read, optionally filtered by status.

**Input:**
```json
{
  "status": "request" | "accepted"  // Optional: filter which convos to mark read
}
```

**Response:**
```json
{
  "updatedCount": 7
}
```

## Unread Counts

### `chat.bsky.convo.getUnreadCounts` (query)

Returns unread conversation counts (see "chat-requests.md" for full details).

## Muting

### `chat.bsky.convo.muteConvo` (procedure)

Mutes a conversation, preventing notifications.

**Input:** `{ "convoId": "string" }`

**Response:** `{ "convo": convoView }`

### `chat.bsky.convo.unmuteConvo` (procedure)

Unmutes a conversation, allowing notifications.

**Input:** `{ "convoId": "string" }`

**Response:** `{ "convo": convoView }`

## Reactions

### `chat.bsky.convo.addReaction` (procedure)

Adds an emoji reaction to a message. **Idempotent** — multiple calls with the same emoji result in a single reaction.

**Input:**
```json
{
  "convoId": "string",
  "messageId": "string",
  "value": "❤️"  // Exactly 1 emoji grapheme, max 64 bytes
}
```

**Response:** `{ "message": messageView }` (message with updated reactions)

**Errors:** `ReactionNotAllowed`, `ReactionMessageDeleted`, `ReactionLimitReached`, `ReactionInvalidValue`

### `chat.bsky.convo.removeReaction` (procedure)

Removes an emoji reaction. **Idempotent.**

**Input:** Same as `addReaction`

**Response:** `{ "message": messageView }`

## Key Data Types

### `messageView`
```json
{
  "id": "string",
  "rev": "string",
  "text": "string",           // Max 10000 chars / 1000 graphemes
  "facets": [facet, ...],     // Optional rich text facets
  "embed": { ... },           // Optional embed
  "reactions": [reactionView, ...],  // In ascending creation order
  "sender": { "did": "did:plc:..." },
  "sentAt": "2024-01-01T00:00:00Z"
}
```

### `deletedMessageView`
```json
{
  "id": "string",
  "rev": "string",
  "sender": { "did": "..." },
  "sentAt": "datetime"
}
```

### `reactionView`
```json
{
  "value": "❤️",
  "sender": { "did": "..." },
  "createdAt": "datetime"
}
```

### `messageInput`
```json
{
  "text": "string",            // Max 10000 chars / 1000 graphemes
  "facets": [facet, ...],      // Optional
  "embed": record_embed | join_link_embed  // Optional
}
```

### `messageViewSender`
```json
{
  "did": "did:plc:..."
}
```

### `convoView`
```json
{
  "id": "string",
  "rev": "string",
  "members": [profileViewBasic, ...],  // Sample members (not full list for groups)
  "lastMessage": messageView | deletedMessageView | systemMessageView,
  "lastReaction": messageAndReactionView,
  "muted": false,
  "status": "request" | "accepted",
  "unreadCount": 0,
  "kind": directConvo | groupConvo
}
```

## Real-time Log Events (getLog)

See "overview-and-authentication.md" for the full list of 30 log event types.

The polling pattern is:
1. Call `chat.bsky.convo.getLog` without cursor to get initial events
2. Use the returned `cursor` in subsequent calls
3. Each call returns only new events since the cursor

## Moderation Endpoints

For moderation/admin tooling (requires moderator privileges):

| Endpoint | Description |
|----------|-------------|
| `chat.bsky.moderation.getConvo` | Get convo as moderator (no viewer-specific data) |
| `chat.bsky.moderation.getConvos` | Get multiple convos by IDs |
| `chat.bsky.moderation.getConvoMembers` | List members as moderator |
| `chat.bsky.moderation.getMessageContext` | Get messages surrounding a target message |
| `chat.bsky.moderation.getActorMetadata` | Get actor's chat usage stats (day/month/all) |
| `chat.bsky.moderation.updateActorAccess` | Enable/disable chat for an actor |
| `chat.bsky.moderation.subscribeModEvents` | WebSocket subscription for moderation events |

### Moderation Subscription Events

`chat.bsky.moderation.subscribeModEvents` is a **WebSocket subscription** endpoint (private) that streams chat moderation events including:
- `eventConvoFirstMessage` — First message sent on a convo
- `eventGroupChatCreated` — Group was created
- `eventGroupChatMemberAdded` — Member added to group (starts in request state)
- `eventGroupChatMemberJoined` — Member joined via link (no approval)
- `eventGroupChatJoinRequest` — User requested to join via link
- `eventGroupChatJoinRequestApproved` — Owner approved a join request
- `eventGroupChatJoinRequestRejected` — Owner rejected a join request
- `eventChatAccepted` — User accepted a convo (explicit or via message)
- `eventGroupChatMemberLeft` — Member left/was removed
- `eventGroupChatUpdated` — Group metadata changed (name, lock, join link)
- `eventRateLimitExceeded` — User hit rate limit
