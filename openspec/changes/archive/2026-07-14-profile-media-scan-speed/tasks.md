## ADDED Requirements

- [ ] 1.1 Rewrite `countMedia()` to use `withTaskGroup` for parallel page fetching (up to 3 concurrent pages)
- [ ] 1.2 Add depth limit of 1000 posts (stop after 10 pages)
- [ ] 1.3 Cache media counts in `BlueskyAPICache` with 5-minute TTL per profile DID
- [ ] 1.4 Check cache before scanning; write cache after scan completes
