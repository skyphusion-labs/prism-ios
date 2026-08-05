# Apple Developer via CLI (`asc`)

Prism iOS is driven from the terminal with [asc](https://asccli.sh) (Homebrew:
`brew install asc`). Prefer this over clicking through App Store Connect for apps,
bundle IDs, IAP products, certificates, and TestFlight.

## One-time: App Store Connect API key

1. Open [Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api).
2. Note the **Issuer ID** (page header).
3. **Generate API Key**:
   - Name: `skyphusion-cli` (or similar)
   - Access: **Admin** (or App Manager + access to Certificates, IDs & Profiles and IAP)
4. Download `AuthKey_<KEY_ID>.p8` **once**. Store it outside any git tree, e.g.
   `~/.config/skyphusion/AuthKey_<KEY_ID>.p8` with `chmod 600`.
5. Register with asc (credentials go in the **macOS keychain** by default):

```bash
asc auth login \
  --name skyphusion \
  --key-id '<KEY_ID>' \
  --issuer-id '<ISSUER_ID>' \
  --private-key ~/.config/skyphusion/AuthKey_<KEY_ID>.p8 \
  --network
```

6. Confirm:

```bash
asc auth status --verbose
asc doctor
asc apps list
```

Optional env fallback (not required if keychain login worked): copy
`~/.config/skyphusion/apple-developer.env.example` → `apple-developer.env`
(`chmod 600`), fill values, and `set -a; source …; set +a`. Prefer keychain.

**Never** commit `.p8` files, Issuer IDs with private keys, or `./.asc/config.json`
that contains key material. Repo docs only.

## Team ID (Xcode signing)

| Item | Value |
| --- | --- |
| Team ID | `858878N47M` (bundle seedId) |
| In repo | `project.yml` → `DEVELOPMENT_TEAM` |

After changing `project.yml`: `xcodegen generate`.

## Prism app identifiers

| Item | Value |
| --- | --- |
| Bundle ID | `org.skyphusion.prism` |
| Bundle resource ID | `4Y2B2UF5QB` |
| Product name | Prism |
| SKU (when creating app) | `skyphusion-prism-ios` |
| IAP capability | enabled on the bundle ID |

### Create the App Store Connect *app* (API key cannot CREATE apps)

App Store Connect API keys only allow GET/UPDATE on `apps`. Create once via web session:

```bash
# interactive Apple ID + password + 2FA (not the API key)
asc web auth login --apple-id 'you@example.com'
asc web apps create \
  --name "Prism" \
  --bundle-id "org.skyphusion.prism" \
  --sku "skyphusion-prism-ios" \
  --platform IOS \
  --primary-locale en-US
asc apps list
```

Then export the numeric app id for later IAP:

```bash
export ASC_APP_ID="$(asc apps list --output json | jq -r '.data[0].id')"
asc iap create --app "$ASC_APP_ID" --type CONSUMABLE --ref-name "Credit pack" --product-id "org.skyphusion.prism.credit.5"
```

Plane contract still parks **receipt enrollment / credit prices**. Catalog IAP can land;
server redeem stays deferred.

## Useful commands

```bash
asc apps list
asc bundle-ids list
asc bundle-ids create --identifier org.skyphusion.prism --name Prism --platform IOS
asc iap --help
asc signing --help
asc testflight --help
```

Full command catalog: [ASC.md](./ASC.md) (`asc docs init` regenerates it).
