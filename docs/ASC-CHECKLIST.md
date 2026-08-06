# App Store Connect checklist (Prism)

App id **6798391677**, bundle **org.skyphusion.prism**, SKU **skyphusion-prism-ios**.

Use `asc` for API work; dashboard only for agreement/tax that CLI cannot do.

## Before first public submit

| Item | Status / action |
| --- | --- |
| Bundle ID | `org.skyphusion.prism` (personal Team seed `858878N47M`) |
| App record | Exists as "Prism - prism" |
| IAP consumables | `org.skyphusion.prism.credit.{5,20,50}` READY_TO_SUBMIT |
| Privacy nutrition labels | Declare network; no tracking if true; photo library for refs/save |
| Privacy policy URL | Hosted page (e.g. skyphusion.org / play privacy) linked in ASC |
| Support URL | Same or status.skyphusion.org |
| Export compliance | Standard encryption (HTTPS only) unless you add more |
| Content rights | DOES_NOT_USE_THIRD_PARTY_CONTENT (current ASC attr) |
| Screenshots | iPhone 6.7" + 6.5" minimum; chat + image + settings |
| App icon | AppIcon asset catalog |
| Age rating | Questionnaire (AI content generation) |
| Review notes | Enrollment is operator-token; TestFlight uses Configuration.storekit or sandbox IAP |

## Privacy / Info.plist (in repo)

- `NSPhotoLibraryUsageDescription` -- reference images for i2i / i2v  
- `NSPhotoLibraryAddUsageDescription` -- save generated images  
- `NSMicrophoneUsageDescription` -- STT recording (file + live WebSocket)  
- `NSCameraUsageDescription` -- vision / i2v stills  
- `NSFaceIDUsageDescription` -- optional biometric app lock  

## Screenshots

Shot list and capture notes: **`docs/ASC-SCREENSHOTS.md`**.

## API keys (local only)

```bash
asc auth status
asc apps list
```

StoreKit Server API key (optional, for stricter plane verification later):  
`ASC_STOREKIT_*` env vars documented in `docs/ASC.md`.

## CLI pointers

- Full command map: `docs/ASC.md`  
- Auth setup: `docs/apple-cli.md`  
- Device beta: `docs/TESTFLIGHT.md`  

## Product gates (pre-public)

| Gate | Check |
| --- | --- |
| Plane redeem | `POST /v1/store/redeem` (0.4.15+); sandbox IAP → balance rises |
| Plane vision | v0.4.23+ multiparty image_url on chat |
| Plane Fable stream | v0.4.22+ deferred SSE first-byte |
| TestFlight smoke | Full `docs/TESTFLIGHT.md` on device build 0.8.2+ |
| Privacy labels | Photos + mic; no tracking; chat not sold |
| Review notes | Operator enrollment token; control plane privacy (no server chat) |
| Do not ship | Public top-up marketing until sandbox redeem verified on device |

## Pre-submit ASC pass (operator) — 0.8.4

1. `asc apps list` / app 6798391677 still current  
2. IAP three credit packs READY_TO_SUBMIT or approved  
3. **Screenshots (iPhone 6.7" + 6.5"):** follow `docs/ASC-SCREENSHOTS.md` (chat + cost, vision,
   image, video, Usage, Face ID lock, top-up)  
4. Privacy policy + support URLs live  
5. Age rating questionnaire matches AI generation  
6. Export compliance: HTTPS only  
7. Privacy nutrition: photos, camera, mic, Face ID; no tracking  
8. **Review notes (paste in ASC):**  
   > Prism is a metered multimodal AI client. Enrollment uses a single-use operator token (or
   > recovery pcp_ key) stored in Keychain. Optional Face ID/Touch ID lock gates the UI after
   > background. Control plane never stores chat text. Per-request cost from plane headers when
   > non-stream. Live STT uses GET /v1/stt/stream with Bearer on upgrade. IAP packs apply prepaid
   > credit via POST /v1/store/redeem. Demo: enroll, enable biometric lock, chat once (see cost
   > line), More → Usage, optional live mic. Contact: conrad@skyphusion.org  
9. Build uploaded via TestFlight; internal group installed once  
10. Home Screen widget (balance) + App Shortcuts (Chat / Usage / New chat) optional review mention  

## Review notes template (0.8.4)

```
Account: TestFlight internal (or sandbox Apple ID for IAP)
Enrollment: operator provides single-use token OR recovery pcp_ key
Steps:
1. Launch → enroll with token
2. Chat → short prompt (optional: attach photo with vision model)
3. More → Usage & spend detail
4. Image tab → simple prompt → generate
5. Settings → Top up (sandbox) optional
Privacy: chats local only on control plane; no third-party analytics
```

## Product gates

- Plane redeem: `POST /v1/store/redeem` (0.4.15+)  
- Do not ship public top-up marketing until sandbox redeem is verified on device  
