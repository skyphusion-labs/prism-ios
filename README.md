# prism-ios

**License:** AGPL-3.0-only  
**App name:** Prism for iOS  
**Version:** 1.0.0  
**API:** [prism](https://github.com/skyphusion-labs/prism)  
**Control plane:** [prism-control-plane](https://github.com/skyphusion-labs/prism-control-plane)  
**Sibling:** [prism-android](https://github.com/skyphusion-labs/prism-android)

## What this is

AGPL **iOS client** for Prism:

1. **`PrismKit`** (Swift package) — HTTP clients for the playground Worker and commercial control plane.
2. **`Prism for iOS` app** (SwiftUI) — enroll / model pick / chat / image / video / audio / music / credit top-up.

## Layout

```
Sources/PrismKit/     -- shared package (API client)
Tests/PrismKitTests/  -- package tests
App/                  -- SwiftUI application sources
project.yml           -- XcodeGen project definition
Prism.xcodeproj/      -- generated iOS app project (open this)
docs/                 -- ASC, TestFlight, 1.0 release notes
```

## Run the app (macOS + Xcode)

```bash
xcodegen generate
open Prism.xcodeproj
# Prism scheme, iPhone simulator, Run
```

Default control plane: `https://play-proxy.skyphusion.org`.  
Playground (optional): `https://play.skyphusion.org`.

Local IAP testing: scheme → Run → Options → StoreKit Configuration → `Configuration.storekit`.

## App Store Connect (CLI)

[asc](https://asccli.sh) — see [docs/apple-cli.md](docs/apple-cli.md) and [docs/ASC.md](docs/ASC.md).

| Item | Value |
| --- | --- |
| ASC name | Prism for iOS |
| App id | `6798391677` |
| Bundle | `org.skyphusion.prism` |
| Credit packs | `org.skyphusion.prism.credit.{5,20,50}` |

## Package tests

```bash
swift test
```

## Status (1.0.0)

- **1.0.0** (build 26): production-ready display name, async image/video/music/speech jobs,
  Gemini chat, IAP top-up via plane redeem (plane **0.4.36+** Production JWS).
- Release notes: [docs/RELEASE-1.0.md](docs/RELEASE-1.0.md)
- TestFlight smoke: [docs/TESTFLIGHT.md](docs/TESTFLIGHT.md)
- ASC submit: [docs/ASC-CHECKLIST.md](docs/ASC-CHECKLIST.md)

## Related

- Playground: https://play.skyphusion.org  
- Control plane contract: [CONTRACT.md](https://github.com/skyphusion-labs/prism-control-plane/blob/main/docs/CONTRACT.md)  
- Android: https://github.com/skyphusion-labs/prism-android  
