# prism-ios

**License:** AGPL-3.0-only  
**API:** [prism](https://github.com/skyphusion-labs/prism)  
**Control plane:** [prism-control-plane](https://github.com/skyphusion-labs/prism-control-plane)  
**Sibling:** [prism-android](https://github.com/skyphusion-labs/prism-android)

## What this is

AGPL **iOS client kit** for Prism: shared Swift package (`PrismKit`) that talks to:

1. **Playground Worker** (`https://play.skyphusion.org` or self-host) -- public signup/session cookie, `GET /api/models`, `POST /api/chat` + SSE stream.
2. **Control plane** (`https://play-proxy.skyphusion.org`) -- device enrollment + `Bearer pcp_…` metered chat.

A full Xcode SwiftUI app ships next; this package is the spine.

## Layout

```
Sources/PrismKit/
  PrismKit.swift           -- version / package identity
  Models.swift             -- Codable request/response types
  HTTPClient.swift         -- URLSession + cookie jar
  PrismClient.swift        -- playground Worker client
  ControlPlaneClient.swift -- commercial plane client
  SSE.swift                -- chat stream parser
Tests/PrismKitTests/       -- unit + URLProtocol mocks
```

## Status

**Library client: in progress.** Aviation-grade `main`. Next: Keychain storage, SwiftUI shell, StoreKit later.

## Build / test

```bash
# macOS (Command Line Tools or Xcode)
swift test

# Prefer full Xcode toolchain if CLI tools miss XCTest:
# DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```

## Quick use

```swift
import PrismKit

// Public playground (cookie session after login)
let play = PrismClient(baseURL: PrismClient.playBaseURL)
let catalog = try await play.models()
_ = try await play.login(username: "you", password: "••••••••••")
let reply = try await play.chat(ChatRequestBody(model: catalog.models[0].model, userInput: "Hello"))
print(reply.output ?? "")

// Or stream
let (text, _) = try await play.chatStreamText(
  ChatRequestBody(model: catalog.models[0].model, userInput: "Hello")
)

// Commercial plane (device key from enrollment -- store in Keychain)
let plane = ControlPlaneClient(baseURL: ControlPlaneClient.productionBaseURL)
// let en = try await plane.enroll(enrollmentToken: "…")
// plane.setClientKey(en.key)
// let answer = try await plane.chat(model: "…", user: "Hello")
```

## Related

- Playground: https://play.skyphusion.org  
- Control plane contract: [prism-control-plane/docs/CONTRACT.md](https://github.com/skyphusion-labs/prism-control-plane/blob/main/docs/CONTRACT.md)  
- Android: https://github.com/skyphusion-labs/prism-android
