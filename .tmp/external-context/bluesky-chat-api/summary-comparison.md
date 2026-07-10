---
source: AT Protocol Lexicon Schemas (GitHub) + docs.bsky.app
library: Bluesky
package: chat.bsky.*
topic: Summary & Comparison — Chat Requests vs Regular Convos
fetched: 2026-06-12T14:00:00Z
official_docs: https://docs.bsky.app/docs/category/http-reference
---

# Bluesky Chat API — Summary & Key Comparisons

## Chat Requests vs Regular Conversations

| Aspect | Request (Pending) | Accepted (Active) |
|--------|-------------------|-------------------|
| **Status value** | `"request"` | `"accepted"` |
| **Visibility** | Separate "requests" inbox (via `listConvoRequests` or `listConvos(status:"request")`) | Main inbox (`listConvos` default) |
| **Messaging** | Messages can be sent/received | Messages can be sent/received |
| **Notification** | Triggers unread count in `unreadRequestConvos` | Triggers unread count in `unreadAcceptedConvos` |
| **Accept action** | `acceptConvo` moves to accepted | N/A |
| **User control** | Recipient can accept, ignore, or block | User can leave, mute, or lock (groups) |
| **When created** | When someone DMs you who you don't follow, or when added to a group | After `acceptConvo` is called |
| **Group context** | Members added to a group are "request" by default | Owner is always "accepted" |

## Direct (1-1) vs Group Conversations

| Aspect | Direct (1-1) | Group |
|--------|-------------|-------|
| **Kind value** | `"direct"` | `"group"` |
| **Member count** | Always exactly 2 | 2+ (up to 50 members + creator = 50 total) |
| **Member list** | Immutable (fixed 2 members) | Mutable (add/remove members) |
| **Creation** | `getConvoForMembers` (idempotent, always returns same convo) | `createGroup` (non-idempotent, creates new convo each time) |
| **Name** | No name (not applicable) | Named (max 50 graphemes, editable via `editGroup`) |
| **Leaving** | Can leave (hides from enumeration only) | Can leave, but owner must lock first |
| **Lock/unlock** | Not applicable | Lock/unlock by owner |
| **Join links** | Not applicable | Available (with approval/rule config) |
| **System messages** | None | Various system message types for events |

## Message Types Comparison

| Type | Has text | Has reactions | Can be reacted to | Can be deleted | Sender info |
|------|----------|--------------|-------------------|---------------|-------------|
| `messageView` (user) | Yes | Yes | Yes | Yes (self only) | Full sender |
| `deletedMessageView` | No | No | No | N/A | Sender only |
| `systemMessageView` | No | No | **No** (`ReactionNotAllowed`) | **No** (`MessageDeleteNotAllowed`) | Via data field |

## Endpoint Categories by Function

### Read Operations
- `getConvo` — Get single convo
- `getConvoForMembers` — Get/create 1-1 convo
- `getConvoAvailability` — Check if chat is possible
- `getConvoMembers` — List all members
- `getMessages` — Get messages (paginated)
- `getLog` — Get event log
- `getUnreadCounts` — Get unread counts
- `listConvos` — List conversations
- `listConvoRequests` — List requests
- `getJoinLinkPreviews` — Preview join links

### Write Operations (Messages)
- `sendMessage` — Send a message
- `sendMessageBatch` — Send batch messages
- `addReaction` — React to a message
- `removeReaction` — Remove reaction
- `deleteMessageForSelf` — Soft-delete message

### Write Operations (Conversations)
- `acceptConvo` — Accept conversation request
- `leaveConvo` — Leave conversation
- `muteConvo` / `unmuteConvo` — Toggle mute
- `updateRead` — Update read state
- `updateAllRead` — Mark all as read
- `lockConvo` / `unlockConvo` — Toggle lock (group)

### Group Management
- `createGroup` — Create group
- `addMembers` / `removeMembers` — Member management
- `editGroup` — Edit group name
- `createJoinLink` / `editJoinLink` / `enableJoinLink` / `disableJoinLink` — Join link management
- `requestJoin` / `withdrawJoinRequest` — Join requests (user side)
- `approveJoinRequest` / `rejectJoinRequest` / `listJoinRequests` / `updateJoinRequestsRead` — Join requests (owner side)
- `listMutualGroups` — Mutual group discovery

### Moderation
- `getActorMetadata` — Chat activity stats
- `getMessageContext` — Message context for review
- `updateActorAccess` — Allow/block chat access

### Account
- `deleteAccount` — Delete chat data
- `exportAccountData` — Export chat data

## Key URLs

- **Official API docs**: https://docs.bsky.app/docs/category/http-reference
- **AT Protocol Lexicons (GitHub)**: https://github.com/bluesky-social/atproto/tree/main/lexicons/chat/bsky
- **Chat service host**: https://api.bsky.chat
- **Chat service DID**: `did:web:api.bsky.chat#bsky_chat`
- **API Auth guide**: https://docs.bsky.app/docs/advanced-guides/api-directory
- **Service Auth guide**: https://docs.bsky.app/docs/advanced-guides/service-auth
