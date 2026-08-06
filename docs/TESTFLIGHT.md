# TestFlight smoke (Prism iOS)

Internal / external beta checklist for real-device validation. Use **asc** CLI
where possible; App Store Connect API key is already registered (`asc auth status`).

App: **Prism** (`org.skyphusion.prism`, ASC id `6798391677`).  
Team: `858878N47M`. Kit **0.8.1+**.

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

Requires a valid Apple signing identity on this Mac (`security find-identity -v -p codesigning`).
If none are listed, open Xcode once signed into the skyphusion team so Automatic
signing can mint certificates.

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
