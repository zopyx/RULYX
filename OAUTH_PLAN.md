# OAuth Implementation Plan

## Overview

Bluesky's AT Protocol now supports OAuth 2.0 Authorization Code flow + PKCE + DPoP as an alternative to the legacy `com.atproto.server.createSession` (app password) flow. This plan implements both, letting the user choose which auth method to use when adding an account.

**Why OAuth?** The user never shares credentials with the app — they authenticate directly with their PDS via a web browser. Tokens are DPoP-bound and provide better security.

**Current status of `createSession`:** Not yet deprecated, but OAuth is the recommended path for apps with end-user login flows.

## Architecture

### How the user chooses

In `AddAccountView`, a segmented control at the top:

```
[ App Password ] [ Sign in with Browser ]
```

- **App Password** — existing form (handle + password, 2FA support)
- **Sign in with Browser** — handle-only, opens `ASWebAuthenticationSession` to the PDS's OAuth page

### Runtime routing

```
LiveBlueskyClient
  └── AuthSessionProvider (protocol)
        ├── LegacyAuthSessionProvider — existing Bearer JWT logic
        └── OAuthAuthSessionProvider — DPoP-bound tokens + refresh
```

Each `AppAccount` has an `authMethod: AuthMethod` property (`.password` | `.oauth`). `LiveBlueskyClient` checks the active account's `authMethod` and delegates to the correct provider. All 50+ API methods are covered transparently.

## Phases

### Phase 1 — Foundation: OAuth Client Infrastructure

Core cryptographic and protocol primitives, no app behavior changes.

| File | What |
|------|------|
| `Sources/Domain/Services/OAuthPKCE.swift` | PKCE verifier/challenge generation (S256) |
| `Sources/Domain/Services/OAuthDPoP.swift` | ES256 keypair management, DPoP proof JWT signing |
| `Sources/Domain/Services/OAuthClientMetadata.swift` | Client metadata JSON document model + encoder |
| `project.yml` | Add `CFBundleURLTypes` for OAuth callback scheme |
| Hosted JSON | `oauth-client-metadata.json` at a public HTTPS URL |

### Phase 2 — OAuth Session Model & Token Storage

Models and storage for OAuth tokens plus well-known endpoint resolvers.

| File | What |
|------|------|
| `Sources/Domain/Models/OAuthSession.swift` | `OAuthSession` model (tokens, DPoP key ref, nonces, expiry) |
| `Sources/Domain/Services/OAuthTokenStore.swift` | Keychain persistence for tokens and DPoP keys |
| `Sources/Domain/Services/OAuthEndpointResolver.swift` | Well-known metadata fetchers for AS and resource server |
| `Sources/Domain/Services/OAuthTokenRefresher.swift` | Token refresh with DPoP proof, single-use rotation, concurrency guard |

### Phase 3 — OAuth Authorization Flow & UI

The actual login flow via browser.

| File | What |
|------|------|
| `Sources/Domain/Services/OAuthAuthorizationFlow.swift` | PAR request, ASWebAuthenticationSession orchestration |
| `Sources/Domain/Services/OAuthTokenExchange.swift` | Callback handling, code exchange for tokens |
| `Sources/Features/Accounts/OAuthSignInView.swift` | Handle input, "Sign in with Browser" button, ASWebAuthenticationSession |
| `Sources/Features/Accounts/AddAccountView.swift` | Segmented control at top: App Password / Browser |
| `Sources/App/AppDependencies.swift` | Wire OAuth services into DI container |

### Phase 4 — DPoP-Authenticated Requests

All XRPC calls use DPoP tokens when the account is OAuth-based.

| File | What |
|------|------|
| `Sources/Domain/Services/OAuthRequestAdapter.swift` | DPoP header injection, nonce retry handling |
| `Sources/Domain/Services/AuthSessionProvider.swift` | Protocol with two implementations |
| `Sources/Domain/Services/LegacyAuthSessionProvider.swift` | Wraps existing BlueskySessionService |
| `Sources/Domain/Services/OAuthAuthSessionProvider.swift` | Wraps OAuthSession + DPoP |
| `Sources/Domain/Services/BlueskySessionService.swift` | No major changes — wrapped by LegacyAuthSessionProvider |
| `Sources/Domain/Services/LiveBlueskyClient.swift` | Route through AuthSessionProvider |

### Phase 5 — Coexistence & Migration

Both auth methods work side by side.

| File | What |
|------|------|
| `Sources/Domain/Models/AppAccount.swift` | Add `authMethod: AuthMethod` |
| `AccountStore` | Dual-path add/remove/restore for both account types |
| `PreviewBlueskyClient` | Mock OAuth sessions in previews |
| Settings | Show auth method per account |

## Key Considerations

- **Client metadata hosting**: OAuth spec requires `client_id` to be a public HTTPS URL. For development, `http://localhost/` is allowed as an exception. For production, host a static JSON at a well-known URL (e.g., `https://rulypx.app/oauth-client-metadata.json`).
- **Eurosky / other PDSes**: Fully supported — OAuth metadata is discovered dynamically from each PDS's `/.well-known/` endpoints. No PDS-specific code needed.
- **Screenshot tests**: Remain on the legacy password path (ASWebAuthenticationSession doesn't work in automated UI tests).
- **Transitional scopes**: Phase 1–5 uses `transition:generic` for parity with app password permissions. Future migration to granular permission sets is out of scope.
