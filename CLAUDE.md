# CLAUDE.md -- prism-ios

Guidance for agents working in this repository.

## What this is

**AGPL iOS client kit for Prism.** Shared Swift package (`PrismKit`) for chat and
(later) multimodal + subscription UX. Goal is easier access to a curated model set
with cost-recovery hosting, not a closed app.

**Status:** library client lives here (`PrismClient` + `ControlPlaneClient`). Xcode
SwiftUI app is the next slice. Aviation-grade `main` (PR + CI + coverage).

## Related

| Repo | Role |
| --- | --- |
| [prism](https://github.com/skyphusion-labs/prism) | Inference playground Worker (`play.skyphusion.org`) |
| [prism-control-plane](https://github.com/skyphusion-labs/prism-control-plane) | Commercial multi-tenant plane (`play-proxy.skyphusion.org`) |
| [prism-android](https://github.com/skyphusion-labs/prism-android) | Sibling Android kit |

## Layout

- `Sources/PrismKit` -- API clients + models
- `Tests/PrismKitTests` -- XCTest + URLProtocol mocks
- `Package.swift` -- SPM (iOS 16+, macOS 13+)

## Clients

- **`PrismClient`** -- playground Worker. Public mode uses `__Host-prism_session` cookie
  after `login`/`signup`. Methods: `health`, `models`, `signup`, `login`, `logout`,
  `chat`, `chatStream` / `chatStreamText`.
- **`ControlPlaneClient`** -- metered plane. `Bearer pcp_…` device key. Methods:
  `health`, `enroll`, `me`, `chatCompletions` / `chat`. Normative contract:
  control-plane `docs/CONTRACT.md` + `openapi.yaml`.

## Commands

```bash
swift test   # library tests (Ubuntu CI with setup-swift; macOS CLI tools need Xcode for XCTest)
```

## CI

- `.github/workflows/ci.yml` -- push/PR to `main`: `swift test` on `ubuntu-latest`
- Coverage / CodeQL workflows present; public repo uses GitHub-hosted runners only (fork-safe)

## Next (product)

1. Keychain wrapper for control-plane device keys (and optional session token persistence).
2. SwiftUI app target: login/catalog/chat against playground and/or plane.
3. Streaming via `URLSession.bytes` (incremental) instead of full-body SSE buffer.
4. StoreKit / entitlement (commercial) -- after product rules settle.

## Conventions

- No em-dashes (U+2014) or en-dashes (U+2013) in source or docs; use commas, semicolons, or `--`.
- Handle / username default: `skyphusion`.
- Conventional Commits. License: AGPL-3.0-only.

## Crew + identity

Crew work as their own identity (`sudo -u <member> bash -lc '...'`). Conrad laptop commits:
`Conrad Rockenhaus <conrad@skyphusion.org>`.
