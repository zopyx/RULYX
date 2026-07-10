---
source: AT Protocol Lexicon Schemas (GitHub) + docs.bsky.app
library: Bluesky
package: chat.bsky.*
topic: Chat Requests & Group Chat
fetched: 2026-06-12T14:00:00Z
official_docs: https://docs.bsky.app/docs/category/http-reference
---

# Bluesky Chat API — Chat Requests & Group Chat Feature

## 1. Chat Requests System

### Overview

Bluesky has a two-tier conversation status system:
- **"request"**: The conversation is pending — the recipient hasn't accepted it yet
- **"accepted"**: The conversation has been accepted and appears in the main inbox

This applies to both direct (1-1) and group conversations. The core principle: **you cannot message someone who doesn't follow you without them first accepting your chat request**.

### How Chat Requests Work

#### Flow for Direct Messages (1-1)

1. **Sender initiates** a DM via `chat.bsky.convo.getConvoForMembers` (gets or creates a direct convo)
2. The convo is created with `status: "request"` for the recipient
3. **The sender can send messages** immediately (the convo exists)
4. The recipient sees the convo in their **request inbox** (separate from accepted conversations)
5. The recipient can:
   - **Accept**: Call `chat.bsky.convo.acceptConvo` → status changes to `"accepted"` → moves to main inbox
   - **Ignore**: Simply don't accept (messages still collect, but convo stays in requests)
   - **Block/mute**: Through the regular graph blocking mechanisms

#### Error Conditions for Starting a Conversation

`getConvoForMembers` can fail with these errors:
- `AccountSuspended` — recipient account is suspended
- `BlockedActor` — the sender has blocked the recipient
- `BlockedSubject` — the recipient has blocked the sender
- `MessagesDisabled` — the recipient has disabled messages
- `NotFollowedBySender` — the sender must follow the recipient (for certain configurations)
- `RecipientNotFound` — the recipient DID doesn't exist

#### Checking Availability Before Starting

Use `chat.bsky.convo.getConvoAvailability` to check if you can start a chat with someone **without** creating the conversation:

```
GET /xrpc/chat.bsky.convo.getConvoAvailability?members=did:plc:xxx&members=did:plc:yyy
```

Response:
```typescript
{
  canChat: boolean;       // Whether a chat can be started
  convo?: convoView;      // Existing convo if one already exists
}
```

This is a read-only check — it does not create a new conversation.

#### Listing Requests vs. Accepted

**`listConvos`** has a `status` filter parameter:
- `status: "request"` — Show only request convos
- `status: "accepted"` — Show only accepted convos (default behavior)

**`listConvoRequests`** — Dedicated endpoint for the request inbox:
- Returns a union of `convoView` (for direct message requests) and `joinRequestConvoView` (for group join requests the user made)
- The official docs say: *"It is discouraged to call listConvos with status=request; preferred to call listConvoRequests, which also includes group join requests made by the user."*

#### Accepting a Conversation

```
POST /xrpc/chat.bsky.convo.acceptConvo
Body: { "convoId": "string" }
```

Response:
```typescript
{
  rev: string;  // Rev when accepted. If not present, convo was already accepted.
}
```

Errors: `InvalidConvo`

### Unread Counts by Status

`chat.bsky.convo.getUnreadCounts` returns separate counts:
- `unreadAcceptedConvos` — for accepted (inbox) convos, capped at 31
- `unreadRequestConvos` — for request convos, capped at 11

Group convos are counted as unread if they have unread join request counts (for the owner).

### "Mark All Read" by Status

`chat.bsky.convo.updateAllRead` accepts an optional `status` parameter:
- `status: "request"` — Mark all request convos as read
- `status: "accepted"` — Mark all accepted convos as read
- Omitting status marks all convos as read

## 2. Group Chat Feature

### Status: [UNDER ACTIVE DEVELOPMENT — UNSTABLE]

Many group chat features are marked with: *"[NOTE: This is under active development and should be considered unstable while this note is here]"*

### Creating a Group

```
POST /xrpc/chat.bsky.group.createGroup
Body: {
  "members": ["did:plc:xxx", "did:plc:yyy"],  // Max 49 members + yourself
  "name": "My Group"                            // 1-50 graphemes
}
```

- **Not idempotent**: Creating a group with the same members creates a new group each time
- The creator is added with `status: "accepted"` (owner role)
- All other members are added with `status: "request"` — they must accept
- Members can be up to 49 DIDs (plus the creator)

Error conditions:
- `AccountSuspended`, `BlockedActor`, `BlockedSubject`
- `NewAccountCannotCreateGroup` — account too new
- `NotFollowedBySender` — must follow members (for some configurations)
- `RecipientNotFound`
- `UserForbidsGroups` — user has disabled group invitations

### Group Lifecycle

```
┌──────────┐     createGroup()     ┌──────────────────┐
│  Create  │ ─────────────────────→│  Owner is Owner   │
│  Group   │                       │  Members are      │
└──────────┘                       │  "request" status │
                                   └──────────────────┘
                                           │
                                    acceptConvo() by members
                                           │
                                           ▼
                                   ┌──────────────────┐
                                   │  Members are      │
                                   │  "accepted"        │
                                   └──────────────────┘
                                           │
                              ┌────────────┼────────────┐
                              ▼            ▼            ▼
                        addMembers()  leaveConvo()  lockConvo()
                        removeMembers()              unlockConvo()
```

### Managing Group Members

**Add members** (`chat.bsky.group.addMembers`):
```
POST /xrpc/chat.bsky.group.addMembers
Body: { "convoId": "string", "members": ["did:plc:xxx"] }
```
- Members are added in "request" status (they must accept)
- Fails if: convo is locked, insufficient role, member limit reached
- Returns: `{ convo: convoView, addedMembers: profileViewBasic[] }`

**Remove members** (`chat.bsky.group.removeMembers`):
```
POST /xrpc/chat.bsky.group.removeMembers
Body: { "convoId": "string", "members": ["did:plc:xxx"] }
```

**Get all members** (`chat.bsky.convo.getConvoMembers`):
```
GET /xrpc/chat.bsky.convo.getConvoMembers?convoId=xxx&limit=50&cursor=yyy
```
- Paginated (default 50, max 100)
- Returns all members with their roles

**Leave a group** (`chat.bsky.convo.leaveConvo`):
```
POST /xrpc/chat.bsky.convo.leaveConvo
Body: { "convoId": "string" }
```
- The **owner cannot leave** without first locking the group (`OwnerCannotLeave` error)
- For direct convos: membership is never fully removed, just hidden from enumeration

### Locking/Unlocking

**Lock** (`chat.bsky.convo.lockConvo`): Prevents new messages/reactions. Only the owner can lock.
**Unlock** (`chat.bsky.convo.unlockConvo`): Re-enables messaging.
**Lock Permanently** (`chat.bsky.convo.lockConvo` with `locked-permanently`): Irreversible (conceptually, via system message).

### Join Links

Join links allow users to join a group without being added by a member:

1. **Create** (`chat.bsky.group.createJoinLink`): Generates a unique code
2. **Enable/Disable** (`enableJoinLink`, `disableJoinLink`): Toggle whether the link works
3. **Edit** (`chat.bsky.group.editJoinLink`): Change settings (requireApproval, joinRule)
4. **Preview** (`chat.bsky.group.getJoinLinkPreviews`): Get preview data for rendering

**Join link configuration:**
- `requireApproval: boolean` — Whether join requests need owner approval
- `joinRule: "anyone" | "followedByOwner"` — Who can use the link

**Requesting to join** (`chat.bsky.group.requestJoin`):
- If `requireApproval: false` → user joins immediately
- If `requireApproval: true` → creates a join request, owner must approve

**Join request management:**
- `listJoinRequests` — Owner lists pending requests
- `approveJoinRequest` — Owner approves
- `rejectJoinRequest` — Owner rejects
- `withdrawJoinRequest` — Requester cancels their own request
- `updateJoinRequestsRead` — Owner marks requests as read

**Embeds**: Join links can be embedded in chat messages via `chat.bsky.embed.joinLink`.

### Mutual Groups

`chat.bsky.group.listMutualGroups`: Lists groups in common between the viewer and another user. Useful for discovery ("groups in common").

### Editing Group Info

`chat.bsky.group.editGroup`: Update the group name.
- Generates a `systemMessageDataEditGroup` system message with old/new name

## 3. System Messages in Groups

Group conversations generate system messages for various events. These appear in the message stream alongside user messages and are returned as `systemMessageView` objects.

System messages are visible only to members who are in the group at the time:
- `logAddMember` — Other members see this, the added member gets `logBeginConvo` + `logAddMember`
- `logRemoveMember` — Other members see this, the removed member gets `logLeaveConvo`
- `logMemberJoin` — When someone joins via link (with approval info)
- `logMemberLeave` — When someone voluntarily leaves (other members see it)
- `logLockConvo` / `logUnlockConvo` / `logLockConvoPermanently`
- `logEditGroup`
- `logCreateJoinLink` / `logEditJoinLink` / `logEnableJoinLink` / `logDisableJoinLink`

System messages:
- **Cannot** be reacted to (`ReactionNotAllowed` error)
- **Cannot** be deleted (`MessageDeleteNotAllowed` error)
- Are filtered by `maxInterleavedSystemMessages` in moderation context queries

## 4. Reactions in Chat

Reactions are emoji reactions on messages:

- **Add**: `chat.bsky.convo.addReaction` — `{ convoId, messageId, value (emoji) }`
- **Remove**: `chat.bsky.convo.removeReaction` — `{ convoId, messageId, value (emoji) }`
- Both are **idempotent**
- Value: single grapheme emoji (1-64 bytes)
- Errors: `ReactionNotAllowed` (system messages), `ReactionMessageDeleted`, `ReactionLimitReached` (per-user limit), `ReactionInvalidValue` (not an emoji)
- Reactions appear in `messageView.reactions[]` in ascending creation order
- Reactions trigger `logAddReaction` / `logRemoveReaction` events in the log
