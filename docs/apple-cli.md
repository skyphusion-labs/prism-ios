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

Membership → **Team ID** (10 characters), or after auth:

```bash
asc bundle-ids list 2>/dev/null | head
# or: developer.apple.com → Membership details
```

Put it in `project.yml` as `DEVELOPMENT_TEAM` when ready, then `xcodegen generate`.

## Prism app identifiers (planned)

| Item | Value |
| --- | --- |
| Bundle ID | `org.skyphusion.prism` |
| Product name | Prism |
| IAP (later) | consumable credit packs; product IDs TBD when plane store-receipt is un-parked |

Plane contract still parks **receipt enrollment / credit prices** (see
`prism-control-plane` CONTRACT open decisions). CLI can still create the app,
bundle ID, and IAP *catalog* in App Store Connect; server redeem stays deferred.

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
