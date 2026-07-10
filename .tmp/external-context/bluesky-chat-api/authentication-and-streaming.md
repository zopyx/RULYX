---
source: docs.bsky.app (API Hosts and Auth, Service Auth guides)
library: Bluesky
package: chat.bsky.*
topic: Authentication & Streaming
fetched: 2026-06-12T14:00:00Z
official_docs: https://docs.bsky.app/docs/advanced-guides/api-directory
---

# Bluesky Chat API — Authentication, Pagination & Event Log

## 1. Authentication

### Standard Client Auth (for app clients)
Chat endpoints use the **same authentication** as all other Bluesky API endpoints:

1. **Create a session**: `POST /xrpc/com.atproto.server.createSession` with handle/identifier + app password
2. **Use the access token**: Pass it as `Authorization: Bearer <accessJwt>` in all subsequent requests
3. **App passwords** work the same as for the main API

### Request Routing (Service Proxying)
The critical difference from regular Bluesky APIs is the **routing path**:

1. The client sends the request to **its own PDS** (e.g., `https://bsky.social`)
2. The PDS proxies the request to the centralized chat service using **service auth**
3. The chat service DID is: `did:web:api.bsky.chat`
4. The chat service hostname is: `https://api.bsky.chat`
5. The `atproto-proxy` header is set by the PDS automatically

From the docs: *"chat.bsky.* APIs... are generally authenticated, routed via the PDS, and use service proxying to route to the relevant service instance."*

### Service Auth (PDS-to-Chat-Service)
When the PDS forwards a chat request to the chat service, it signs a JWT:

```typescript
type Payload = {
  iss: string;  // User's DID
  aud: string;  // Service DID (did:web:api.bsky.chat)
  exp: number;  // Short expiration (<60 seconds)
}
```

This JWT is signed by the user's signing key (from their DID document).

### How Clients Typically Implement It
From the existing project code (`ChatService.swift`):
```swift
// Example pattern: Use AT Protocol proxy headers
let request = ATProtocolRequest(
    path: "chat.bsky.convo.listConvos",
    method: .get,
    // Add service proxy header
    headers: ["atproto-proxy": "did:web:api.bsky.chat#bsky_chat"]
)
```

The client library (like `@atproto/api` or Swift `ATProtocol` client) handles the proxying automatically when you use chat endpoints.

## 2. Pagination

### Cursor-based Pagination
All list-style chat endpoints use cursor-based pagination:

| Endpoint | Parameters | Default Limit | Max Limit |
|----------|-----------|---------------|-----------|
| `listConvos` | `cursor`, `limit` | 50 | 100 |
| `listConvoRequests` | `cursor`, `limit` | 50 | 100 |
| `getMessages` | `cursor`, `limit` | 50 | 100 |
| `getConvoMembers` | `cursor`, `limit` | 50 | 100 |
| `getLog` | `cursor` | (no limit) | (no limit) |
| `listJoinRequests` | `cursor`, `limit` | 50 | 100 |

**Pattern**:
1. Make initial request without cursor
2. Response includes `cursor` string if there are more results
3. Pass the cursor in the next request to get the next page
4. When cursor is `null`/absent, end of results reached

### Filter Parameters

**`listConvos`** additional filters:
```
?status=request|accepted
?kind=direct|group
?lockStatus=unlocked|locked|locked-permanently
?readState=unread
```

## 3. Event Log (Real-time / Streaming Pattern)

### `chat.bsky.convo.getLog`
This is the **most important endpoint for real-time updates**. It returns a page of events for the viewer, allowing clients to stay synchronized with chat state without polling.

```typescript
// GET /xrpc/chat.bsky.convo.getLog?cursor=xxx
{
  cursor?: string;
  logs: Array<LogEvent>;  // Union of many event types
}
```

### Complete List of Log Event Types

| Event Type | Description | Who Receives It |
|-----------|-------------|-----------------|
| `logBeginConvo` | Convo containing viewer was started | All members |
| `logAcceptConvo` | Viewer accepted a convo | Viewer only |
| `logLeaveConvo` | Viewer left a convo | Viewer only |
| `logMuteConvo` | Viewer muted a convo | Viewer only |
| `logUnmuteConvo` | Viewer unmuted a convo | Viewer only |
| `logCreateMessage` | User-originated message created | All members |
| `logDeleteMessage` | User-originated message deleted | All members |
| `logReadMessage` | [DEPRECATED] Use logReadConvo | — |
| `logReadConvo` | Convo was read up to a message | Viewer only |
| `logAddReaction` | Reaction added to a message | All members |
| `logRemoveReaction` | Reaction removed from a message | All members |
| `logAddMember` | Member added to group convo | Other members |
| `logRemoveMember` | Member removed from group convo | Other members |
| `logMemberJoin` | Member joined via join link | Other members |
| `logMemberLeave` | Member voluntarily left group | Other members |
| `logLockConvo` | Group convo was locked | Other members |
| `logUnlockConvo` | Group convo was unlocked | Other members |
| `logLockConvoPermanently` | Group convo locked permanently | Other members |
| `logEditGroup` | Group info edited | Other members |
| `logCreateJoinLink` | Join link created | Other members |
| `logEditJoinLink` | Join link edited | Other members |
| `logEnableJoinLink` | Join link enabled | Other members |
| `logDisableJoinLink` | Join link disabled | Other members |
| `logIncomingJoinRequest` | Someone requested to join group | Owner only |
| `logApproveJoinRequest` | Viewer approved a join request | Owner only |
| `logRejectJoinRequest` | Viewer rejected a join request | Owner only |
| `logOutgoingJoinRequest` | Viewer requested to join a group | Requester only |
| `logWithdrawIncomingJoinRequest` | Prospective member withdrew request | Owner only |
| `logWithdrawOutgoingJoinRequest` | Viewer withdrew their own request | Requester only |
| `logReadJoinRequests` | Owner marked join requests as read | Owner only |

### Log Event Structure (example: logCreateMessage)

```typescript
{
  rev: string;
  convoId: string;
  message: messageView | deletedMessageView;
  relatedProfiles?: profileViewBasic[];  // Profiles referenced in the message
}
```

### How to Use the Log for Real-time Updates

1. **Initial fetch**: Call `getLog` without cursor to get the most recent events
2. **Poll**: Regularly call `getLog` with the last cursor (e.g., every 5-10 seconds)
3. **Process events**: Apply each event to your local state:
   - `logCreateMessage` → Append message to conversation
   - `logDeleteMessage` → Replace with `deletedMessageView`
   - `logAddReaction` / `logRemoveReaction` → Update reactions on message
   - `logBeginConvo` → Add new conversation to list
   - `logAcceptConvo` → Move convo from requests to accepted
   - `logAddMember` / `logRemoveMember` → Update member list
   - `logLockConvo` / `logUnlockConvo` → Update lock status

4. **No WebSocket/Webhook currently**: The chat API does not have a documented WebSocket endpoint or webhook system. Polling `getLog` is the recommended approach for real-time updates.

### Relationship to Notifications
Chat events do NOT go through the regular `app.bsky.notification.*` system. The chat service manages its own notification state via:
- `unreadCount` on `convoView`
- `getUnreadCounts` endpoint
- Mute state on conversations
- The event log system

## 4. Read State Management

### Per-Conversation Read State
```
POST /xrpc/chat.bsky.convo.updateRead
Body: { "convoId": "string", "messageId"?: "string" }
```
- If `messageId` is omitted, marks as read up to the latest message
- Returns the updated `convoView`

### Mark All Read
```
POST /xrpc/chat.bsky.convo.updateAllRead
Body: { "status"?: "request" | "accepted" }
```
- Filter by status (optional)
- Returns `{ updatedCount: number }`

## 5. Message Deletion

### Soft Delete (viewer only)
```
POST /xrpc/chat.bsky.convo.deleteMessageForSelf
Body: { "convoId": "string", "messageId": "string" }
```
- Marks message as deleted **for the viewer only**
- Other participants still see the message
- Returns `deletedMessageView`
- Error `MessageDeleteNotAllowed` for system messages

### Hard Delete (not available via API)
There is no "delete for everyone" endpoint currently. Only soft-deletion per-viewer is supported.

## 6. Muting

```
POST /xrpc/chat.bsky.convo.muteConvo     → returns { convo: convoView }
POST /xrpc/chat.bsky.convo.unmuteConvo   → returns { convo: convoView }
```
- Muting suppresses notifications
- Muted state is reflected in `convoView.muted`
- Mute/unmute events appear in the event log

## 7. Export & Account Deletion

- `chat.bsky.actor.exportAccountData` — Export all chat data as JSONL
- `chat.bsky.actor.deleteAccount` — Delete chat account data (separate from main account deletion)
