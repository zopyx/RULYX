---
source: Bluesky AT Protocol Lexicons (github.com/bluesky-social/atproto)
library: Bluesky Social
package: chat.bsky
topic: Chat Requests (listing, accepting, declining)
fetched: 2026-06-12T18:30:00Z
official_docs: https://github.com/bluesky-social/atproto/tree/main/lexicons/chat/bsky
---

# Bluesky Chat Requests System

## Overview

The Bluesky chat system has a **dual-inbox model** for conversations:

1. **Accepted conversations**: Normal conversations the user has accepted (returned by `listConvos` with `status: "accepted"`)
2. **Request conversations**: Conversations from non-accepted contacts that sit in a "request inbox" (returned by `listConvoRequests`)

This applies to both **direct (1-1) chats** and **group chats**. When someone adds you to a group, it initially appears as a request.

## Request Flow

When a user sends you a first message:
1. The conversation is created with your membership in **`"request"`** status
2. It appears in `listConvoRequests`
3. You can either **accept** it (moves to accepted convos) or **ignore** it
4. If you respond to the message, it **automatically accepts** the conversation

The same applies to group invites: when you're added to a group, your membership starts as `"request"` and you must accept it.

## Listing Chat Requests

### `chat.bsky.convo.listConvoRequests` (query)

Returns incoming conversation requests for the user.

**Parameters:**
- `limit` (integer, 1-100, default 50): Page size
- `cursor` (string, optional): Pagination cursor

**Response:**
```json
{
  "cursor": "optional-cursor-string",
  "requests": [
    // Two types of items can appear here:
    chat.bsky.convo.defs#convoView,        // Direct convo requests
    chat.bsky.group.defs#joinRequestConvoView  // Group join requests (made by user)
  ]
}
```

**The response contains two types of items:**
1. **`convoView`**: Direct message conversation requests (someone messaged you)
2. **`joinRequestConvoView`**: Group join requests you've submitted to groups you're not yet a member of

This is the **preferred** way to get request convos — the `listConvos` endpoint also supports `status: "request"` but documentation recommends using `listConvoRequests` instead (which also includes group join requests).

### `chat.bsky.convo.listConvos` (query) — with `status` filter

Can also list request convos via:

**Parameters (relevant):**
- `status`: `"request"` or `"accepted"` — **Note:** It is "discouraged" to use `status: "request"` here; prefer `listConvoRequests`
- `readState`: `"unread"` — Filter to only unread convos
- `kind`: `"direct"` or `"group"` — Filter by conversation type
- `lockStatus`: `"unlocked"`, `"locked"`, or `"locked-permanently"`

## Accepting Chat Requests

### `chat.bsky.convo.acceptConvo` (procedure)

Accepts a conversation request, moving it from requests to accepted convos.

**Input:**
```json
{
  "convoId": "string"
}
```

**Response:**
```json
{
  "rev": "string"   // Rev when the convo was accepted
  // If not present, the convo was already accepted
}
```

**Error:** `InvalidConvo`

**Behavior:**
- Marks the conversation as accepted for the viewer
- The conversation moves from `listConvoRequests` to `listConvos` with `status: "accepted"`
- Also triggers a `logAcceptConvo` event in `getLog`

## Automatic Acceptance via Replying

If you send a message to a request conversation via `sendMessage`, the conversation is automatically accepted. The moderation subscription endpoint `subscribeModEvents` captures this with `eventChatAccepted` where `method` is either `"explicit"` (via `acceptConvo`) or `"message"` (via sending a message).

## Differences Between Request and Accepted Conversations

| Aspect | Request | Accepted |
|--------|---------|----------|
| Listed in | `listConvoRequests` | `listConvos` (with `status: "accepted"`) |
| Notifications | May be suppressed | Normal notifications |
| `convoView.status` | `"request"` | `"accepted"` |
| Can send messages | Yes (auto-accepts) | Yes |
| Can be muted | Yes | Yes |
| unreadCount tracking | Yes | Yes |

## Group Join Requests

Group join requests (via join links) are a separate mechanism:

### Requesting to Join (from the prospective member)
- `chat.bsky.group.requestJoin`: Send a request to join via a group's join link code
- `chat.bsky.group.withdrawJoinRequest`: Withdraw a pending join request

### Managing Requests (from the group owner)
- `chat.bsky.group.listJoinRequests`: List all pending requests to join your group
- `chat.bsky.group.approveJoinRequest`: Approve a join request
- `chat.bsky.group.rejectJoinRequest`: Reject a join request
- `chat.bsky.group.updateJoinRequestsRead`: Mark join requests as read

### Viewing Your Own Pending Requests
The `listConvoRequests` endpoint returns `joinRequestConvoView` items that represent your pending group join requests. Each includes:
```json
{
  "convoId": "string",
  "name": "Group Name",
  "owner": profileViewBasic,  // Group owner
  "memberCount": 42,
  "memberLimit": 50,
  "viewer": {
    "requestedAt": "2024-01-01T00:00:00Z"
  }
}
```

## Unread Counts

### `chat.bsky.convo.getUnreadCounts` (query)

Returns unread counts split by convo status:

**Parameters:**
- `includeGroupChats` (boolean, default true): When false, excludes group convos

**Response:**
```json
{
  "unreadAcceptedConvos": 3,  // Capped at 31 (31 = 30+)
  "unreadRequestConvos": 1    // Capped at 11 (11 = 10+)
}
```

**Counting rules:**
- Counts only **unlocked**, **not muted** conversations
- Direct convos are excluded when there's a block relationship
- Group convos count unread join requests too
- `unreadRequestConvos` counts only unread messages, not join requests (since the owner would have accepted the group already)
