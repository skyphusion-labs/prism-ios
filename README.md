# prism-ios

**License:** AGPL-3.0-only  
**API:** [prism](https://github.com/skyphusion-labs/prism)  
**Control plane:** [prism-control-plane](https://github.com/skyphusion-labs/prism-control-plane)  
**Sibling:** [prism-android](https://github.com/skyphusion-labs/prism-android)

## What this is

AGPL **iOS client** for Prism: chat, multimodal modalities, and (later)
subscription / quota UX against the commercial control plane. Goal is easier
access to a curated model set with cost-recovery hosting, not a closed app.

## Layout (skeleton)

- `Sources/PrismKit` -- shared Swift package (API client, models)
- Xcode app target to be added when UI work starts
- CI runs `swift test` on Ubuntu (library tests; full UI on macOS later)

## Status

Skeleton only. Aviation-grade `main`. Next: Bearer auth client, chat + stream
against the public or self-hosted Prism API.

## Related

- Playground: https://play.skyphusion.org  
- Android: https://github.com/skyphusion-labs/prism-android
