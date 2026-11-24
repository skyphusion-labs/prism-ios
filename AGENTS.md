# prism-ios

This file is the guide for any coding agent and any contributor. Follow it.

## What this project is

This is the AGPL iOS client for Prism.
The app name is Prism for iOS.
`PrismKit` is the shared Swift package.
`App/` plus `Prism.xcodeproj` is the SwiftUI shell.

The marketing version is `MARKETING_VERSION` in `project.yml`.
Do not copy a version into this file.
See the latest `v*` tag.
Release notes are in [docs/RELEASE-1.0.md](docs/RELEASE-1.0.md).

The metered API is [prism-control-plane](https://github.com/skyphusion-labs/prism-control-plane).
The default host is `https://play-proxy.skyphusion.org`.
The playground is [prism](https://github.com/skyphusion-labs/prism) at `https://play.skyphusion.org`.
The sibling Android app is [prism-android](https://github.com/skyphusion-labs/prism-android).
The MCP door is [prism-mcp](https://github.com/skyphusion-labs/prism-mcp).
Read each repo for its version.

The bundle id is `org.skyphusion.prism`.
The Apple team id is in `project.yml`.
Signing setup is in [docs/apple-cli.md](docs/apple-cli.md) and [docs/ASC.md](docs/ASC.md).

## Layout

- `Sources/PrismKit` holds API clients and models.
- `Tests/PrismKitTests` holds XCTest and URLProtocol mocks.
- `App/` is the SwiftUI shell.
- `project.yml` is the XcodeGen spec.
- `Package.swift` is the Swift package (iOS 16+, macOS 13+).

## Clients

`PrismClient` talks to the playground Worker.
Public mode uses a session cookie after login.
`compactConversation` and `clearConversationCompact` call the playground compact routes.
Plane compact is client-side.
`ConversationCompact` builds a summary system block plus recent raw turns.

`ControlPlaneClient` talks to the metered plane.
The header is `Bearer pcp_…`.
It enrolls, lists models, streams chat, and generates image, video, speech, STT, and music.
Async work uses Prefer plus `getJob` or `waitForJob`.
Store redeem goes through the same client.

`VideoDurationCatalog` mirrors the plane clip-length limits.
`SSEParser` accepts playground delta frames and OpenAI delta frames.
`SecretStore` keeps the device key, pending job ids, the session cookie, and URL prefs.
Linux CI uses the memory store.
`StoreProducts` holds the credit-pack product ids.

The 1.0 app surface is in [README.md](README.md).

## How to work

```bash
swift test
xcodegen generate
xcodebuild -scheme Prism -destination 'generic/platform=iOS Simulator' build
```

`swift test` is the CI command.
CI is [.github/workflows/ci.yml](.github/workflows/ci.yml).
It runs on Ubuntu and tests the package only.
The app build is local Xcode.
Do not require an iOS simulator on Linux.

After you edit `project.yml` or an app target, run `xcodegen generate`.
Commit the updated `Prism.xcodeproj`.

`./scripts/archive-testflight.sh` makes a device archive.
It needs signing.
TestFlight steps are in [docs/TESTFLIGHT.md](docs/TESTFLIGHT.md).

## Release

A version changes only in a release pull request.
Feature and fix pull requests do not bump it.
Put the tag on that pull request's merge commit.
The version of record is `MARKETING_VERSION` in `project.yml`.
The tag shape is `v*`.
If that version already has a tag, the cycle is closed.
The next release pull request bumps.
If the manifest version has no tag, stop.
Find why before you bump again.

## Docs

Write Simplified Technical English.
Use short sentences.
Use one idea per sentence.
Use the active present tense.
Use plain words.
Use the same word every time.

Do not use an em dash (U+2014) or an en dash (U+2013).
Use a comma, a semicolon, parentheses, or two hyphens (`--`).

State the limit next to the capability.
Do not turn a measured result into a promise.
Use Conventional Commits.
The license is AGPL-3.0-only.

## Safety

Do not put a secret in a tracked file.
Do not put a signing key in the repo.
Credentials stay in the macOS keychain, or in a mode `0600` file outside the repo.
See [docs/apple-cli.md](docs/apple-cli.md).
Do not log a device key or an enrollment token.
