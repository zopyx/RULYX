## Why

The media scan on profile view is slow — it fetches all post pages sequentially, which for profiles with 1000+ posts takes many seconds. The result is also not cached, so every profile re-visit rescans from scratch.

## What Changes

- Parallelize page fetching in `countMedia()` using `withTaskGroup`
- Cap scan depth at 1000 posts (10 pages of 100)
- Cache media counts per profile in `BlueskyAPICache`

## Capabilities

### New Capabilities
- `media-scan-optimization`: Faster profile media scanning with parallel fetching, depth limit, and caching.
