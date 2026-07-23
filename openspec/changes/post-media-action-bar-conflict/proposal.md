# Proposal: Post Media / Action Bar Tap Conflict

## Problem

When a post with media (images, video, or external/GIF embed) is displayed, the action
bar icons below the post (reply, repost, like, quote) do NOT respond to taps. Instead,
the tap opens the media (full-screen image carousel or video player). Reported on EVERY
surface that renders posts with media (timeline, thread detail, list timeline, profile
posts, search results).

## Validation findings (static analysis, completed)

All shared components were audited end-to-end:

- `PostRowView.standardContent` — media embed and `PostActionBar` are siblings in a
  `VStack(spacing: 4)`; no overlap in the layout tree.
- `PostEmbedView` — every media element is wrapped in its own `Button` with
  `.buttonStyle(.plain)`, `.clipped()` and `.clipShape(...)`; no container-level gesture.
- `PostActionBar` — all icons are plain `Button`s with `.buttonStyle(.plain)`.
- `TimelinePostRow`, `ThreadView`, `FeedTimelineView`, `ListTimelineView`,
  `UserPostsView`, search rows, `NotificationRow` — no row-level tap gesture, no
  wrapping `Button`, no `NavigationLink` around rows.
- Media presentation is uniformly `.fullScreenCover(item:)` driven by
  `onTapImage`/`onPlayVideo` callbacks; all `PostRowCallbacks` are labeled-argument
  inits and every call site wires them correctly (no miswiring possible/found).
- `ImageCarouselView`, `ThumbnailImageView`, `PostTextContent`,
  `PostLikerActionsViewModifier` — no gesture or hit-area leaks.

**Conclusion:** The conflict is not a wiring/structure bug — it is a runtime
hit-region defect in the shared media embed rendering (`PostEmbedView` image grid /
video button), i.e. the media `Button`'s tappable region extends beyond its visible
frame and covers the action bar below it. Prime suspects:

1. `imageGrid()` — `LazyVGrid` + `.aspectRatio(contentMode:)` + `.frame(maxHeight:)`
   inside `List` rows: resizable images with unconstrained proposals can report ideal
   sizes larger than the clipped frame, inflating the `Button` hit region.
2. The video `Button` wraps a `ZStack` with `.scaledToFill()` thumbnail
   (`.frame(height: 200)`, `.clipShape`) — `.scaledToFill()` content with a resizable
   image can similarly inflate hit-testing beyond the clip shape.

## Goal

Tapping reply/repost/like/quote on a post with media MUST trigger the action — never
the media. Tapping the media itself MUST still open the carousel/player. The media
`Button`'s hit region MUST be exactly its visible frame.

## Scope

- In scope: `PostEmbedView` (image grid, video card, external/Tenor cards),
  `PostActionBar` (hit-region hardening if needed).
- Out of scope: redesigning the media layout, changing presentation mechanics
  (`.fullScreenCover` stays), touch handling in `ImageCarouselView`/`VideoPlayerView`.

## Approach

1. Reproduce at runtime (simulator, timeline with a media post) and confirm which
   embed type(s) inflate the hit region.
2. Constrain the media `Button` hit region to its visible frame
   (`.contentShape(RoundedRectangle(cornerRadius:))` on the button label after
   `.clipShape`, explicit size proposals for resizable images), keeping visuals identical.
3. Regression-check all surfaces (all use the shared `PostRowView`/`PostEmbedView`).

## Rollback

Pure view-layer change; revert the single commit. No data/model/migration impact.
