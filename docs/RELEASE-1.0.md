# Prism for iOS 1.0.0 release

**App name:** Prism for iOS  
**Version:** 1.0.0 (build 26)  
**Bundle:** `org.skyphusion.prism`  
**ASC app id:** `6798391677`  
**Plane:** play-proxy `prism-control-plane` **0.4.36+** (StoreKit Production JWS verify)

## What ships

- Control-plane client: chat (incl. Gemini native body), image/video/music/TTS/STT
- Async Workflow jobs: video, music, speech, gpt-image-2
- Credit top-up: StoreKit 2 packs → `POST /v1/store/redeem`
- Display name **Prism for iOS** (home screen + ASC)

## IAP (consumables)

| Product ID | ASC id | Price | Localization | Review screenshot |
| --- | --- | --- | --- | --- |
| `org.skyphusion.prism.credit.5` | 6798391977 | $5 | en-US READY | COMPLETE (640×920) |
| `org.skyphusion.prism.credit.20` | 6798391642 | $20 | en-US READY | COMPLETE |
| `org.skyphusion.prism.credit.50` | 6798392108 | $50 | en-US READY | COMPLETE |

Descriptions (max 55 chars ASC): `$N prepaid credit for Prism for iOS.`  
Asset source: `docs/iap-review-screenshot.png` (Top up UI mock for App Review).

**State:** READY_TO_SUBMIT until attached to app version 1.0.0 submission.

## Plane redeem (0.4.36)

| Environment | Verify path |
| --- | --- |
| **Production** | Leaf ES256 (SPKI from `x5c[0]` X.509) + chain length ≥ 2. No trust_decode. |
| **Sandbox** | Same crypto verify by default. Opt-in `STORE_REDEEM_ALLOW_SANDBOX_TRUST=true` for lab only. |
| **Xcode** | Decode-only after `environment=Xcode` (Configuration.storekit). |
| Lab fields | `STORE_REDEEM_TRUST_DECODE=true` only; never Production. |

Product map: `src/store-products.ts` (plane) ↔ `StoreProducts` (iOS).

## Sandbox / TestFlight purchase checklist

1. **Business:** Paid Applications Agreement + bank + tax complete (ASC → Business).
2. **Upload** 1.0.0 build: `./scripts/archive-testflight.sh` then Organizer → TestFlight.
3. Device: Settings → App Store → **Sandbox Account** (not personal Media ID).
4. Install TestFlight build; enroll with operator token / `pcp_` key.
5. Settings → **Top up** → buy Credit 5 USD (sandbox).
6. Confirm balance rises (plane redeem `verified: "jws"` or sandbox trust flag).
7. Do **not** enable Configuration.storekit on the scheme for this test (that is Xcode-only).

Local UI-only path (no Apple money): scheme → StoreKit Configuration → `Configuration.storekit`.

## App Store submit (1.0.0)

1. App Store version **1.0.0** with build 26.
2. Attach all three IAP versions to the submission.
3. Screenshots: `docs/ASC-SCREENSHOTS.md` (6.7" + 6.5").
4. Privacy policy: `https://skyphusion.org/privacy.html`
5. Support URL + age rating (AI content generation).
6. Review notes: see `docs/ASC-CHECKLIST.md` (enroll token, top-up sandbox, Face ID).

## Related docs

| Doc | Purpose |
| --- | --- |
| `docs/ASC-CHECKLIST.md` | Pre-public ASC gates |
| `docs/ASC-SCREENSHOTS.md` | Store screenshot shot list |
| `docs/TESTFLIGHT.md` | Device smoke + archive |
| `docs/apple-cli.md` | `asc` auth + identifiers |
| `docs/ASC.md` | Full `asc` command map |
| plane `docs/CONTRACT.md` | Redeem contract |
| plane `CHANGELOG.md` | 0.4.36 store verify |

## Git tags / Releases

- iOS: `v1.0.0` on this repo (GitHub Release).
- Plane: `v0.4.36` when PR merges (or tag from `fix/0.4.35-matrix-smoke-failures` / main after merge).
