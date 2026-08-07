# ASC screenshots kit (Prism for iOS 1.0)

Minimum for first public submit: **iPhone 6.7"** and **6.5"** (portrait).
Optional: iPad 13" if you enable iPad multitasking listing.

App ASC id **6798391677**, bundle **org.skyphusion.prism**, name **Prism for iOS**.  
Version target: **1.0.0** (`docs/RELEASE-1.0.md`).

## Capture setup

1. Install the TestFlight / device build of **1.0.0** (or the version you will submit).
2. Enroll with a throwaway operator token that has spendable balance (do not screenshot real personal chats with private content).
3. Use **Light mode**, English, no notification banners, full charge or hide battery if fussy.
4. Simulator or device: Simulator is fine for ASC if UI matches production (Control plane + real models).
5. iOS **Settings → Display & Brightness → Text Size** default.
6. Home screen label under the icon should read **Prism for iOS** (not bare "Prism").

## Shot list (required narrative)

| # | Screen | What to show | Why review / store |
| --- | --- | --- | --- |
| 1 | Chat empty + starters | Model picker, starter chips, mic + attach | First open value |
| 2 | Chat with reply | User + assistant bubble, **last request cost** caption if visible | Metered product honesty |
| 3 | Chat vision | Photo attach chip + vision model | Multimodal |
| 4 | Live STT (optional) | Mic menu → Live listen bar / partial text | Differentiator |
| 5 | Image generate | Prompt + result thumbnail | Image door |
| 6 | Video generate | Seedance prompt + generating or done | Video door |
| 7 | More → Usage | Dual-pool lines / spendable | Billing transparency |
| 8 | Settings lock + top-up | **Require Face ID** toggle + IAP packs | Privacy + IAP |
| 9 | Biometric lock gate | "Prism is locked" unlock screen | Security feature |

## How to capture (device)

```text
iPhone: Side + Volume Up → screenshot
Files → On My iPhone → Screenshots (or AirDrop to Mac)
```

Resize/crop only if needed to exact device sizes ASC expects; prefer native resolution.

## How to capture (Simulator, optional)

```bash
cd ~/dev/prism-ios
xcodegen generate
open Prism.xcodeproj
# Run on iPhone 16 Pro Max (6.7") and iPhone 11 Pro Max / 15 Plus class (6.5")
# Device → Trigger Screenshot, or Cmd+S
```

## Upload

App Store Connect → Prism → version → Screenshots:

- Drag 6.7" set into iPhone 6.7" slot
- Drag 6.5" set into iPhone 6.5" (or let ASC scale if only one set -- Apple still prefers both)

## Caption ideas (optional ASO)

1. Chat with metered models -- cost per request on device  
2. Image, video, speech -- one control-plane key  
3. Face ID lock for your enrolled session  
4. Usage and dual-pool balance at a glance  
5. Local chat backup; plane never stores your transcript  

## Review notes (paste with screenshots)

See `docs/ASC-CHECKLIST.md` review notes for **1.0**. Point reviewers at:

1. Enroll with provided token  
2. Settings → enable Face ID lock, background, re-open  
3. Chat once (cost line + balance)  
4. More → Usage  
5. Optional: Chat mic → Live listen  

## Do not screenshot

- Real `pcp_` keys or enrollment tokens  
- Other people's PII  
- Debug Developer playground URLs unless marketing that path  
