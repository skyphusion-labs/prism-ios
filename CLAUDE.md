# CLAUDE.md -- prism-ios

Guidance for agents working in this repository.

## What this is

**AGPL iOS client for Prism.** Shared Swift package (`PrismKit`) plus a SwiftUI app shell
(`App/` + `Prism.xcodeproj`) for login, model pick, and chat against the playground Worker.

**Status:** kit 0.3.1 + app with dual backend, streaming, and Keychain session restore.
Aviation-grade `main` (PR + CI for the package). Next: StoreKit top-up.

## Related

| Repo | Role |
| --- | --- |
| [prism](https://github.com/skyphusion-labs/prism) | Inference playground Worker (`play.skyphusion.org`) |
| [prism-control-plane](https://github.com/skyphusion-labs/prism-control-plane) | Commercial plane (`play-proxy.skyphusion.org`) |
| [prism-android](https://github.com/skyphusion-labs/prism-android) | Sibling Android kit |

## Layout

- `Sources/PrismKit` -- API clients + models
- `Tests/PrismKitTests` -- XCTest + URLProtocol mocks
- `App/` -- SwiftUI (`PrismApp`, `AppState`, login/chat/settings)
- `project.yml` -- XcodeGen; regenerate with `xcodegen generate`
- `Package.swift` -- SPM library (iOS 16+, macOS 13+)

## Clients

- **`PrismClient`** -- playground Worker. Public mode session cookie after login. `chatStreamEvents` for incremental SSE.
- **`ControlPlaneClient`** -- metered plane, `Bearer pcp_…`. Enroll, `me` / models, chat + `chatCompletionsStream` (OpenAI SSE).
- **`SSEParser`** -- playground `{type:delta}` and OpenAI `choices[].delta.content` frames.
- **`SecretStore` / `KeychainSecretStore`** -- plane device key, playground session cookie, URL prefs (memory store on Linux CI).
- **Session restore** -- `PrismClient.exportSessionToken` / `restoreSessionToken` for `__Host-prism_session`.

## Commands

```bash
swift test                 # package tests (CI)
xcodegen generate          # refresh Prism.xcodeproj from project.yml
xcodebuild -scheme Prism -destination 'generic/platform=iOS Simulator' build
```

## CI

- `.github/workflows/ci.yml` -- `swift test` on Ubuntu (package only)
- App build is local Xcode; do not require Linux iOS simulators

## Conventions

- No em-dashes (U+2014) or en-dashes (U+2013); use commas, semicolons, or `--`.
- Conventional Commits. License: AGPL-3.0-only.
- After editing `project.yml` or app targets, run `xcodegen generate` and commit the xcodeproj.

## Crew + identity

Crew work as their own identity (`sudo -u <member> bash -lc '...'`). Conrad laptop commits:
`Conrad Rockenhaus <conrad@skyphusion.org>`.
