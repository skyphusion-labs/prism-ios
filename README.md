# prism-ios

**License:** AGPL-3.0-only  
**API:** [prism](https://github.com/skyphusion-labs/prism)  
**Control plane:** [prism-control-plane](https://github.com/skyphusion-labs/prism-control-plane)  
**Sibling:** [prism-android](https://github.com/skyphusion-labs/prism-android)

## What this is

AGPL **iOS client** for Prism:

1. **`PrismKit`** (Swift package) -- HTTP clients for the playground Worker and commercial control plane.
2. **`Prism` app** (SwiftUI) -- login / enroll / model pick / chat against playground or control plane.

## Layout

```
Sources/PrismKit/     -- shared package (API client)
Tests/PrismKitTests/  -- package tests
App/                  -- SwiftUI application sources
project.yml           -- XcodeGen project definition
Prism.xcodeproj/      -- generated iOS app project (open this)
```

## Run the app (macOS + Xcode)

```bash
# regenerate project after project.yml / App/ changes
xcodegen generate

open Prism.xcodeproj
# select the Prism scheme, iPhone simulator, Run
```

Default server: `https://play.skyphusion.org` (public signup). Settings can point at a self-host Worker.

## App Store Connect (CLI)

[asc](https://asccli.sh) is installed for App Store Connect API work (apps, bundle IDs, IAP, signing).
See [docs/apple-cli.md](docs/apple-cli.md) for API-key login and [docs/ASC.md](docs/ASC.md) for the command map.

## Package tests

```bash
swift test
# or: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```

CI runs package tests on Ubuntu. The iOS app is built with Xcode locally (not in Linux CI).

## Status

- Kit **0.8.7** (build 22): resume async job poll after lock; Prefer: respond-async.
  Prior **0.8.6**: async jobs + Grok Range playback.
- App Store Connect: app `6798391677`, three consumable credit IAPs. See `docs/TESTFLIGHT.md`,
  `docs/ASC-CHECKLIST.md`.

## Related

- Playground: https://play.skyphusion.org  
- Control plane contract: [docs/CONTRACT.md](https://github.com/skyphusion-labs/prism-control-plane/blob/main/docs/CONTRACT.md)  
- Android: https://github.com/skyphusion-labs/prism-android
