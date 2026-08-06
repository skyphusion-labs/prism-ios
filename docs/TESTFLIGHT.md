# TestFlight smoke (Prism iOS)

Internal / external beta checklist for real-device validation. Use **asc** CLI
where possible; App Store Connect API key is already registered (`asc auth status`).

App: **Prism** (`org.skyphusion.prism`, ASC id `6798391677`).  
Signing Team ID: `858878N47M` (personal Apple Developer Program membership -- not a
separate "skyphusion" org team). Kit **0.8.1+**.

ASC CLI credential name `skyphusion` is only the local key label; App Store Connect
and code signing both hang off the personal account that owns that Team ID.

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
4. **Video**  
   - Veo Fast or Seedance Fast; elapsed timer.  
   - On failure, **Retry video** keeps prompt.  
   - In-app player + share URL.
5. **More → Audio**  
   - Speak: short line → audio plays.  
   - Transcribe: record a few seconds → transcript; Use as chat draft.
6. **More → Music**  
   - Short prompt → generate; play or open URL.
7. **More / Settings → Top-up** (sandbox Apple ID or Configuration.storekit Debug)  
   - Purchase credit pack → balance rises after `POST /v1/store/redeem`.  
   - Plane **v0.4.15+** required.
8. **Keychain / offline**  
   - Kill app, relaunch: still enrolled.  
   - Airplane mode: offline banner; send blocked.

## Plane version

```bash
curl -sS https://play-proxy.skyphusion.org/health
# store redeem requires 0.4.15+
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
