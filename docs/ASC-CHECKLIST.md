# App Store Connect checklist (Prism)

App id **6798391677**, bundle **org.skyphusion.prism**, SKU **skyphusion-prism-ios**.

Use `asc` for API work; dashboard only for agreement/tax that CLI cannot do.

## Before first public submit

| Item | Status / action |
| --- | --- |
| Bundle ID | `org.skyphusion.prism` (seed `858878N47M`) |
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

## Product gates

- Plane redeem: `POST /v1/store/redeem` (0.4.15+)  
- Do not ship public top-up marketing until sandbox redeem is verified on device  
