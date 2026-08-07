# TestFlight smoke (Prism for iOS)

Internal / external beta checklist for real-device validation. Use **asc** CLI
where possible; App Store Connect API key is already registered (`asc auth status`).

App: **Prism for iOS** (`org.skyphusion.prism`, ASC id `6798391677`).  
Signing Team ID: `858878N47M` (personal Apple Developer Program membership -- not a
separate "skyphusion" org team). Version **1.0.0+** (see `docs/RELEASE-1.0.md`).

ASC CLI credential name `skyphusion` is only the local key label; App Store Connect
and code signing both hang off the personal account that owns that Team ID.

## "Copy failed" on Distribute / export IPA

Xcode Organizer error **Copy failed** with logs under  
`/var/folders/.../T/Prism_*.xcdistributionlogs` is almost always:

```text
/usr/bin/rsync ... -E ...
rsync: on remote machine: --extended-attributes: unknown option
rsync error: ... [server=3.4.4]
```

**Cause:** Homebrew **GNU rsync 3.x** is on `PATH` ahead of Apple **openrsync**.  
Xcode still invokes `/usr/bin/rsync`, but the receiving side picks up GNU rsync, which does not understand Apple’s `-E` / `--extended-attributes`.

**Fix (pick one):**

```bash
# Preferred: stop Homebrew from shadowing system rsync
brew unlink rsync

# Then fully quit and reopen Xcode (GUI apps cache PATH)
```

Or export/upload via the repo script (forces system PATH first):

```bash
./scripts/archive-testflight.sh --export
```

Do **not** need to change the app project for this; it is an environment conflict.

## Build number (CFBundleVersion)

One build setting, `CURRENT_PROJECT_VERSION`, feeds both targets:

| Target | How `CFBundleVersion` is produced |
| --- | --- |
| `Prism` (app) | `GENERATE_INFOPLIST_FILE: YES`, so Xcode injects `CURRENT_PROJECT_VERSION` over `App/Info.plist` |
| `PrismWidget` (extension) | `Widget/Info.plist` holds the literal `$(CURRENT_PROJECT_VERSION)` |

Because there is exactly one source value, the extension's build number cannot
drift from its host app's. App Store Connect rejects an upload where they
differ, so keep it that way: never set a per-target build number by hand.

`project.yml` is the source of truth and `Prism.xcodeproj` is generated from it
by XcodeGen. `scripts/archive-testflight.sh` runs `xcodegen generate` before
every archive, so **an edit to `project.pbxproj` alone is discarded on the next
local archive.** Change `project.yml` (both sites: `settings.base` and
`targets.PrismWidget.settings.base`), then regenerate.

### Xcode Cloud

`ci_scripts/ci_pre_xcodebuild.sh` sets `CURRENT_PROJECT_VERSION` to Xcode
Cloud's own `CI_BUILD_NUMBER` before `xcodebuild` runs, so the uploaded build
number advances on its own instead of waiting for somebody to remember. The
script writes both `project.yml` and the committed `project.pbxproj` (Xcode
Cloud does not run `xcodegen`, so `xcodebuild` reads the committed project),
verifies that every declaration in both files carries the new value, and fails
the build if any does not.

Outside Xcode Cloud `CI_BUILD_NUMBER` is unset, and the script then writes
nothing and exits 0. A local archive therefore uses the committed value as its
floor. It does not substitute a default, because a default would be a build
number nobody chose.

### Prerequisite: Next Build Number in App Store Connect

Xcode Cloud build numbers start at `1` and count up per build; they know
nothing about builds uploaded before Xcode Cloud existed. Build 27 of version
`1.0.0` is already uploaded, so until Xcode Cloud's counter passes it, a
derived build number collides with or regresses against what is already there
and the upload is rejected with *"The bundle version must be higher than the
previously uploaded version."*

Set the counter once, in App Store Connect: **app page -> Xcode Cloud tab ->
Settings -> Build Number -> Edit next to Next Build Number**. Requires the
Admin or App Manager role. Set it above the highest already-uploaded build.

Do not raise `MARKETING_VERSION` to work around a build-number collision; for
iOS, App Store Connect only requires the version and build-number pair to be
unique, and `1.0.0` is pinned deliberately (see `docs/RELEASE-1.0.md`).

## Build & upload

### Option A -- script (archive)

```bash
cd ~/dev/prism-ios
chmod +x scripts/archive-testflight.sh
./scripts/archive-testflight.sh
# optional IPA + upload path when profiles allow:
./scripts/archive-testflight.sh --export
```

Archive lands at `build/archives/Prism.xcarchive`. Open Xcode → **Organizer** →
select archive → **Distribute App** → **App Store Connect** → TestFlight.

Requires a valid Apple signing identity on this Mac:

```bash
security find-identity -v -p codesigning
```

If that lists **0 valid identities**, sign into **your personal** Apple ID in
Xcode → Settings → Accounts, select Team `858878N47M`, and let Automatic signing
create an Apple Development (and, for archive upload, Distribution) certificate.
There is no separate skyphusion org team to pick.

### Signing errors (personal team, first device)

**"Your team has no devices… generate a provisioning profile"** and  
**"No profiles for org.skyphusion.prism"** mean Apple has no registered iOS
device UDIDs on this membership. **Development** profiles always require at
least one device. (App Store / TestFlight **distribution** profiles do not.)

| Goal | What to do |
| --- | --- |
| Run on a physical iPhone | Plug in the phone (trust this computer), unlock it, pick it as the Xcode run destination. Xcode → Signing: Automatic + personal team. Xcode registers the UDID and mints an **iOS App Development** profile. Or register manually (below). |
| TestFlight only (no phone plugged in) | In Xcode, set destination to **Any iOS Device (arm64)** (not a simulator). Product → **Archive**. That path uses **App Store** signing and does **not** need a development device list. Then Organizer → Distribute → App Store Connect. |
| Simulator only | Simulator builds do not need a provisioning profile. Destination: iPhone 17 simulator (or any sim). |

Register a device without Xcode (when you know the UDID from the phone:
Settings → General → About → copy UDID via Finder/Xcode, or ask a friend’s
device):

```bash
asc devices list                                    # currently empty until one is added
asc devices register --name "Conrad iPhone" --udid "THE-UDID" --platform IOS
# then in Xcode: Signing → Download Manual Profiles / toggle Automatic off→on
```

List what ASC already knows:

```bash
asc devices list
asc bundle-ids list
```

**"Communication with Apple failed"** is usually separate: flaky network, Apple
outage, or Accounts session stale. Sign out/in of the Apple ID under Xcode →
Settings → Accounts, accept any unpaid agreements on
[developer.apple.com/account](https://developer.apple.com/account), retry.

### Option B -- Xcode UI

```bash
cd ~/dev/prism-ios
xcodegen generate
open Prism.xcodeproj
# Product → Archive → Distribute App → TestFlight
```

### After processing

```bash
asc builds list --app 6798391677
asc beta-groups list --app 6798391677
# Add build to an internal group when READY_TO_SUBMIT / processing finishes
```

## Smoke script (device)

1. **Fresh install** → onboarding → enroll with a one-time token (or paste `pcp_`).  
   Clipboard paste accepts token or full `pcp_` key.
2. **Chat**  
   - Stream a reply; cancel mid-stream.  
   - Switch models mid-thread; ask about prior turns (context retained).  
   - **Compact** after 3+ turns; badge shows; Expand restores full wire history.  
   - List icon → multi-session; New chat; reopen older session.  
   - Force a failure (optional) → **Retry** / **Regenerate**.  
   - Long-press assistant → Speak (uses TTS model).
3. **Image**  
   - Pure t2i (flux-1-schnell).  
   - Dual model + Photos reference.  
   - Spend preview; Save to Photos + Share; history restore.
3b. **Chat vision (0.8.2+)**  
   - Attach a photo (paperclip/photo button); send with a short question.  
   - Prefer a vision-capable chat model; reply references the image.  
   - Plane **v0.4.23+** for multiparty image content on control-plane.
3c. **Chat starters**  
   - Empty chat starters are complete sentences (no trailing blank topic).  
3d. **Fable + Stream**  
   - Stream on, Claude Fable 5, short prompt → full reply (not empty/gateway error).  
   - Plane **v0.4.22+**.
4. **Video**  
   - Default model should prefer **Seedance** (not Hailuo).  
   - Seedance Fast / Veo Fast; elapsed timer.  
   - Hailuo without photo shows i2v footer.  
   - On failure, **Retry video** keeps prompt.  
   - In-app player + share URL. History: tap restore; Clear history.
5. **More → Audio**  
   - Speak: short line → audio plays.  
   - Transcribe: record a few seconds → transcript; Use as chat draft.
6. **More → Music**  
   - Short prompt → generate; play or open URL.
7. **More / Settings → Top-up** (sandbox Apple ID or Configuration.storekit Debug)  
   - Purchase credit pack → balance rises after `POST /v1/store/redeem`.  
   - Plane **v0.4.36+** (Production JWS leaf verify). Sandbox must verify unless
     `STORE_REDEEM_ALLOW_SANDBOX_TRUST=true` on a lab worker.  
   - Xcode Configuration.storekit → environment Xcode (decode path).  
   - TestFlight: device Sandbox Apple ID, **no** StoreKit config override.
7b. **Chat backup / sync (0.8.2+)**  
   - Settings → Export local chats (JSON).  
   - Settings → Import chats (JSON).  
   - Playground: Chats list → Sync from playground cloud (signed in).  
   - Control plane: no server chat store (privacy); local sessions only.  
7c. **Usage / spend (0.8.3+)**  
   - More → Usage & spend detail → dual pool + period meter.  
   - Chat model picker shows rate / vision / stream tags and send preview.  
7d. **Composer (0.8.3+)**  
   - Photo menu: library / camera / paste; mic → STT → draft.  
   - Video gen: leave tab during long run; optional completion notification.
8. **Keychain / offline**  
   - Kill app, relaunch: still enrolled.  
   - Airplane mode: offline banner; send blocked.

## Plane version

```bash
curl -sS https://play-proxy.skyphusion.org/health
# store redeem Production JWS: plane 0.4.36+
```

## Tab layout (0.8.1+)

| Tab | Content |
| --- | --- |
| Chat | Multi-session, compact, stream |
| Image | t2i / i2i |
| Video | t2v / i2v |
| More | Audio (TTS/STT), Music, balance snapshot, Settings |

Gear on every tab still opens Settings.

## Notes

- Photo library + **microphone** usage strings are in `Info.plist` / `project.yml`.
- Local IAP: scheme → Run → Options → StoreKit Configuration → `Configuration.storekit`.
- Do not paste `pcp_` keys into tickets or screenshots.
- `build/` is local output; keep archives out of git (see `.gitignore`).
