# Design: Post Media / Action Bar Tap Conflict

## Root-cause hypothesis

Static analysis proved wiring and layout structure correct on all surfaces. The defect
is therefore a runtime hit-region inflation of the media `Button`s in `PostEmbedView`.
Two concrete mechanisms are suspected (to be confirmed in reproduction):

### Suspect A — Image grid (`imageGrid`)
```swift
ThumbnailImageView(...)              // Image(uiImage:).resizable() inside
    .aspectRatio(contentMode: .fit)  // single image
    .frame(maxHeight: 300)
    .clipped()
    .clipShape(RoundedRectangle(cornerRadius: 8))
```
A `.resizable()` image with `.aspectRatio(contentMode: .fit)` inside a `LazyVGrid`
flexible column receives an unconstrained height proposal. Its *ideal* size can exceed
the `.frame(maxHeight: 300)` cap. `.clipped()`/`.clipShape` clip drawing, but SwiftUI
`Button` computes its tappable region from the label's layout frame — under
`LazyVGrid` in a `List`, inflated ideal sizes are known to leak hit-testing onto
siblings below (iOS 17/18, also 26 betas).

### Suspect B — Video card (`videoEmbedCard`)
```swift
ThumbnailImageView(...)
    .scaledToFill()        // resizable image, fill
// ZStack, then .frame(height: 200).clipShape(...)
```
`.scaledToFill()` with a resizable image proposes the image's intrinsic size; the
`ZStack` frames at 200pt but the inner image view may extend hit-testing before
`.clipShape` is applied at the outer level.

## Fix strategy

Constrain hit regions explicitly, without changing visuals:

1. **Image grid cells:** after `.clipShape(RoundedRectangle(cornerRadius: 8))`, add
   `.contentShape(RoundedRectangle(cornerRadius: 8))` so the `Button`'s interactive
   region equals the clipped shape. For single images, additionally cap the image
   proposal: `.frame(maxWidth: .infinity)` before `.aspectRatio` is NOT enough — apply
   the `.frame(maxHeight: 300)` BEFORE `.aspectRatio`... (exact modifier order decided
   during reproduction; goal: layout frame == visible frame == hit region).
2. **Video card:** same treatment — `.contentShape(RoundedRectangle(cornerRadius: 8))`
   on the button label, and ensure the thumbnail `ZStack` has `.clipped()` before
   `.clipShape` so drawing and hit-testing both stop at the 200pt frame.
3. **External/Tenor cards:** already fixed-height/fixed-layout HStacks — audit during
   reproduction; add `.contentShape` only if they leak.
4. **Defense in depth (optional):** `.contentShape(Rectangle())` on each
   `PostActionBar` button label so its own region is asserted regardless of neighbors.

## Why `.contentShape`

`.contentShape(_:)` explicitly defines the hit-testing region of a view, overriding
SwiftUI's inferred (and here inflated) region. It is the minimal, visual-no-op fix for
hit-region leaks and the standard remedy for `LazyVGrid`/`.scaledToFill` cases.

## Alternatives considered

- Replace `LazyVGrid` with fixed `HStack` rows — larger refactor, same result;
  only if `.contentShape` proves insufficient in reproduction.
- `.allowsHitTesting(false)` on the image + tap gesture on the clipped container —
  equivalent; `contentShape` on the existing `Button` is simpler.
- Restructure `PostEmbedView` to return an explicit `VStack` — cosmetic; does not fix
  hit regions.

## Verification

1. Reproduce on simulator: timeline, post with 1 image → tap like/reply/quote icons →
   actions fire, carousel stays closed; tap image → carousel opens at index.
2. Repeat for 2–4 image grid, video, external link card, Tenor GIF.
3. Repeat in thread detail, list timeline, profile posts, search results, iPad timeline.
4. No visual regression (media frames, clip radii, ALT badge, spacing identical).
