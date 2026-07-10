---
source: AT Protocol Lexicon Schemas (chat/bsky/convo/defs.json, chat/bsky/actor/defs.json, chat/bsky/group/defs.json)
library: Bluesky
package: chat.bsky.*
topic: Data Models
fetched: 2026-06-12T14:00:00Z
official_docs: https://github.com/bluesky-social/atproto/tree/main/lexicons/chat/bsky
---

# Bluesky Chat API — Key Data Models

## 1. Convos (Conversations)

### `convoView` (chat.bsky.convo.defs#convoView)
The primary conversation object returned by list/get endpoints.

```typescript
{
  id: string;                    // Conversation ID
  rev: string;                   // Revision (for optimistic concurrency)
  members: profileViewBasic[];   // Partial member list (see notes below)
  lastMessage: messageView | deletedMessageView | systemMessageView | null;
  lastReaction: messageAndReactionView | null;
  muted: boolean;
  status: "request" | "accepted";// Viewer's status towards this convo
  unreadCount: number;
  kind: directConvo | groupConvo;// Union: direct or group-specific data
}
```

**Member list behavior**:
- For **direct** convos: immutable list of the 2 members
- For **group** convos: partial list (first few + viewer + adder + last message/reaction sender). Use `chat.bsky.convo.getConvoMembers` for the full list.

### `directConvo` (chat.bsky.convo.defs#directConvo)
No additional fields. The `kind` field distinguishes direct from group.

### `groupConvo` (chat.bsky.convo.defs#groupConvo)
Group-specific data within `convoView.kind`:

```typescript
{
  createdAt: string;              // ISO datetime
  lockStatus: "unlocked" | "locked" | "locked-permanently";
  lockStatusModerationOverride: boolean;
  memberCount: number;
  memberLimit: number;
  name: string;                   // Display name (max 128 graphemes)
  joinLink: joinLinkView | null;
  joinRequestCount: number | null;    // Only for owner, capped at 21
  unreadJoinRequestCount: number | null; // Only for owner
}
```

## 2. Messages

### `messageInput` (chat.bsky.convo.defs#messageInput)
Used when sending messages:

```typescript
{
  text: string;                  // Max 10,000 bytes / 1,000 graphemes
  facets?: app.bsky.richtext.facet[];  // Mentions, URLs, hashtags
  embed?: app.bsky.embed.record | chat.bsky.embed.joinLink;  // Post embed or join link
}
```

### `messageView` (chat.bsky.convo.defs#messageView)
Returned when reading messages:

```typescript
{
  id: string;                    // Message ID
  rev: string;                   // Revision
  text: string;                  // Max 10,000 bytes / 1,000 graphemes
  facets?: app.bsky.richtext.facet[];  // Rich text annotations
  embed?: app.bsky.embed.record#view | chat.bsky.embed.joinLink#view;
  reactions?: reactionView[];    // Reactions in ascending creation order
  sender: messageViewSender;
  sentAt: string;                // ISO datetime
}
```

### `deletedMessageView` (chat.bsky.convo.defs#deletedMessageView)
Returned when a message has been deleted (by the viewer or by the sender):

```typescript
{
  id: string;
  rev: string;
  sender: messageViewSender;
  sentAt: string;                // ISO datetime
}
```
Note: No `text`, `facets`, `embed`, or `reactions` fields — the content is gone.

### `systemMessageView` (chat.bsky.convo.defs#systemMessageView)
[UNDER ACTIVE DEVELOPMENT — UNSTABLE]
System-generated messages for group events:

```typescript
{
  id: string;
  rev: string;
  sentAt: string;                // ISO datetime
  data: systemMessageData*;      // Union of system message types
}
```

#### System Message Data Types

| Type | Fields | Description |
|------|--------|-------------|
| `systemMessageDataAddMember` | `member`, `role` ("owner" | "standard"), `addedBy` | User added to group |
| `systemMessageDataRemoveMember` | `member`, `removedBy` | User removed from group |
| `systemMessageDataMemberJoin` | `member`, `role`, `approvedBy?` | User joined via link |
| `systemMessageDataMemberLeave` | `member` | User left group |
| `systemMessageDataLockConvo` | `lockedBy` | Group locked |
| `systemMessageDataUnlockConvo` | `unlockedBy` | Group unlocked |
| `systemMessageDataLockConvoPermanently` | `lockedBy` | Group locked permanently |
| `systemMessageDataEditGroup` | `oldName?`, `newName?` | Group info edited |
| `systemMessageDataCreateJoinLink` | (none) | Join link created |
| `systemMessageDataEditJoinLink` | (none) | Join link edited |
| `systemMessageDataEnableJoinLink` | (none) | Join link enabled |
| `systemMessageDataDisableJoinLink` | (none) | Join link disabled |

All `systemMessageReferredUser` objects contain: `{ did: string }`.

### `messageViewSender` (chat.bsky.convo.defs#messageViewSender)
```typescript
{
  did: string;  // DID of the message sender
}
```

### `reactionView` (chat.bsky.convo.defs#reactionView)
```typescript
{
  value: string;               // Emoji (1 grapheme, max 64 bytes)
  sender: reactionViewSender;
  createdAt: string;           // ISO datetime
}
```

### `reactionViewSender` (chat.bsky.convo.defs#reactionViewSender)
```typescript
{
  did: string;
}
```

### `messageAndReactionView` (chat.bsky.convo.defs#messageAndReactionView)
Used in `convoView.lastReaction`:

```typescript
{
  message: messageView;
  reaction: reactionView;
}
```

### `messageRef` (chat.bsky.convo.defs#messageRef)
Reference to a specific message:

```typescript
{
  did: string;       // DID of the conversation member
  convoId: string;
  messageId: string;
}
```

## 3. Actor Profiles (Chat-specific)

### `profileViewBasic` (chat.bsky.actor.defs#profileViewBasic)
Extended actor profile for chat contexts:

```typescript
{
  did: string;
  handle: string;
  displayName?: string;         // Max 64 graphemes
  avatar?: string;              // URI
  associated?: app.bsky.actor.defs#profileAssociated;
  viewer?: app.bsky.actor.defs#viewerState;
  labels?: com.atproto.label.defs#label[];
  createdAt?: string;           // ISO datetime
  chatDisabled?: boolean;       // true if user cannot participate in chat
  verification?: app.bsky.actor.defs#verificationState;
  kind?: directConvoMember | groupConvoMember | pastGroupConvoMember;
}
```

#### Member Kinds

- **`directConvoMember`**: No additional fields
- **`groupConvoMember`**: `{ role: "owner" | "standard", addedBy?: profileViewBasic }`
- **`pastGroupConvoMember`**: No additional fields (was previously in the group)

### `memberRole` (chat.bsky.actor.defs#memberRole)
`"owner"` | `"standard"`

## 4. Join Links (Group Chat)

### `joinLinkView` (chat.bsky.group.defs#joinLinkView)
```typescript
{
  code: string;
  enabledStatus: "enabled" | "disabled";
  requireApproval: boolean;
  joinRule: "anyone" | "followedByOwner";
  createdAt: string;             // ISO datetime
}
```

### `joinLinkPreviewView` (chat.bsky.group.defs#joinLinkPreviewView)
```typescript
{
  convoId: string;
  code: string;
  name: string;
  owner: profileViewBasic;
  memberCount: number;
  memberLimit: number;
  requireApproval: boolean;
  joinRule: "anyone" | "followedByOwner";
  convo?: convoView;            // Present if authenticated user is member
  viewer?: joinLinkViewerState;
}
```

### `disabledJoinLinkPreviewView`
```typescript
{ code: string }
```

### `invalidJoinLinkPreviewView`
```typescript
{ code: string }
```

### `joinLinkViewerState`
```typescript
{
  requestedAt?: string;  // ISO datetime — present if user has requested
}
```

### `joinRequestView` (chat.bsky.group.defs#joinRequestView)
From the perspective of the group owner:

```typescript
{
  convoId: string;
  requestedBy: profileViewBasic;
  requestedAt: string;           // ISO datetime
}
```

### `joinRequestConvoView` (chat.bsky.group.defs#joinRequestConvoView)
From the perspective of the requester:

```typescript
{
  convoId: string;
  name: string;
  owner: profileViewBasic;
  memberCount: number;
  memberLimit: number;
  viewer: joinLinkViewerState;
}
```

## 5. Moderation Metadata

### `metadata` (chat.bsky.moderation.getActorMetadata#metadata)
```typescript
{
  messagesSent: number;
  messagesReceived: number;
  convos: number;
  convosStarted: number;
}
```
Returned in three time windows: `day`, `month`, `all`.

## 6. References

- `convoRef`: `{ did: string, convoId: string }`
- `messageRef`: `{ did: string, convoId: string, messageId: string }`
