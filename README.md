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
cd mac && ./make-signing-cert.sh   # optional, one time
cd mac && ./build-app.sh --install
```
- `make-signing-cert.sh` creates a self-signed "NotchBridge Local Signing" certificate in your login keychain. With it, macOS keeps Calendar, Camera and Local Network permission across rebuilds.
- Without it, the app is ad-hoc signed and macOS may ask for those permissions again after each rebuild.
- The first launch from /Applications adds NotchBridge to your login items. You can turn that off in Settings.
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
  - **Phone:** all current phone notifications, plus the phone's battery level.
    - Click a row to see its full text.
    - Hover a row for quick **Reply** (typed right there), the app's own action, and **Clear**.
    - **Find phone** rings the phone at full alarm volume for 30 seconds, even on silent. Stop it from the Mac or from the phone's notification.
    - **Clear all** dismisses everything on the phone too.
  - Move the pointer away, click outside, or swipe up to close it.
- **Music:** while anything plays (Spotify, Music, a YouTube video in any browser on the Mac, or Spotify / YouTube Music on the phone):
  - The album art sits left of the camera and small dancing bars sit right of it.
  - Hover for quick play/pause and next.
  - Swipe left or right over the notch to skip tracks.
  - The Home tab shows a full player with progress and controls. Music playing on the Mac takes priority over the phone.
  - Turn it off in Settings: "Show what's playing beside the camera".
- **Calendar:** NotchBridge reads every account in the Calendar app (iCloud, Google, Exchange…). It asks for access the first time.
  - The **Agenda** tab lists today's and tomorrow's events. A **Join** button appears from 15 minutes before a Zoom, Meet, Teams, Webex or FaceTime call.
  - The Home clock shows your next event.
  - 5 minutes before a meeting, a card drops out of the notch with **Join**.
- **Mac battery:**
  - Plugging in shows a green "Charging" strip beside the camera with the battery filling up.
  - On battery, you get a red warning at 20% and again at 10%.
- **Shelf:** drag any file toward the notch and the island opens on the **Shelf** tab. Drop the file to park it there; it's still there after a restart.
  - Drag a file back out of the shelf into any app.
  - Double-click a file to open it.
  - Hover a file for **AirDrop** or **Send to phone**. Sending shows a progress ring; on the phone the file lands in **Downloads › NotchBridge** with a notification you can tap to open it.
  - Use **AirDrop all** or **Clear** for everything. Removing a file from the shelf never deletes the file itself.
- **Mirror:** the camera tab shows your camera, so you can check how you look before a call. The camera only runs while that tab is open.
- **Volume** (off by default, Settings): a small volume bar beside the camera when you change the volume. macOS's own volume indicator still shows too.
- **Multiple displays:** in Settings, choose whether the island appears on the display with the notch or on your primary display.
- **Priorities:** phone notifications beat everything else. A meeting card that gets interrupted comes back afterwards. Battery strips never cover a phone card or the open dashboard.
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
- `NotchBridge --filetest <file>` serves on port 47899 and sends `<file>` to a test client. It's used with a fake phone to check transfers byte for byte.

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
- **Mac music info relies on a workaround.** Since macOS 15.4, Apple only lets apps with a special permission read what's playing. NotchBridge gets around this with a small helper (`mac/MediaHelper/NowPlayingHelper.m`) loaded into `/usr/bin/perl`, which already has that permission. A future macOS could block this again. If that happens, Mac music simply disappears from the island and everything else keeps working.
- **One-time codes.** Android 15+ may hide one-time login codes from notification-reading apps. You might see "Sensitive notification content hidden" for bank or 2FA texts.
- **Reply** only works for apps that put a reply box in their notification.
- **Same network only.** This version works only on the same Wi-Fi, with no Bluetooth or internet fallback.
- **No replay protection.** Messages aren't protected against being captured and resent, which is acceptable on a trusted home network.
