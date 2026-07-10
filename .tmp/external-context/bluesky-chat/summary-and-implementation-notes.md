---
source: Bluesky AT Protocol Lexicons (github.com/bluesky-social/atproto)
library: Bluesky Social
package: chat.bsky
topic: Summary and Implementation Notes
fetched: 2026-06-12T18:30:00Z
official_docs: https://github.com/bluesky-social/atproto/tree/main/lexicons/chat/bsky
---

# Bluesky Chat API — Summary & Implementation Notes

## Quick Reference: Complete Endpoint List

### Actor Endpoints
| Method | Endpoint | Purpose |
|--------|----------|---------|
| Record (at://) | `chat.bsky.actor.declaration` | User's chat privacy preferences |
| Query | `chat.bsky.actor.getStatus` | Get viewer's chat status |
| Procedure | `chat.bsky.actor.deleteAccount` | Delete chat account data |
| Query | `chat.bsky.actor.exportAccountData` | Export all chat data (JSONL) |

### Conversation Endpoints
| Method | Endpoint | Purpose |
|--------|----------|---------|
| Query | `chat.bsky.convo.listConvos` | List conversations (with filters) |
| Query | `chat.bsky.convo.listConvoRequests` | List incoming requests + group join requests |
| Query | `chat.bsky.convo.getConvo` | Get a single conversation |
| Query | `chat.bsky.convo.getConvoForMembers` | Get/create 1-1 convo (idempotent) |
| Query | `chat.bsky.convo.getConvoAvailability` | Check if chat available |
| Query | `chat.bsky.convo.getConvoMembers` | List members (paginated) |
| Query | `chat.bsky.convo.getMessages` | Get messages (paginated) |
| Query | `chat.bsky.convo.getLog` | Poll for real-time events |
| Query | `chat.bsky.convo.getUnreadCounts` | Get unread counts |
| Procedure | `chat.bsky.convo.sendMessage` | Send a message |
| Procedure | `chat.bsky.convo.sendMessageBatch` | Send batch of messages |
| Procedure | `chat.bsky.convo.acceptConvo` | Accept a conversation request |
| Procedure | `chat.bsky.convo.leaveConvo` | Leave a conversation |
| Procedure | `chat.bsky.convo.deleteMessageForSelf` | Soft-delete a message |
| Procedure | `chat.bsky.convo.updateRead` | Mark convo as read |
| Procedure | `chat.bsky.convo.updateAllRead` | Mark all convos as read |
| Procedure | `chat.bsky.convo.muteConvo` | Mute a conversation |
| Procedure | `chat.bsky.convo.unmuteConvo` | Unmute a conversation |
| Procedure | `chat.bsky.convo.addReaction` | Add emoji reaction |
| Procedure | `chat.bsky.convo.removeReaction` | Remove emoji reaction |
| Procedure | `chat.bsky.convo.lockConvo` | Lock a group convo |
| Procedure | `chat.bsky.convo.unlockConvo` | Unlock a group convo |

### Group Endpoints (all [NOTE: unstable])
| Method | Endpoint | Purpose |
|--------|----------|---------|
| Procedure | `chat.bsky.group.createGroup` | Create a group |
| Procedure | `chat.bsky.group.addMembers` | Add members |
| Procedure | `chat.bsky.group.removeMembers` | Remove members |
| Procedure | `chat.bsky.group.editGroup` | Edit group name |
| Query | `chat.bsky.group.listMutualGroups` | List shared groups |
| Procedure | `chat.bsky.group.createJoinLink` | Create invite link |
| Procedure | `chat.bsky.group.editJoinLink` | Edit invite link settings |
| Procedure | `chat.bsky.group.enableJoinLink` | Re-enable invite link |
| Procedure | `chat.bsky.group.disableJoinLink` | Disable invite link |
| Query | `chat.bsky.group.getJoinLinkPreviews` | Preview groups from codes |
| Procedure | `chat.bsky.group.requestJoin` | Request to join via link |
| Procedure | `chat.bsky.group.withdrawJoinRequest` | Withdraw join request |
| Query | `chat.bsky.group.listJoinRequests` | List pending requests (owner) |
| Procedure | `chat.bsky.group.approveJoinRequest` | Approve join request |
| Procedure | `chat.bsky.group.rejectJoinRequest` | Reject join request |
| Procedure | `chat.bsky.group.updateJoinRequestsRead` | Mark requests as read |

### Moderation Endpoints
| Method | Endpoint | Purpose |
|--------|----------|---------|
| Query | `chat.bsky.moderation.getConvo` | Get convo (mod view) |
| Query | `chat.bsky.moderation.getConvos` | Get multiple convos (mod view) |
| Query | `chat.bsky.moderation.getConvoMembers` | List members (mod view) |
| Query | `chat.bsky.moderation.getMessageContext` | Get message context |
| Query | `chat.bsky.moderation.getActorMetadata` | Get actor chat metadata |
| Procedure | `chat.bsky.moderation.updateActorAccess` | Toggle chat access |
| Subscription | `chat.bsky.moderation.subscribeModEvents` | WebSocket mod event stream |

## XRPC Paths Summary

All endpoints are called via:
```
GET  https://{PDS_HOST}/xrpc/chat.bsky.{ns}.{action}  (queries)
POST https://{PDS_HOST}/xrpc/chat.bsky.{ns}.{action}  (procedures)
```

The PDS host is typically the user's PDS (e.g., `bsky.social`, or a self-hosted PDS).

## Key Behavioral Rules

1. **Request → Accepted flow**: Members are added in `"request"` status. They must call `acceptConvo` (or send a message, which auto-accepts) to move to `"accepted"`.

2. **No "decline" endpoint**: There's no explicit "decline" or "reject" endpoint for convo requests. You simply don't accept them. The request will naturally remain or the sender can be blocked.

3. **Block overrides mute**: When computing unread counts, direct convos with blocked members are excluded.

4. **getConvoForMembers is idempotent for direct convos only**: For 1-1 chats, this always returns the same convo. For groups, use `createGroup` which always creates new.

5. **Member list in convoView is a sample**: For group convos, `convoView.members` does NOT contain the full member list. It contains "important members" (first few, viewer, adder, last message/reaction senders). Use `getConvoMembers` for the full list.

6. **Soft delete**: `deleteMessageForSelf` only hides the message for the viewer. Other participants can still see it.

7. **System messages cannot be deleted or reacted to**: The `ReactionNotAllowed` and `MessageDeleteNotAllowed` errors protect system messages.

8. **Owner cannot leave group**: The owner must first lock the group before they can leave. This prevents orphaned groups.

9. **New accounts restricted**: New accounts cannot create groups. Check `getStatus().canCreateGroups`.

10. **unreadCounts are capped**: Accepted convos cap at 31 (31 = 30+), requests cap at 11 (11 = 10+).

## Implementation Notes (for Swift/iOS client)

### Polling for Real-time Updates
Rather than WebSocket for regular users, implement polling via `chat.bsky.convo.getLog`:
```swift
// Store the last cursor from UserDefaults or in-memory
var chatLogCursor: String?

// Periodically call (every 3-5 seconds):
func pollChatLog() async throws {
    let response = try await callXRPC(
        "chat.bsky.convo.getLog",
        params: cursor != nil ? ["cursor": chatLogCursor] : [:]
    )
    chatLogCursor = response.cursor
    // Process response.logs array
}
```

### Managing Conversations List
- Use `listConvos` for the main conversations tab (accepted conversations)
- Use `listConvoRequests` for the requests inbox
- Use `getUnreadCounts` for the badge count display
- The `kind` field helps differentiate direct vs group for UI rendering

### Chat Request UX Flow
1. Call `getUnreadCounts` to show badge on "Requests" tab
2. Call `listConvoRequests` to populate the requests list
3. User taps "Accept" → call `acceptConvo(convoId:)`
4. User sends message in request convo → auto-accepts
5. Group join requests show as `joinRequestConvoView` with group context

### Group Chat UX Flow
1. Create group → `createGroup` with members array + name
2. Manage members → `addMembers` / `removeMembers`
3. Share invite → `createJoinLink` → copy URL with code
4. Join via link → `getJoinLinkPreviews` to show preview → `requestJoin`
5. Owner manages requests → `listJoinRequests` → `approveJoinRequest` / `rejectJoinRequest`

### User Availability Check
Before starting a 1-1 chat:
1. Check user's `chat.bsky.actor.declaration` (if accessible)
2. Call `getConvoAvailability` with the user's DID
3. If `canChat` is false, show an appropriate error

### Error Handling
Common errors to handle:
- `AccountSuspended` / `BlockedActor` / `BlockedSubject`: User-level blocks
- `ConvoLocked`: Group has been locked
- `NotFollowedBySender`: Recipient only accepts messages from followed users
- `MessagesDisabled`: User has `allowIncoming: "none"`
- `NewAccountCannotCreateGroup`: Account too new
- `MemberLimitReached`: Group is full
- `InsufficientRole`: Only owner can perform this action
- `OwnerCannotLeave`: Owner must lock group before leaving
- `ReactionLimitReached`: Max reactions on message per user
