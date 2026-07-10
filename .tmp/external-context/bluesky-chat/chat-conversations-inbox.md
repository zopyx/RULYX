---
source: Bluesky AT Protocol Lexicons (github.com/bluesky-social/atproto)
library: Bluesky Social
package: chat.bsky
topic: Flat list of all Chat API endpoints with Descriptions
fetched: 2026-06-12T18:30:00Z
official_docs: https://github.com/bluesky-social/atproto/tree/main/lexicons/chat/bsky
---

# All Chat API Endpoints — Flat Reference

This file provides a quick-reference flat list of every `chat.bsky.*` lexicon file found in the AT Protocol repository as of June 2026.

## chat.bsky.actor (4 files)

| Lexicon ID | Type | Description |
|------------|------|-------------|
| `chat.bsky.actor.declaration` | **record** (at://) | A declaration of a Bluesky chat account. `allowIncoming: "all"\|"none"\|"following"`. Key: `literal:self`. |
| `chat.bsky.actor.defs` | **defs** | Defines `memberRole` ("owner", "standard") and `profileViewBasic` with chat-specific fields (`chatDisabled`, `verification`, `kind`: `directConvoMember`, `groupConvoMember`, `pastGroupConvoMember`). |
| `chat.bsky.actor.deleteAccount` | **procedure** | Deletes the user's chat account data. |
| `chat.bsky.actor.exportAccountData` | **query** | Exports all chat account data in JSONL format. |
| `chat.bsky.actor.getStatus` | **query** | Gets the authenticated viewer's chat status: `chatDisabled`, `canCreateGroups`, `groupMemberLimit`. |

## chat.bsky.convo (25 files)

| Lexicon ID | Type | Description |
|------------|------|-------------|
| `chat.bsky.convo.defs` | **defs** | Core type definitions: `convoKind`, `convoLockStatus`, `convoStatus`, `convoRef`, `messageRef`, `messageInput`, `messageView`, `deletedMessageView`, `messageViewSender`, `reactionView`, `reactionViewSender`, `messageAndReactionView`, `convoView`, `directConvo`, `groupConvo`, and 30 `log*` event types. |
| `chat.bsky.convo.listConvos` | **query** | Returns a page of conversations (direct or group) with filters: `limit`, `cursor`, `readState` ("unread"), `status` ("request"\|"accepted"), `kind` ("direct"\|"group"), `lockStatus` ("unlocked"\|"locked"\|"locked-permanently"). |
| `chat.bsky.convo.listConvoRequests` | **query** | Returns incoming conversation requests. Direct convos returned as `convoView`; group join requests returned as `joinRequestConvoView`. |
| `chat.bsky.convo.getConvo` | **query** | Gets an existing conversation by ID. Error: `InvalidConvo`. |
| `chat.bsky.convo.getConvoForMembers` | **query** | Get or create a 1-1 conversation for given members (idempotent). 1-10 DIDs. Errors: `AccountSuspended`, `BlockedActor`, `BlockedSubject`, `MessagesDisabled`, `NotFollowedBySender`, `RecipientNotFound`. |
| `chat.bsky.convo.getConvoAvailability` | **query** | Check if chat can be started with given members. Does NOT create a convo. Returns `canChat: bool` + optional existing `convo`. |
| `chat.bsky.convo.getConvoMembers` | **query** | Returns paginated list of members from a conversation. Error: `InvalidConvo`. |
| `chat.bsky.convo.getMessages` | **query** | Returns a page of messages from a conversation. Returns `messages[]` (mix of messageView, deletedMessageView, systemMessageView) + `relatedProfiles[]`. Error: `InvalidConvo`. |
| `chat.bsky.convo.getLog` | **query** | Poll for real-time log events. Returns array of typed log events with cursor for subsequent calls. |
| `chat.bsky.convo.getUnreadCounts` | **query** | Returns unread counts: `unreadAcceptedConvos` (capped 31) and `unreadRequestConvos` (capped 11). Optional `includeGroupChats` parameter. |
| `chat.bsky.convo.sendMessage` | **procedure** | Sends a message to a conversation. Input: `convoId` + `message` (text, optional facets, optional embed). Output: `messageView`. Errors: `ConvoLocked`, `InvalidConvo`. |
| `chat.bsky.convo.sendMessageBatch` | **procedure** | Sends up to 100 messages. Input: `items[]` (each with `convoId` + `message`). Output: `items[]` of `messageView`. |
| `chat.bsky.convo.acceptConvo` | **procedure** | Marks a conversation as accepted (moves from request to accepted inbox). Input: `convoId`. Output: optional `rev` (absent if already accepted). Error: `InvalidConvo`. |
| `chat.bsky.convo.leaveConvo` | **procedure** | Leaves a conversation. Direct: removes from enumeration. Group: deletes membership. Error: `OwnerCannotLeave`. |
| `chat.bsky.convo.deleteMessageForSelf` | **procedure** | Marks a message as deleted for the viewer only. Input: `convoId` + `messageId`. Output: `deletedMessageView`. Errors: `MessageDeleteNotAllowed` (system messages). |
| `chat.bsky.convo.updateRead` | **procedure** | Updates read state of a conversation. Input: `convoId` (required) + `messageId` (optional). Output: `convo`. Error: `InvalidConvo`. |
| `chat.bsky.convo.updateAllRead` | **procedure** | Sets all conversations as read. Optional `status` filter ("request"\|"accepted"). Output: `updatedCount`. |
| `chat.bsky.convo.muteConvo` | **procedure** | Mutes a conversation (prevents notifications). Input: `convoId`. Output: `convo`. |
| `chat.bsky.convo.unmuteConvo` | **procedure** | Unmutes a conversation. Input: `convoId`. Output: `convo`. |
| `chat.bsky.convo.addReaction` | **procedure** | Adds emoji reaction (1 grapheme, idempotent). Input: `convoId`, `messageId`, `value`. Output: `message`. Errors: `ReactionNotAllowed`, `ReactionMessageDeleted`, `ReactionLimitReached`, `ReactionInvalidValue`. |
| `chat.bsky.convo.removeReaction` | **procedure** | Removes emoji reaction (idempotent). Same input/output as addReaction. Same errors minus `ReactionLimitReached`. |
| `chat.bsky.convo.lockConvo` | **procedure** | Locks a group convo (prevents new content). Input: `convoId`. Output: `convo`. Errors: `ConvoLocked`, `InsufficientRole`. |
| `chat.bsky.convo.unlockConvo` | **procedure** | Unlocks a group convo. Input: `convoId`. Output: `convo`. Errors: `ConvoLockedByModeration`, `InsufficientRole`. |
| `chat.bsky.convo.muteConvo` | **procedure** | Mutes a conversation (in: `convoId`, out: `convo`) |
| `chat.bsky.convo.unmuteConvo` | **procedure** | Unmutes a conversation (in: `convoId`, out: `convo`) |

## chat.bsky.group (16 files)

| Lexicon ID | Type | Description |
|------------|------|-------------|
| `chat.bsky.group.defs` | **defs** | Defines `linkEnabledStatus`, `joinRule`, `joinLinkView`, `joinLinkPreviewView`, `disabledJoinLinkPreviewView`, `invalidJoinLinkPreviewView`, `joinLinkViewerState`, `joinRequestView`, `joinRequestConvoView`. |
| `chat.bsky.group.createGroup` | **procedure** | Creates a group convo (not idempotent). Input: `members[]` (max 49 DIDs), `name` (1-50 graphemes). Output: `convo`. Various errors for blocks/suspension/restrictions. |
| `chat.bsky.group.addMembers` | **procedure** | Adds members to a group. Input: `convoId`, `members[]`. Output: `convo` + `addedMembers[]`. Members added in "request" status. |
| `chat.bsky.group.removeMembers` | **procedure** | Removes members from a group. Input: `convoId`, `members[]`. Output: `convo`. Errors: `InsufficientRole`. |
| `chat.bsky.group.editGroup` | **procedure** | Edits group name. Input: `convoId`, `name` (1-128 graphemes). Output: `convo`. Errors: `ConvoLocked`, `InsufficientRole`. |
| `chat.bsky.group.listMutualGroups` | **query** | Lists group conversations both requester and subject are members of. Input: `subject` DID. Output: `convos[]`. |
| `chat.bsky.group.createJoinLink` | **procedure** | Creates a join link. Input: `convoId`, `requireApproval` (default false), `joinRule` ("anyone"\|"followedByOwner"). Output: `joinLink`. Error: `EnabledJoinLinkAlreadyExists`. |
| `chat.bsky.group.editJoinLink` | **procedure** | Edits join link settings. Input: `convoId`, optional `requireApproval`, optional `joinRule`. Output: `joinLink`. Error: `NoJoinLink`. |
| `chat.bsky.group.enableJoinLink` | **procedure** | Re-enables a disabled join link. Input: `convoId`. Output: `joinLink`. Error: `LinkAlreadyEnabled`. |
| `chat.bsky.group.disableJoinLink` | **procedure** | Disables a join link. Input: `convoId`. Output: `joinLink`. Error: `NoJoinLink`. |
| `chat.bsky.group.getJoinLinkPreviews` | **query** | Gets public group info from join link codes (1-50). Output matches input one-to-one by position. Output types: `joinLinkPreviewView`, `disabledJoinLinkPreviewView`, `invalidJoinLinkPreviewView`. |
| `chat.bsky.group.requestJoin` | **procedure** | Sends a request to join a group via join link. Input: `code`. Output: `status` ("joined"\|"pending") + optional `convo`. Errors: `FollowRequired`, `LinkDisabled`, `MemberLimitReached`, `UserKicked`. |
| `chat.bsky.group.withdrawJoinRequest` | **procedure** | Withdraws a pending join request. Input: `convoId`. Output: empty. Error: `InvalidJoinRequest`. |
| `chat.bsky.group.listJoinRequests` | **query** | Lists pending join requests (owner view). Input: `convoId`. Output: `requests[]` of `joinRequestView`. Errors: `InsufficientRole`. |
| `chat.bsky.group.approveJoinRequest` | **procedure** | Approves a join request. Input: `convoId`, `member` DID. Output: `convo`. Errors: `MemberLimitReached`. |
| `chat.bsky.group.rejectJoinRequest` | **procedure** | Rejects a join request. Input: `convoId`, `member` DID. Output: empty. Errors: `InsufficientRole`. |
| `chat.bsky.group.updateJoinRequestsRead` | **procedure** | Marks all join requests as read for the group owner. Input: `convoId`. Output: empty. |

## chat.bsky.embed (1 file)

| Lexicon ID | Type | Description |
|------------|------|-------------|
| `chat.bsky.embed.joinLink` | **embed** | A join link embed for chat messages. `main` has `code` string. `view` has `joinLinkPreview` (union of preview view types). |

## chat.bsky.moderation (8 files)

| Lexicon ID | Type | Description |
|------------|------|-------------|
| `chat.bsky.moderation.defs` | **defs** | Moderation-specific `convoView` (no viewer data like muted/unread) with `directConvo` and `groupConvo`. |
| `chat.bsky.moderation.getActorMetadata` | **query** | Gets chat metadata for an actor (day, month, all time): `messagesSent`, `messagesReceived`, `convos`, `convosStarted`. |
| `chat.bsky.moderation.getConvo` | **query** | Gets convo for moderation (doesn't require membership). |
| `chat.bsky.moderation.getConvos` | **query** | Gets multiple convos by IDs (100 max). Unknown IDs silently omitted. |
| `chat.bsky.moderation.getConvoMembers` | **query** | Lists members for moderation (doesn't require membership). |
| `chat.bsky.moderation.getMessageContext` | **query** | Gets message context (before/after messages). Parameters: `messageId`, optional `convoId`, `before` (default 5), `after` (default 5), `maxInterleavedSystemMessages` (default 10). |
| `chat.bsky.moderation.subscribeModEvents` | **subscription** | WebSocket subscription for moderation events. Private endpoint. Error: `ConsumerTooSlow` if backlog too large. |
| `chat.bsky.moderation.updateActorAccess` | **procedure** | Toggles chat access for an actor. Input: `actor`, `allowAccess`, optional `ref`. |

## chat.bsky.authFullChatClient (1 file)

| Lexicon ID | Type | Description |
|------------|------|-------------|
| `chat.bsky.authFullChatClient` | **permission-set** | Defines the permission set for a full chat client. Grants access to 30+ RPC methods + CRUD on `chat.bsky.actor.declaration`. |

**Total: ~55 lexicon files**
