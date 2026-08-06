# TestFlight smoke (Prism iOS)

Internal / external beta checklist for real-device validation. Use **asc** CLI
where possible; App Store Connect API key is already registered (`asc auth status`).

## Build & upload

```bash
cd ~/dev/prism-ios
xcodegen generate
# Xcode: Product → Archive → Distribute App → TestFlight
# or: xcodebuild -scheme Prism -destination 'generic/platform=iOS' archive ...
```

App: **Prism** (`org.skyphusion.prism`, ASC id `6798391677`).  
Team: `858878N47M`.

## After build processing

```bash
asc builds list --app 6798391677
# Add to internal group when ready
asc beta-groups list --app 6798391677
```

## Smoke script (device)

1. **Fresh install** → onboarding → enroll with a one-time token (or paste `pcp_`).
2. **Chat**  
   - Stream a reply; cancel mid-stream.  
   - Switch models mid-thread; ask about prior turns (context retained).  
   - Force a failure (optional) → **Retry last message**.
3. **Image**  
   - Pure t2i (flux-1-schnell).  
   - Dual model + Photos reference.  
   - Confirm spend preview text.  
   - Save to Photos + Share.  
   - Tap history item to restore.
4. **Video**  
   - Veo Fast or Seedance Fast; watch elapsed timer.  
   - On failure, **Retry video** keeps prompt.  
   - In-app player + share URL.
5. **Top-up** (Configuration.storekit in Debug scheme, or sandbox Apple ID)  
   - Purchase credit pack → balance increases after `POST /v1/store/redeem`.  
   - Needs plane **v0.4.15+** live.
6. **Keychain**  
   - Kill app, relaunch: still enrolled, balance loads.

## Plane version

```bash
curl -sS https://play-proxy.skyphusion.org/health
# store redeem requires 0.4.15+
```

## Notes

- Photo library usage strings are in `Info.plist` / `project.yml`.
- Local IAP: scheme → Run → Options → StoreKit Configuration → `Configuration.storekit`.
- Do not paste `pcp_` keys into tickets or screenshots.
