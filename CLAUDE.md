# CLAUDE.md -- prism-ios

Guidance for agents working in this repository.

## What this is

**AGPL iOS client for Prism.** Shared Swift package (`PrismKit`) plus a SwiftUI app shell
(`App/` + `Prism.xcodeproj`) branded **Prism for iOS**.

**Status:** **1.0.0** (build 26+; trust Xcode MARKETING_VERSION / git tag `v1.0.0`). ASC app
`6798391677`, bundle `org.skyphusion.prism`. Plane: **prism-control-plane 1.0.0** (redeem path since
0.4.36 Production JWS). Sibling Android **1.0.0**. Release notes: `docs/RELEASE-1.0.md`. README has
estate Mermaid + full catalog tables. Aviation-grade `main`.

## Related

| Repo | Role |
| --- | --- |
| [prism](https://github.com/skyphusion-labs/prism) | Playground Worker (`play.skyphusion.org`) **1.0.0** |
| [prism-control-plane](https://github.com/skyphusion-labs/prism-control-plane) | Commercial plane (`play-proxy.skyphusion.org`) **1.0.0** |
| [prism-android](https://github.com/skyphusion-labs/prism-android) | Sibling Android app **1.0.0** |
| [prism-mcp](https://github.com/skyphusion-labs/prism-mcp) | MCP door for playground API |

## Layout

- `Sources/PrismKit` -- API clients + models
- `Tests/PrismKitTests` -- XCTest + URLProtocol mocks
- `App/` -- SwiftUI (`PrismApp`, `AppState`, login/chat/settings)
- `project.yml` -- XcodeGen; regenerate with `xcodegen generate`
- `Package.swift` -- SPM library (iOS 16+, macOS 13+)

## Clients

- **`PrismClient`** -- playground Worker. Public mode session cookie after login. `chatStreamEvents`
  for incremental SSE. Conversation compact: `compactConversation` / `clearConversationCompact`
  (`POST|DELETE /api/conversations/:id/compact`, playground v0.175.7). Plane compact is client-side
  (summary system block + recent raw turns) via `ConversationCompact` helpers.
- **`ControlPlaneClient`** -- metered plane, `Bearer pcp_…`. Enroll, me/models, chat stream,
  `generateImage` / `generateVideo` / `generateSpeech` (TTS) / `transcribe` (STT) / `generateMusic`,
  async Prefer + `getJob` / `waitForJob` (video, music, speech, gpt-image-2), store redeem.
- **`VideoDurationCatalog`** -- per-model CF clip length limits (mirror of plane `video-duration.ts`).
- **`SSEParser`** -- playground `{type:delta}` and OpenAI `choices[].delta.content` frames.
- **`SecretStore` / `KeychainSecretStore`** -- plane device key, pending job ids, playground session
  cookie, URL prefs (memory store on Linux CI).
- **Session restore** -- `PrismClient.exportSessionToken` / `restoreSessionToken` for `__Host-prism_session`.
- **`StoreProducts`** -- ASC credit pack product ids (`org.skyphusion.prism.credit.*`).
- **App 1.0 surface** -- async media + forceSync on foreground; clip length picker; Use in chat /
  Animate; inline text attach (not RAG); StoreKit top-up; biometric lock.

## Commands

```bash
swift test                 # package tests (CI)
xcodegen generate          # refresh Prism.xcodeproj from project.yml
xcodebuild -scheme Prism -destination 'generic/platform=iOS Simulator' build
./scripts/archive-testflight.sh   # device archive for TestFlight (needs signing)
```

## Apple Developer / App Store Connect (CLI)

Signing is Conrad's **personal** Apple Developer Program membership (Team ID
`858878N47M` in `project.yml`). There is no separate skyphusion org team. Branding
(`org.skyphusion.prism`, ASC key name `skyphusion`) is product naming only.

Use **`asc`** (`brew install asc`), not the dashboard, once an API key is registered:

```bash
asc auth login --name skyphusion --key-id … --issuer-id … --private-key ~/.config/skyphusion/AuthKey_….p8 --network
asc auth status
asc apps list
```

Setup steps: `docs/apple-cli.md`. Command catalog: `docs/ASC.md`. Credentials live in
macOS keychain (or `chmod 600` env under `~/.config/skyphusion/`); never in the repo.
StoreKit 2 redeem: plane **1.0.0** / **0.4.36+** (`POST /v1/store/redeem`, Production JWS verify).
IAP catalog in `Configuration.storekit` + ASC (`credit.{5,20,50}`).

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
