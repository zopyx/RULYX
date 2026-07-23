# Tasks: Post Media / Action Bar Tap Conflict

## 1. Reproduction (confirm root cause)
- [ ] 1.1 Run app in simulator (preview account OK), open timeline with a media post
- [ ] 1.2 Confirm which embed types inflate the hit region (single image, grid, video, external, Tenor) — e.g. via slow tap near the action bar top edge
- [ ] 1.3 Note iOS version / device where reproduced

## 2. Fix (PostEmbedView)
- [x] 2.1 `imageGrid()`: `.contentShape(RoundedRectangle(cornerRadius: 8))` after `.clipShape` on every image cell — button hit region pinned to the visible frame
- [x] 2.2 `videoEmbedCard()`: added missing `.clipped()` before `.clipShape`, plus `.contentShape(RoundedRectangle(cornerRadius: 8))`
- [x] 2.3 External + Tenor cards: `.contentShape(RoundedRectangle(cornerRadius: 12))` on both cards (same leak vector via `.scaledToFill()` thumbnails; applied uniformly, visual no-op)
- [ ] 2.4 Optional hardening: `.contentShape(Rectangle())` on `PostActionBar` button labels (only if 3.1 still shows issues)

## 3. Verification
- [ ] 3.1 Manual: like/reply/repost/quote fire on media posts; media tap still opens carousel/player
- [ ] 3.2 All surfaces: timeline, thread, list timeline, profile posts, search, notifications (card), iPad
- [ ] 3.3 Visual parity: no layout/clip/spacing changes
- [x] 3.4 Build + `swiftformat --lint` + `swiftlint` clean for touched files
- [x] 3.5 `openspec validate post-media-action-bar-conflict --json`
