---
source: AT Protocol Lexicon Schemas (GitHub) + docs.bsky.app
library: Bluesky
package: chat.bsky.*
topic: Endpoints Overview
fetched: 2026-06-12T14:00:00Z
official_docs: https://docs.bsky.app/docs/category/http-reference
---

# Bluesky Chat API (chat.bsky.*) — Complete Endpoint Reference

## Architecture

The Bluesky Chat/DM system is a **centralized** service run by Bluesky, separate from the federated AT Protocol. All `chat.bsky.*` requests are:
1. **Authenticated** (require user auth session)
2. **Directed to the user's PDS instance**
3. **Proxied** to the central chat service via the `atproto-proxy` header pointing to service DID `did:web:api.bsky.chat`
4. The centralized chat service host is `https://api.bsky.chat`

## Complete Endpoint Inventory

### Namespace: `chat.bsky.convo.*` — Conversations & Messages

| # | Endpoint | Method | XRPC Path | Description |
|---|----------|--------|-----------|-------------|
| 1 | `acceptConvo` | POST | `/xrpc/chat.bsky.convo.acceptConvo` | Accept a conversation request → moves from "request" to "accepted" status |
| 2 | `addReaction` | POST | `/xrpc/chat.bsky.convo.addReaction` | Add emoji reaction to a message (idempotent) |
| 3 | `deleteMessageForSelf` | POST | `/xrpc/chat.bsky.convo.deleteMessageForSelf` | Soft-delete a message for the viewer only |
| 4 | `getConvo` | GET | `/xrpc/chat.bsky.convo.getConvo` | Get a single conversation by ID |
| 5 | `getConvoAvailability` | GET | `/xrpc/chat.bsky.convo.getConvoAvailability` | Check if users can start a 1-1 chat (does not create conversation) |
| 6 | `getConvoForMembers` | GET | `/xrpc/chat.bsky.convo.getConvoForMembers` | Get or create a 1-1 (direct) conversation for given members |
| 7 | `getConvoMembers` | GET | `/xrpc/chat.bsky.convo.getConvoMembers` | Paginated list of all members in a conversation |
| 8 | `getLog` | GET | `/xrpc/chat.bsky.convo.getLog` | Get event log for the viewer (real-time event streaming) |
| 9 | `getMessages` | GET | `/xrpc/chat.bsky.convo.getMessages` | Get paginated messages from a conversation |
| 10 | `getUnreadCounts` | GET | `/xrpc/chat.bsky.convo.getUnreadCounts` | Get unread conversation counts (capped at 31/11) |
| 11 | `leaveConvo` | POST | `/xrpc/chat.bsky.convo.leaveConvo` | Leave a conversation |
| 12 | `listConvoRequests` | GET | `/xrpc/chat.bsky.convo.listConvoRequests` | List incoming conversation requests (direct + group join requests) |
| 13 | `listConvos` | GET | `/xrpc/chat.bsky.convo.listConvos` | List conversations (filterable by status, kind, lock status) |
| 14 | `lockConvo` | POST | `/xrpc/chat.bsky.convo.lockConvo` | Lock a group convo (no more messages/reactions) |
| 15 | `muteConvo` | POST | `/xrpc/chat.bsky.convo.muteConvo` | Mute a conversation (suppress notifications) |
| 16 | `removeReaction` | POST | `/xrpc/chat.bsky.convo.removeReaction` | Remove an emoji reaction (idempotent) |
| 17 | `sendMessage` | POST | `/xrpc/chat.bsky.convo.sendMessage` | Send a message to a conversation |
| 18 | `sendMessageBatch` | POST | `/xrpc/chat.bsky.convo.sendMessageBatch` | Send up to 100 messages in batch to one or more convos |
| 19 | `unlockConvo` | POST | `/xrpc/chat.bsky.convo.unlockConvo` | Unlock a group convo |
| 20 | `unmuteConvo` | POST | `/xrpc/chat.bsky.convo.unmuteConvo` | Unmute a conversation |
| 21 | `updateAllRead` | POST | `/xrpc/chat.bsky.convo.updateAllRead` | Mark all conversations as read (filterable by status) |
| 22 | `updateRead` | POST | `/xrpc/chat.bsky.convo.updateRead` | Update read state for a single conversation |

### Namespace: `chat.bsky.group.*` — Group Chat Management

| # | Endpoint | Method | XRPC Path | Description |
|---|----------|--------|-----------|-------------|
| 1 | `addMembers` | POST | `/xrpc/chat.bsky.group.addMembers` | Add members to a group (creates 'request' memberships) |
| 2 | `approveJoinRequest` | POST | `/xrpc/chat.bsky.group.approveJoinRequest` | Approve a join request to a group |
| 3 | `createGroup` | POST | `/xrpc/chat.bsky.group.createGroup` | Create a new group conversation (not idempotent) |
| 4 | `createJoinLink` | POST | `/xrpc/chat.bsky.group.createJoinLink` | Create a join link for a group |
| 5 | `disableJoinLink` | POST | `/xrpc/chat.bsky.group.disableJoinLink` | Disable a join link |
| 6 | `editGroup` | POST | `/xrpc/chat.bsky.group.editGroup` | Edit group info (name, etc.) |
| 7 | `editJoinLink` | POST | `/xrpc/chat.bsky.group.editJoinLink` | Edit join link settings |
| 8 | `enableJoinLink` | POST | `/xrpc/chat.bsky.group.enableJoinLink` | Enable a join link |
| 9 | `getJoinLinkPreviews` | GET | `/xrpc/chat.bsky.group.getJoinLinkPreviews` | Get preview data for join links |
| 10 | `listJoinRequests` | GET | `/xrpc/chat.bsky.group.listJoinRequests` | List pending join requests (owner only) |
| 11 | `listMutualGroups` | GET | `/xrpc/chat.bsky.group.listMutualGroups` | List groups in common with another user |
| 12 | `rejectJoinRequest` | POST | `/xrpc/chat.bsky.group.rejectJoinRequest` | Reject a join request |
| 13 | `removeMembers` | POST | `/xrpc/chat.bsky.group.removeMembers` | Remove members from a group |
| 14 | `requestJoin` | POST | `/xrpc/chat.bsky.group.requestJoin` | Request to join a group via join link |
| 15 | `updateJoinRequestsRead` | POST | `/xrpc/chat.bsky.group.updateJoinRequestsRead` | Mark join requests as read |
| 16 | `withdrawJoinRequest` | POST | `/xrpc/chat.bsky.group.withdrawJoinRequest` | Withdraw a pending join request |

### Namespace: `chat.bsky.moderation.*` — Chat Moderation

| # | Endpoint | Method | XRPC Path | Description |
|---|----------|--------|-----------|-------------|
| 1 | `getActorMetadata` | GET | `/xrpc/chat.bsky.moderation.getActorMetadata` | Get chat metadata for a user (messages sent/received, convos) |
| 2 | `getMessageContext` | GET | `/xrpc/chat.bsky.moderation.getMessageContext` | Get context around a message (for moderation review) |
| 3 | `updateActorAccess` | POST | `/xrpc/chat.bsky.moderation.updateActorAccess` | Allow or disallow a user from using chat |

### Namespace: `chat.bsky.actor.*` — Account Management

| # | Endpoint | Method | XRPC Path | Description |
|---|----------|--------|-----------|-------------|
| 1 | `deleteAccount` | POST | `/xrpc/chat.bsky.actor.deleteAccount` | Delete chat account data |
| 2 | `exportAccountData` | GET | `/xrpc/chat.bsky.actor.exportAccountData` | Export chat account data (JSONL) |

### Namespace: `chat.bsky.embed.*` — Message Embeds

| # | Type | Description |
|---|------|-------------|
| 1 | `joinLink` | Embed a group join link in a chat message |

## Service Architecture Note

The chat API uses **service proxying** via the `atproto-proxy` header:
- The request goes to the user's PDS
- The PDS proxies it to `did:web:api.bsky.chat#bsky_chat` (the central chat service)
- The chat service hostname is `https://api.bsky.chat`
- Service auth tokens are used for PDS-to-chat-service authentication

## Key Status Values

- **convoStatus**: `"request"` | `"accepted"`
- **convoKind**: `"direct"` | `"group"`
- **convoLockStatus**: `"unlocked"` | `"locked"` | `"locked-permanently"`
- **memberRole**: `"owner"` | `"standard"`
- **linkEnabledStatus**: `"enabled"` | `"disabled"`
- **joinRule**: `"anyone"` | `"followedByOwner"`
