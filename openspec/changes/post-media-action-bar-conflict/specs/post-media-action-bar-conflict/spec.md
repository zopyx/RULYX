# Spec: Post Media / Action Bar Tap Conflict

## ADDED Requirements

### Requirement: Action bar buttons remain tappable on posts with media
The action bar (`PostActionBar`) SHALL receive and handle taps on every post,
regardless of whether the post contains media (images, video, external link card,
or Tenor GIF embed).

#### Scenario: Like on a post with a single image
- GIVEN a timeline showing a post with one embedded image
- WHEN the user taps the like (heart) icon below the post
- THEN the like action fires (optimistic like toggle)
- AND the full-screen image carousel does NOT open

#### Scenario: Reply on a post with a video
- GIVEN a timeline showing a post with an embedded video
- WHEN the user taps the reply icon below the post
- THEN the reply composer opens
- AND the video player does NOT open

#### Scenario: Quote/repost on a post with a 2–4 image grid
- GIVEN a timeline showing a post with multiple embedded images
- WHEN the user taps the quote or repost icon
- THEN the quote composer / repost action fires
- AND no media viewer opens

### Requirement: Media hit region equals its visible frame
The tappable region of every media element in `PostEmbedView` SHALL be exactly its
visible (clipped) frame — it MUST NOT extend over sibling content (action bar,
author row, neighboring posts).

#### Scenario: Tap below the media area
- GIVEN a post whose media renders with a clipped frame
- WHEN the user taps in the vertical gap between media bottom and the next row
  (i.e. on the action bar icons)
- THEN the tap is delivered to the action bar button under the tap point

#### Scenario: Media tap still works
- GIVEN a post with embedded media
- WHEN the user taps directly on the media thumbnail
- THEN the media viewer opens (image carousel at the tapped index / video player)

### Requirement: Behavior is identical on all post surfaces
The fix SHALL apply to every surface rendering `PostRowView`/`PostEmbedView`:
timeline, thread detail, list timeline, profile posts, search results,
notifications (card style), iPad variants.

#### Scenario: iPad timeline
- GIVEN the iPad timeline showing a post with media
- WHEN the user taps the like icon
- THEN the like action fires without opening the media viewer
