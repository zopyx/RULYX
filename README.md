# who-blocks-me

Find out who blocks you on Bluesky, split by whether you block them back. Optionally block them all back in parallel or sync them to a moderation list.

## Purpose

Bluesky does not provide a native "who blocked me" API. This project uses the [Clearsky](https://clearsky.app) firehose index to discover accounts blocking you, then checks your own block list to split the results into two groups:

- **Mutual blocks** — accounts blocking you that you also block
- **One-way blocks** — accounts blocking you that you do *not* block back

You can optionally:
- Block all one-way blockers with a single command.
- Create (or reuse) a Bluesky curation list and add every blocker to it.

## What's inside

| File / directory | Language | Purpose |
|------------------|----------|---------|
| `who-blocks-me.py` | Python 3.12+ | Main tool — discovers blockers, optionally blocks back or creates lists. |
| `blocks-to-list.py` | Python 3.12+ | Lists every account *you* block and optionally syncs them to a **moderation list** (modlist). |
| `who-blocks-me-rs/` | Rust | Rust port of `who-blocks-me.py` with the same feature set. |

Both Python scripts are self-contained [`uv` run scripts](https://docs.astral.sh/uv/guides/scripts/) — no virtualenv required.

---

## Python implementation

### Prerequisites

- [uv](https://docs.astral.sh/uv/) installed
- A Bluesky **app password** (not your main password)

### `who-blocks-me.py`

#### Usage

```bash
# Preview only (writes blocks.json)
uv run who-blocks-me.py yourhandle.bsky.social your-app-password

# Preview + block all one-way blockers back
uv run who-blocks-me.py yourhandle.bsky.social your-app-password --block-back

# Custom parallelism (default 10 concurrent block requests)
uv run who-blocks-me.py yourhandle.bsky.social your-app-password --block-back --block-workers 16

# Create a curation list and add all one-way blockers
uv run who-blocks-me.py yourhandle.bsky.social your-app-password --list "People Blocking Me"

# Block back AND create a curation list
uv run who-blocks-me.py yourhandle.bsky.social your-app-password --block-back --list "People Blocking Me"

# Verbose logging
uv run who-blocks-me.py yourhandle.bsky.social your-app-password -v
```

#### Output (`blocks.json`)

```json
{
  "i_block_them": [
    {
      "did": "did:plc:...",
      "handle": "alice.bsky.social",
      "blocked_date": "2026-05-01T16:33:49.790000+00:00"
    }
  ],
  "i_dont_block_them": [
    {
      "did": "did:plc:...",
      "handle": "bob.bsky.social",
      "blocked_date": "2026-04-30T12:53:08.586908+00:00"
    }
  ]
}
```

---

### `blocks-to-list.py`

This companion script does the *reverse* — it lists every account **you** block and can mirror that list to a Bluesky **moderation list** (a "modlist" that other users can subscribe to).

#### Usage

```bash
# Just export your block list to my-blockings.json
uv run blocks-to-list.py yourhandle.bsky.social your-app-password

# Ignore cache and fetch fresh data
uv run blocks-to-list.py yourhandle.bsky.social your-app-password --no-cache

# Create (or reuse) a moderation list named "My Block List" and show its members
uv run blocks-to-list.py yourhandle.bsky.social your-app-password --moderation-list "My Block List"

# Actually populate the moderation list with accounts you block
uv run blocks-to-list.py yourhandle.bsky.social your-app-password --moderation-list "My Block List" --add-to-list
```

#### Output

- `my-blockings.json` — every account you block with resolved handles.
- `my-blockings-listed.json` — final state of the moderation list after additions.

---

## Rust implementation

`who-blocks-me-rs/` is a Cargo project using `tokio` and `reqwest` that implements the same workflow as `who-blocks-me.py`.

### Build

```bash
cd who-blocks-me-rs
cargo build --release
```

### Usage

```bash
# Preview only
./target/release/who-blocks-me yourhandle.bsky.social your-app-password

# Block back all one-way blockers
./target/release/who-blocks-me yourhandle.bsky.social your-app-password --block-back

# Custom parallelism (default 4 concurrent block requests)
./target/release/who-blocks-me yourhandle.bsky.social your-app-password --block-back --block-workers 8

# Create a curation list and add all one-way blockers
./target/release/who-blocks-me yourhandle.bsky.social your-app-password --list "People Blocking Me"

# Block back AND create a curation list
./target/release/who-blocks-me yourhandle.bsky.social your-app-password --block-back --list "People Blocking Me"

# Verbose
./target/release/who-blocks-me yourhandle.bsky.social your-app-password -v
```

---

## Architecture

1. **Resolve handle → DID** via Clearsky anonymous API.
2. **Resolve DID → PDS** via `plc.directory` or `did:web` well-known document.
3. **Authenticate** with the PDS (falling back to `bsky.social`).
4. **Fetch own block list** via `app.bsky.graph.getBlocks` (paginated, 100/page).
5. **Fetch blockers** via Clearsky `single-blocklist` endpoint (paginated, 100/page).
6. **Resolve handles** for unknown DIDs in batches of 25 via `app.bsky.actor.getProfiles`.
7. **Compare** and emit two groups: mutual blocks vs. one-way blocks.
8. **Optional mutations** — block back or add to a list.

---

## Caching

Both Python scripts share a cache directory at `~/.cache/who-blocks-me` (powered by `diskcache`):

- Clearsky DID lookups
- DID documents (PDS endpoints)
- Handle → DID and DID → handle mappings
- `blocks-to-list.py` also caches the full block list for 1 hour.

The Rust binary uses a local `cache.json` file in the working directory.

---

## Getting an app password

Do **not** use your main account password. Generate an app password in Bluesky:

**Settings → Privacy & Security → App Passwords**

---

## Safety notes

- The `--block-back` flag creates real block records on your account. Review `blocks.json` first if unsure.
- The `--add-to-list` flag in `blocks-to-list.py` modifies a moderation list on your account.
- Progress bars show real-time status for all phases.
