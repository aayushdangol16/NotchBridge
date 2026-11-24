# NotchBridge

Shows your Android (Samsung) phone's notifications in your MacBook's notch, like iPhone notifications on a Mac.
You can reply (for apps with a reply button, such as WhatsApp or Messages), tap an action, or dismiss the notification on the phone.

```
Android phone                                   Mac
NotificationListenerService ──┐                 ┌── menu-bar app
                              ├─ Wi-Fi ───────► ├── notch pop-up (SwiftUI panel)
Foreground service (keep-alive)┘  WebSocket,     └── optional Notification Center copy
                                  AES-256-GCM
                         ◄─── dismiss / action / reply
```

- `mac/`: Swift package that builds the menu-bar app `NotchBridge.app` (macOS 14+)
- `android/`: Kotlin app (Android 10+, tested to build against SDK 35)

## Build

### Mac
```bash
cd mac && ./build-app.sh --install
```
This builds an ad-hoc signed app and copies it to `/Applications`. Without `--install`, the app is left in `mac/build/NotchBridge.app`.

### Android
```bash
cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew assembleDebug
```
The APK is written to `android/app/build/outputs/apk/debug/app-debug.apk`. To install it, plug the phone in with USB debugging on and run:
```bash
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
```
You can also copy the APK to the phone and open it there. Android Studio can open the `android/` folder directly.

## First-time setup

On the Mac:
1. Start NotchBridge. A pairing window with a QR code opens; you can reopen it from the menu bar with **Pair phone…**.
2. Click **Allow** if macOS asks about local network access or incoming connections.

On the phone (NotchBridge app):
1. **Notification access** → turn NotchBridge on.
   If the switch is greyed out (because the app wasn't installed from a store), tap it once. Then go to **Settings › Apps › NotchBridge › ⋮ › Allow restricted settings** and try again.
2. **Keep it running.** Samsung stops background apps aggressively, so do all three of these:
   - Tap **Turn off battery optimisation**.
   - Go to **App settings › Battery** and choose **Unrestricted**.
   - Go to **Settings › Battery › Background usage limits** and add NotchBridge to **Never sleeping apps**.
3. **Scan QR code on Mac.** You can also paste the link from **Copy pairing link** instead.
4. Tap **Send a test notification to the Mac**.

Both devices must be on the same Wi-Fi. A VPN or "client isolation" (common on guest and office Wi-Fi) blocks the connection.

## Using it
The notch is now a small dynamic island:
- **Hover over the notch:** it widens slightly. The phone link status shows on the left of the camera and the number of phone notifications on the right.
- **Click it, or swipe down on the trackpad:** opens the dashboard.
  - **Home:** the clock and date, phone status, and the latest notifications.
  - **Phone:** all current phone notifications. Click one to show it again.
  - Move the pointer away, click outside, or swipe up to close it.
- **New phone notifications** peek out of the notch, then open into a card that stays for about 6 seconds (adjustable in Settings). Hovering keeps it open.
  - Click the card for **Reply**, the app's own action, and **Clear** (which also removes it from the phone).
  - Swipe up to hide the card.
  - If several notifications arrive at once, the card shows the newest one with a "+N" badge.
- **Settings (⌘, from the menu bar or the gear icon in the dashboard):**
  - hover behaviour and haptics
  - how long cards stay
  - Notification Center copy
  - pairing
  - launch at login

Developer checks:
- `NotchBridge --selftest` runs the state-machine tests.
- `NotchBridge --snapshot <dir>` renders every island state to PNG.

## How it works

| Piece | File |
|---|---|
| Reads notifications, runs reply/dismiss | `android/…/NotificationCaptureService.kt` |
| Finds the Mac (last IP, then Bonjour), connects, retries | `android/…/Bridge.kt` |
| Keeps the process alive on Samsung | `android/…/BridgeService.kt` (foreground service, type `connectedDevice`) |
| WebSocket server and Bonjour `_notchbridge._tcp` on port 47821 | `mac/…/Features/Phone/BridgeServer.swift` |
| Island state machine, hover and gestures | `mac/…/Core/IslandController.swift`, `HoverTracker.swift` |
| Island views (peek, card, dashboard) | `mac/…/UI/IslandView.swift`, `NotificationCard.swift`, `DashboardView.swift` |
| Key and QR code | `mac/…/Features/Phone/Pairing.swift`, `PairingWindow.swift` |

**Protocol.** Every WebSocket frame is binary data: `nonce(12) | ciphertext | tag(16)`, encrypted with AES-256-GCM using the 32-byte key from the QR code. The decrypted content is JSON with a `type` field:

- From the phone: `hello`, `sync` (current notifications, shown without popping up), `posted`, `removed`, `result`
- From the Mac: `welcome`, `dismiss`, `action`, `reply`

A client that can't decrypt is closed with code 4001, and the phone then shows "scan again". **Reset pairing key…** on the Mac makes any previously paired phone stop working.

The key is stored in `~/Library/Application Support/NotchBridge/pairing.json` (mode 0600) on the Mac, and in the app's private storage on the phone.

## Known limits
- **One-time codes.** Android 15+ may hide one-time login codes from notification-reading apps. You might see "Sensitive notification content hidden" for bank or 2FA texts.
- **Reply** only works for apps that put a reply box in their notification.
- **Same network only.** This version works only on the same Wi-Fi, with no Bluetooth or internet fallback.
- **No replay protection.** Messages aren't protected against being captured and resent, which is acceptable on a trusted home network.
