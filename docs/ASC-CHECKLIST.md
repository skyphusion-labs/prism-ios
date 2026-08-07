# App Store Connect checklist (Prism for iOS 1.0)

App id **6798391677**, bundle **org.skyphusion.prism**, SKU **skyphusion-prism-ios**,  
display name **Prism for iOS**, marketing version **1.0.0** (build 26).

Use `asc` for API work; dashboard only for agreement/tax that CLI cannot do.

Full 1.0 release notes: **`docs/RELEASE-1.0.md`**.

## Before first public submit (1.0)

| Item | Status / action |
| --- | --- |
| Bundle ID | `org.skyphusion.prism` (Team `858878N47M`) |
| App record | **Prism for iOS** (id 6798391677) |
| IAP consumables | `credit.{5,20,50}` READY_TO_SUBMIT; en-US loc + review screenshots COMPLETE |
| Privacy nutrition labels | Network; no tracking if true; photo/camera/mic/Face ID |
| Privacy policy URL | `https://skyphusion.org/privacy.html` |
| AGPL source / license | Settings → Legal; github.com/skyphusion-labs/prism-ios |
| Support URL | skyphusion.org or status.skyphusion.org |
| Export compliance | HTTPS only |
| Content rights | DOES_NOT_USE_THIRD_PARTY_CONTENT |
| Screenshots | iPhone 6.7" + 6.5" — `docs/ASC-SCREENSHOTS.md` |
| App icon | AppIcon asset catalog |
| Age rating | AI content generation questionnaire |
| Plane | **0.4.36+** for Production JWS redeem |
| Paid Apps Agreement | Business section: agreement + bank + tax |

## Privacy / Info.plist (in repo)

- `NSPhotoLibraryUsageDescription` — reference images for i2i / i2v  
- `NSPhotoLibraryAddUsageDescription` — save generated images  
- `NSMicrophoneUsageDescription` — STT recording  
- `NSCameraUsageDescription` — vision / i2v stills  
- `NSFaceIDUsageDescription` — optional biometric app lock  
- `CFBundleDisplayName` / `CFBundleName` — **Prism for iOS**

## Screenshots

Shot list: **`docs/ASC-SCREENSHOTS.md`**.  
IAP review image: **`docs/iap-review-screenshot.png`** (already uploaded to all three products).

## API keys (local only)

```bash
asc auth status
asc apps list
export ASC_APP_ID=6798391677
asc iap list --app "$ASC_APP_ID"
```

## Product gates (pre-public)

| Gate | Check |
| --- | --- |
| Plane redeem | 0.4.36+ Production JWS; sandbox TestFlight buy → balance |
| Local StoreKit | Configuration.storekit → Top up → Xcode env redeem |
| TestFlight smoke | `docs/TESTFLIGHT.md` on device 1.0.0 |
| Privacy labels | Photos + mic + camera + Face ID; no tracking |
| Review notes | Operator enrollment; control plane never stores chat |

## Pre-submit ASC pass (1.0.0)

1. `asc apps list` / app 6798391677 name **Prism for iOS**  
2. IAP three packs: localizations + screenshots COMPLETE  
3. Screenshots (iPhone 6.7" + 6.5") per `ASC-SCREENSHOTS.md`  
4. Privacy policy + support URLs live  
5. Age rating questionnaire  
6. Export compliance: HTTPS only  
7. Privacy nutrition labels  
8. **Review notes:**

```
Prism for iOS is a metered multimodal AI client. Enrollment uses a single-use
operator token (or recovery pcp_ key) stored in Keychain. Optional Face ID lock
gates the UI after background. Control plane never stores chat text.

IAP: consumable credit packs (5 / 20 / 50 USD) redeem via POST /v1/store/redeem
(StoreKit 2 signed transaction). Demo: enroll, Settings → Top up (sandbox),
chat once, More → Usage. Contact: conrad@skyphusion.org
```

9. Build **1.0.0 (26)** uploaded TestFlight; internal install once  
10. Attach IAPs to version 1.0.0 submission  

## Related

- `docs/RELEASE-1.0.md` — release matrix  
- `docs/TESTFLIGHT.md` — device smoke  
- `docs/apple-cli.md` — identifiers  
- plane CONTRACT — store redeem  
