# Product Feature Suggestions

## 1. Collaborative Blocklists (Shared Lists + Subscriptions)

Users publish moderation lists and discover/subscribe to lists from trusted community moderators. Subscribed lists sync automatically when the publisher modifies them.

**Why**: #1 unmet need in Bluesky moderation. Eliminates duplicated list-building effort. Differentiator vs. basic clients.

**Scope**: `SubscribedList` model + sync service (periodic diff-based update), list directory/discovery view, subscription management UI. Leverages existing `BlueskyListService`.

---

## 2. Scheduled Moderation Scans

Users define recurring rules ("every Monday, scan new followers, auto-block accounts created <30 days with >500 follows") processed on a schedule via `BGTaskScheduler`.

**Why**: Moves RULYX from reactive tool to proactive service. Huge time saver. Strong differentiator.

**Scope**: `ModerationRule` model + cron scheduling, background task registration, rule evaluation engine, notification on action. Uses existing `ActionQueueStore`.

---

## 3. Moderation Audit Timeline with Rollback

Visual, searchable timeline of every moderation action with bulk undo within a time window. "git log for moderation."

**Why**: Undo confidence unlocks more aggressive use of bulk features. Builds trust. Lowest effort — existing `operationLog` in `ModerationWorkspaceStore`.

**Scope**: Persisted event store, timeline UI with filters, diff-based undo. Leverages `ActionQueueStore` for batch reversal.

---

## Priority

| Feature | Impact | Effort | Differentiation |
|---|---|---|---|
| Audit Timeline + Rollback | High | Low-Medium | Moderate |
| Collaborative Blocklists | Very High | Medium | Strong |
| Scheduled Scans | High | Medium-High | Strong |

**Ship order**: Audit Timeline → Collaborative Blocklists → Scheduled Scans.
