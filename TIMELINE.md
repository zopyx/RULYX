# Timeline Redesign — Complete Proposal

## 1. UX Audit: Current State

| Area | Current | Problem |
|------|---------|---------|
| **Thread navigation** | `.sheet` modal | Breaks back-swipe flow; no deep navigation |
| **Inline reply expansion** | Static `PostReplyContextView` (non-interactive) | Can't tap to see parent in timeline |
| **Swipe gestures** | None anywhere on posts | Missing primary social interaction pattern |
| **Reply compose** | Full-screen sheet | Heavy for quick replies; should be bottom sheet |
| **Context menu** | Only "mute word" | Industry standard: copy, share, mute, block, report |
| **Inline video** | Only tap-to-fullscreen | No muted autoplay in feed |
| **Thread rendering** | Fixed 16pt indent, gray connector, no author coloring | Visual hierarchy can be improved |
| **Reply collapse** | All replies always shown | No "show N more" or collapsible branches |
| **Polling interval** | 15 seconds | Noticeably slow vs Twitter/X (5-10s) |
| **Post actions** | Full refresh on like/repost | Should be optimistic + local state update |
| **Navigation path** | Flat — all sheets from one screen | Should support deep drill-down (post → thread → profile → post) |

## 2. Design Goals

1. **Push navigation everywhere** — ThreadView moves from sheet to `NavigationStack` path
2. **Inline thread expansion** — Tap reply count or context to expand children inline in the timeline
3. **Swipe actions** — Leading swipe → like (heart), trailing swipe → reply (bubble)
4. **Rich context menu** — Long press shows copy, share, mute user, block, report, translate
5. **Bottom sheet reply** — Reply composer uses `.detents([.medium, .large])` instead of full sheet
6. **Optimistic updates** — Like/repost update UI immediately, sync in background
7. **Inline video autoplay** — Muted autoplay in timeline (configurable)
8. **Visual thread lines** — Author-color-coded connector lines with depth fading
9. **Collapsible replies** — Tap to collapse/expand reply branches
10. **"Show N more"** — For threads with 5+ replies
11. **Faster polling** — Reduce to 8s; add optional WebSocket bridge later
12. **Unified `NavigationPath`** — Type-safe enum-based routing for post/thread/profile

---

## 3. Detailed UX Redesign

### 3.1 Navigation Architecture

**Current:**
```
FeedTimelineView (NavigationStack + sheets)
  ├─ .sheet → ThreadView (its own NavigationStack)
  ├─ .sheet → BlueskyProfileView (wrapped in NavigationStack)
  ├─ .fullScreenCover → ImageCarouselView
  ├─ .fullScreenCover → VideoPlayerView
  └─ .sheet → ComposePostView
```

**Proposed:**
```
TimelineTab (NavigationStack with path)
  ├─ FeedTimelineView
  │   └─ .navigationDestination(for: TimelineRoute.self) → push
  │       ├─ ThreadView(postURI)
  │       │   └─ .navigationDestination(for: TimelineRoute.self) → push
  │       │       ├─ ThreadView (deeper post)
  │       │       └─ BlueskyProfileView
  │       └─ BlueskyProfileView
  │           └─ .navigationDestination(for: TimelineRoute.self) → push
  │               └─ ThreadView (post from profile)
  ├─ .sheet (detents) → ReplyComposerView (reply only)
  ├─ .sheet → ComposePostView (new/quote/edit)
  ├─ .fullScreenCover → ImageCarouselView
  └─ .fullScreenCover → VideoPlayerView
```

**Implementation:**

```swift
enum TimelineRoute: Hashable {
    case thread(postURI: String)
    case profile(actor: BlueskyActor)
}
```

`TimelineTab` holds the `NavigationStack(path: $path)` and `TimelineRoute` enum. Every destination pushes onto this shared path. This gives:
- Free back-swipe navigation
- Deep linking between any depth
- Scroll position preservation

### 3.2 Inline Thread Expansion

**New component: `InlineThreadView`**

When a post has `replyCount > 0`, show a **tappable pill** below the action bar:

```
┌─ Post A ──────────────────────────┐
│ Author  · 2m ago                   │
│                                    │
│ Post text content here...          │
│                                    │
│ ❤ 5  💬 3  🔁 2                   │
│ ┌────────────────────────────┐     │
│ │ Show 3 replies  ▼          │     │
│ └────────────────────────────┘     │
│ (expanded inline replies)          │
└────────────────────────────────────┘
```

**Behavior:**
- Tap the pill → fetch thread via `fetchPostThread(uri:)` with `depth` limited to 2 levels for performance
- Show first N replies inline (N = 3 by default)
- "Show all N replies" button at bottom → push navigates to `ThreadView`
- Inline replies use compact `PostDisplayStyle.threadReply` style (smaller avatar, no full action bar, just reply/like)
- Replies link back to their own `ThreadView` via push navigation

**Performance:** Cache thread data in `ThreadCacheService` (NSCache-based LRU, keyed by post URI, TTL 60s).

### 3.3 Swipe Actions

Add `.swipeActions` to each `PostRowView` in the timeline `List`:

```swift
.swipeActions(edge: .leading, allowsFullSwipe: true) {
    Button { handleLike(entry) } label: {
        Image(systemName: entry.post.isLikedByMe ? "heart.fill" : "heart")
    }
    .tint(entry.post.isLikedByMe ? .gray : .pink)
}

.swipeActions(edge: .trailing, allowsFullSwipe: true) {
    Button { handleReply(entry) } label: {
        Image(systemName: "arrowshape.turn.up.left")
    }
    .tint(.blue)
}
```

Haptic feedback on both actions (`UIImpactFeedbackGenerator`).

### 3.4 Rich Context Menu

Replace the minimal `.contextMenu` with a full one:

```swift
.contextMenu {
    Button { UIPasteboard.general.string = text }
        label: { Label("Copy text", systemImage: "doc.on.doc") }
    Button { showShareSheet(entry) }
        label: { Label("Share", systemImage: "square.and.arrow.up") }
    Divider()
    Button { muteUser(entry) }
        label: { Label("Mute @\(handle)", systemImage: "eye.slash") }
    Button { blockUser(entry) }
        label: { Label("Block @\(handle)", systemImage: "hand.raised") }
    Divider()
    Button { reportPost(entry) }
        label: { Label("Report", systemImage: "exclamationmark.bubble") }
    Button { translate(entry) }
        label: { Label("Translate", systemImage: "globe") }
}
```

Keep the moderation gear menu in `PostActionBar` (block all likers, classify, add to list) — distinct functionality for this app's moderation purpose.

### 3.5 Bottom Sheet Reply Composer

Change reply composition from `.sheet` (full) to `.sheet` with `.detents`:

```swift
.sheet(item: $composeContext) { context in
    if context.isReply {
        ReplyComposerView(
            account: context.account,
            appPassword: context.appPassword,
            blueskyClient: blueskyClient,
            parentURI: context.parentURI,
            parentCID: context.parentCID,
            rootURI: context.rootURI,
            rootCID: context.rootCID,
            onComplete: { refreshAfterAction() }
        )
        .presentationDetents([.medium, .large])
    }
}
```

**New `ReplyComposerView`**: Lightweight — just text field + character count + submit button + parent preview. Blurs the background below. No image/GIF/thread-gate in quick reply (those remain in full `ComposePostView`).

Keep full `ComposePostView` for new posts, quotes, and edits.

### 3.6 Optimistic Updates

**Current:** Like/repost → API call → full `refresh()` → entire timeline re-fetched.

**Proposed:**
1. Immediately toggle `entry.post.isLikedByMe` locally
2. Animate the heart icon (spring scale 1→1.3→1)
3. Fire API call in background
4. If API fails, revert local state with a brief error toast
5. Track `pendingOperations: Set<String>` to prevent duplicate API calls during optimistic state

This eliminates the full refresh on every interaction. `refresh()` is still called only on pull-to-refresh or polling cycles.

### 3.7 Inline Video Autoplay

Add a configuration option (default: Wi-Fi only) to auto-play muted video in the timeline:

```swift
// In PostEmbedView, for video embeds:
if shouldAutoplayVideo {
    InlineVideoPlayer(url: playlist, isMuted: true)
        .frame(idealHeight: 200)
        .onAppear { player.play() }
        .onDisappear { player.pause() }
} else {
    // Current static thumbnail + play button
}
```

**Store setting:** `UserDefaults.standard.bool(forKey: "autoplayVideos")` with default `true` on Wi-Fi.

### 3.8 ThreadView Rendering Enhancements

| Change | Detail |
|--------|--------|
| **Author-colored connector** | Hash DID to a consistent pastel color for the vertical thread line |
| **Collapsible branches** | Tap a reply row to collapse/expand its children. Show "+N" badge when collapsed |
| **"Show N more replies"** | After 4 direct replies, show "+8 more replies" button that loads next page |
| **Depth-limited indentation** | Cap at depth 5 (~80px). Beyond that, flatten to depth=5 with subtle "earlier" indicator |
| **Smooth animations** | `.matchedGeometryEffect` for reply expansion; `.transition(.slide)` for new replies |

### 3.9 Real-time Updates

- Reduce polling interval from 15s → **8s**
- Increase limit from 5 → **10** for the poll check
- Add **activity indicator** in toolbar when polling is active (subtle dot)
- Keep the "N new posts" banner pattern (it's standard)
- **Future option:** AT Protocol `com.atproto.sync.subscribeRepos` WebSocket firehose via `URLSessionWebSocketTask`

### 3.10 Composer Improvements

- **Auto-save drafts** to `UserDefaults` when text exists and composer is dismissed
- **Draft indicator** on the compose button (dot badge) when unsaved draft exists
- **Character count** turns orange at 260, red at 300 (Bluesky limit is 300)

---

## 4. Backend / Data Flow Changes

### 4.1 New / Modified Files

| File | Action | Description |
|------|--------|-------------|
| `Sources/Features/Timeline/TimelineRoute.swift` | **NEW** | `enum TimelineRoute: Hashable` with `thread`, `profile` cases |
| `Sources/Features/Timeline/ThreadView.swift` | MOVE + REFACTOR | Move from `Lists/Profile/` to `Timeline/`; remove its `NavigationStack` wrapper; use shared NavigationPath |
| `Sources/Features/Timeline/InlineThreadView.swift` | **NEW** | Component for inline reply expansion in the timeline list |
| `Sources/Features/Timeline/ReplyComposerView.swift` | **NEW** | Lightweight bottom-sheet reply composer |
| `Sources/Features/Timeline/FeedTimelineView.swift` | REFACTOR | Swipe actions, context menu, inline expansion, navigation path |
| `Sources/Features/Timeline/FeedTimelineViewModel.swift` | REFACTOR | Optimistic updates, cache integration, faster polling |
| `Sources/Features/Timeline/TimelineTab.swift` | REFACTOR | Hold `NavigationStack(path:)` with `TimelineRoute` |
| `Sources/Shared/Components/Posts/PostRowView.swift` | REFACTOR | Accept `style: .threadReply` for inline replies |
| `Sources/Shared/Components/Posts/PostReplyContextView.swift` | REFACTOR | Make parent post URI tappable (navigate to parent) |
| `Sources/Shared/Components/Posts/PostActionBar.swift` | REFACTOR | Add `onShowThread` callback for reply count tap |
| `Sources/Shared/Components/Posts/PostDisplayStyle.swift` | REFACTOR | Add `.threadReply` case |
| `Sources/Domain/Services/ThreadCacheService.swift` | **NEW** | LRU cache for thread fetch results (NSCache, keyed by URI, 60s TTL) |
| `Sources/Features/Timeline/ThreadViewModel.swift` | EXTRACT | Extract from ThreadView.swift into its own file |

### 4.2 Data Flow Diagram

```
                        ┌─────────────────────┐
                        │   ThreadCacheService  │
                        │  (NSCache<URI, Node>) │
                        └──────┬──────────────┘
                               │ cache hit/miss
                               ▼
FeedTimelineViewModel ─────► LiveBlueskyClient
  │   │   │                    │
  │   │   │                    ├─ fetchPostThread(uri, depth: 2)
  │   │   │                    ├─ fetchTimeline()
  │   │   │                    └─ createLike / createRepost
  │   │   │
  │   ▼   ▼
  │  entries[]  (optimistic local state)
  │  pendingOps: Set<String>
  │
  ▼
FeedTimelineView
  │  .navigationDestination(for: TimelineRoute.self)
  │     → ThreadView (push, not sheet)
  │  .swipeActions (like/reply)
  │  .contextMenu (rich)
  │  InlineThreadView (inside list row)
  ▼
ThreadView (no NavigationStack wrapper)
  │  shares same NavigationStack path
  │  can push more ThreadViews or profiles
  ▼
ReplyComposerView (.sheet, .detents)
  │  lightweight, just text + parent preview
```

### 4.3 Optimistic Update Flow

```
User taps like ❤️
  → viewModel.toggleLike(entry)
    → entry.post.isLikedByMe = !old (LOCAL)
    → entry.post.likeCount ±= 1 (LOCAL)
    → pendingOps.insert(uri + "like")
    → objectWillChange.send()
    → Task {
        try await client.createLike/deleteRecord
        pendingOps.remove(uri + "like")
      } catch {
        // revert local state
        entry.post.isLikedByMe = old
        entry.post.likeCount ∓= 1
        // show error toast
      }
```

### 4.4 Thread Cache

```swift
@MainActor
final class ThreadCacheService {
    static let shared = ThreadCacheService()
    private let cache = NSCache<NSString, CacheEntry>()

    struct CacheEntry {
        let thread: ThreadNode
        let timestamp: Date
    }

    func get(uri: String) -> ThreadNode? {
        guard let entry = cache.object(forKey: uri as NSString),
              Date().timeIntervalSince(entry.timestamp) < 60 else { return nil }
        return entry.thread
    }

    func set(uri: String, thread: ThreadNode) {
        cache.setObject(CacheEntry(thread: thread, timestamp: Date()), forKey: uri as NSString)
    }

    func invalidate(uri: String) {
        cache.removeObject(forKey: uri as NSString)
    }
}
```

---

## 5. Implementation Plan (Phased)

### Phase 1: Navigation Foundation (~3-4 files, ~300 lines changed)
- Create `TimelineRoute.swift`
- Refactor `TimelineTab.swift` to hold `NavigationStack(path:)`
- Move `ThreadView` from sheet to push navigation
- Remove `NavigationStack` wrapper from `ThreadView`
- Update `FeedTimelineView` to use `.navigationDestination`

### Phase 2: Swipe Actions + Context Menu (~2 files, ~80 lines changed)
- Add `.swipeActions` to post rows in `FeedTimelineView`
- Enhance `.contextMenu` with copy, share, mute, block, report, translate
- Wire all new actions to existing handlers

### Phase 3: Optimistic Updates (~1 file, ~60 lines changed)
- Refactor `FeedTimelineViewModel.toggleLike()` / `toggleRepost()`
- Add `pendingOps` tracking
- Local state mutation + background sync
- Remove full `refresh()` after like/repost

### Phase 4: Inline Thread Expansion + Thread Enhancements (~3-4 files, ~400 lines new)
- Create `InlineThreadView.swift`
- Create `ThreadCacheService.swift`
- Create the "Show N replies" pill component
- Add collapsible branches to `ThreadView`
- Author-colored connector lines
- "Show N more" reply loading

### Phase 5: Reply Composer + Video Autoplay (~2-3 files, ~200 lines new)
- Create `ReplyComposerView.swift` (lightweight bottom sheet)
- Add inline video autoplay with setting

### Phase 6: Polish + Performance (across all files)
- Faster polling (15s → 8s)
- Smooth animations (spring for like, slide for reply expansion)
- Draft auto-save
- Haptic feedback on swipe success
- Scroll position restoration after navigation back

---

## 6. Key Design Decisions

1. **Thread in timeline: fetch on tap vs prefetch?** — Fetch-on-tap to avoid N+1 API calls on timeline load. Cache after first fetch.

2. **Reply composer: how much functionality?** — Minimal bottom sheet for quick replies (text only); redirect to full `ComposePostView` for media/thread-gate. Keeps the quick action genuinely quick.

3. **Video autoplay: Wi-Fi only or always?** — Wi-Fi only with a setting. Matches user expectations and avoids data usage complaints.

4. **Inline thread expansion depth?** — Fetch with `depth: 1` and `parentHeight: 1` from the API (Bluesky supports these params). Show first 2 levels of replies inline; deeper levels require tapping into full ThreadView.

5. **Profile navigation: sheet vs push?** — Push for consistency. Profiles open inline in the same `NavigationStack`. Deprecate the sheet pattern for profiles.

6. **How to handle the "Reply to" context in timeline?** — Make `PostReplyContextView` tappable: tapping navigates to the parent post's `ThreadView`. Show a compact preview of the parent.

---

## 7. Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Push navigation breaks existing sheet-based flows | Carefully audit all `ThreadView` and `BlueskyProfileView` presentations. Add both `navigationDestination` and keep sheet as fallback during migration |
| Optimistic updates race with polling | Use `pendingOps` set to suppress poll-based overwrites of optimistically mutated entries |
| Inline thread expansion API cost | Cache aggressively (60s TTL). Only expand when user taps. Limit depth to 2 levels |
| Bottom sheet reply loses state on dismiss | Auto-save draft text to UserDefaults. Restore on re-open |
| Performance with deep `NavigationStack` path | Keep `NavigationStack` path depth reasonable. Consider `.stack` navigation stack style |
