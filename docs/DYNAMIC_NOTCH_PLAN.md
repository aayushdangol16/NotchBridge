# Dynamic Notch: plan

**Goal:** make the notch a live, responsive surface, like Boring Notch or the iPhone's Dynamic Island. Android phone notifications become one feature of it, not the only one.

**Approach:** build our own on top of the notch window we already have. Use Boring Notch as a reference for features and how it behaves, but don't copy its code.

## 1. Why build from scratch instead of forking Boring Notch

| | Fork boring.notch | Build our own (recommended) |
|---|---|---|
| License | GPL-3.0: our whole app would have to be GPL and open source | Ours to choose |
| Build tools | Needs Xcode 26 and macOS 15.6+ to build | SwiftPM + `build-app.sh` (works with the command-line tools we have) |
| Phone link | Would have to be added to someone else's large codebase | Already built and working in our app |
| Effort | Fast start, slow to customise | Phase 1 takes about a week, then grows one feature at a time |

Ideas we borrow from Boring Notch (ideas only, not code):
- music controls in the notch with a sound visualiser
- calendar
- a file shelf with AirDrop
- replacements for the volume and brightness pop-ups
- a battery and charging indicator
- a camera mirror
- a menu-bar settings entry
- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) for reading what's playing on macOS 15.4 and later

## 2. How it behaves

```
            hover near notch               click / swipe down
  IDLE ───────────────────────► PEEK ─────────────────────────► OPEN (dashboard)
 (invisible,  ◄── mouse leaves ──  (slightly wider: live   ◄── click outside / Esc ──
  click-through)                    activity beside camera)
        ▲                                                         tabs: Home · Phone · Shelf
        │  an event arrives (notification, call, volume, charging)
        └──── ACTIVITY (temporary card, shows a few seconds, then back to the previous state)
```

- **IDLE:** looks exactly like the hardware notch. Clicks pass through. Uses no CPU.
- **PEEK:** happens on hover, or by itself while something is "live". It shows small items on either side of the camera:
  - music: album art on the left, an animated sound wave on the right
  - phone call: caller photo and an animated ringing icon
  - phone connected: a small battery icon
- **OPEN:** a dashboard about 480×200 pt with these tabs:
  - **Home:** what's playing (Mac or phone), the next calendar event, and the latest phone notifications
  - **Phone:** a notification list where you can reply, dismiss or act on each one; the phone's battery level; "find my phone" (rings it)
  - **Shelf:** drop files here to keep them handy; AirDrop them or send them to the phone
- **ACTIVITY:** a temporary card. The phone notification card we have today becomes one kind of activity. Activities have priorities, so a higher one replaces a lower one, and the lower one returns afterwards:
  1. incoming call
  2. phone notification
  3. volume or brightness change
  4. charging or low battery
  5. music track change

Gestures and input:

| Input | Result |
|---|---|
| Hover over the notch | Peek |
| Click the notch | Open |
| Swipe down on the trackpad while over the notch | Open |
| Swipe up | Close |
| Swipe left / right while music is showing | Next / previous track |
| Esc or click outside | Close |
| Hover over a card | Pauses its timer (already built) |

## 3. Architecture (Mac app)

```
mac/Sources/NotchBridge/
  Core/
    NotchWindow.swift        panel: always ordered in, click-through when idle (today's NotchPanel)
    NotchGeometry.swift      notch size and position per screen, multiple monitors, fullscreen
    NotchStateMachine.swift  idle / peek / open / activity, with the transition rules
    HoverTracker.swift       global mouse-move watcher + a hot zone around the notch (no Accessibility permission needed)
    GestureHandler.swift     scroll / swipe events while the pointer is over the panel
    ActivityCenter.swift     priority queue of activities, plus the "newest wins / +N" logic
  UI/
    IslandShape.swift        today's NotchShape
    IslandView.swift         root view; switches between peek, open and activity layouts
    Peek/*.swift             small items shown beside the camera (music, call, battery)
    Dashboard/*.swift        Home / Phone / Shelf tabs
    Activities/*.swift       notification card (today's), call card, HUD card, charging card
  Features/
    Phone/      today's BridgeServer, Pairing, NotificationStore, plus phone media and battery
    Media/      MediaController protocol, with three implementations:
                  MediaRemoteAdapterSource (macOS 15.4+, uses mediaremote-adapter)
                  AppleScriptSource (fallback for Music and Spotify)
                  PhoneMediaSource (what's playing on the Android phone)
    Calendar/   EventKit: next event, a "meeting in 5 minutes" activity
    Battery/    IOKit power-source notifications: charging and low battery activities
    HUD/        volume and brightness overlay (optional, see risks)
    Shelf/      drag and drop store, AirDrop through NSSharingService, send to phone
  Settings/
    SettingsWindow.swift     SwiftUI settings: which features are on, sizes, behaviour, pairing
    Preferences.swift        @AppStorage keys
```

Rules:
- **One state machine owns the island.** Features never change the window themselves; they hand an `Activity` or `LiveItem` to `ActivityCenter`.
- **Every feature is a module** with an on/off switch in Settings. A turned-off feature does no work in the background.
- **Performance:** when idle the island renders nothing and only watches mouse movement. Animations run only while visible. Target under 1% CPU when idle.
- **Keep snapshot mode** (`--snapshot`) so every layout can be checked visually during development.

## 4. Phone side (Android) additions

| Feature | How |
|---|---|
| **Phone media** (Spotify or YouTube Music on the phone, shown and controlled from the Mac notch) | Media notifications carry a `MediaSession.Token` → `MediaController` gives title, artist, album art and play state; we send `media` messages and accept `media_cmd` (play, pause, next, previous). |
| **Calls** (ringing card with answer and decline) | Incoming-call notifications are already forwarded (this update). Next step is to map the answer and decline actions to buttons. |
| **Phone battery** | A `BATTERY_CHANGED` broadcast → a `battery` message every 5% or when charging starts or stops. |
| **Find my phone** | Mac sends `ring` → phone plays an alarm at full volume. |
| **Send to phone** (from the Shelf) | Chunked binary file transfer over the same encrypted WebSocket. |

New protocol messages, all inside the existing AES-GCM frames:
- phone → Mac: `media`, `battery`
- Mac → phone: `media_cmd`, `ring`, `file_begin`, `file_chunk`, `file_end`

## 5. Phases

Status: phases 0–6 are built (see the README and git history).


| Phase | Delivers | Done when |
|---|---|---|
| **0. Reliability** (done in this update) | Phone-side alert decisions, queue for missed notifications, faster reconnect, newest-wins with a "+N" badge, call forwarding | Bursts no longer replay old chats. Notifications sent while the Mac was asleep appear after it wakes. |
| **1. Core island** | Hover tracker, state machine, peek and open states, swipe and click gestures, ActivityCenter, Settings window. The notification card moves into it as an activity. | Hovering widens the notch. Clicking opens an empty dashboard. Notifications behave as they do today. Idle CPU stays under 1%. |
| **2. Phone tab** | Dashboard notification list (reply, dismiss, act), phone battery, find my phone | You can work through the phone's notifications without picking it up. |
| **3. Media** | Mac now-playing through mediaremote-adapter with AppleScript fallback, peek wave visualiser, controls, swipe to skip. Phone media through MediaSession. | Spotify on the Mac or on the phone shows in the peek and is controllable. |
| **4. Calendar + battery** | Next event on Home, "meeting soon" activity, charging and low-battery activities | Plugging in shows a charging animation. A meeting 5 minutes away shows a card. |
| **5. Shelf** | Drop files, AirDrop, send to phone | Dragging a file to the notch keeps it there. Send to phone works. |
| **6. Polish and extras** | Volume and brightness HUD, camera mirror, themes and sizes, multiple monitors, launch at login by default, a proper app icon | Daily-driver quality. |

## 6. Risks

- **Reading what's playing:** Apple locked this down in macOS 15.4. mediaremote-adapter works around it by running through `/usr/bin/perl`, which is allowed to use it, but a future macOS could break that again. Keep the AppleScript fallback for Music and Spotify, and keep media a separate module.
- **Replacing the system volume and brightness pop-ups:** this needs to intercept the media keys (an event tap, which requires Accessibility permission). Hiding Apple's own pop-up is fragile across macOS versions. Make this the last feature, and optional.
- **Hover detection:** a global mouse-move watcher works without special permissions. Check that it never steals clicks when the island is idle, since the window stays click-through.
- **Fullscreen and multiple monitors:** the always-on-screen panel already handles fullscreen. Multiple monitors need one panel per screen with a notch, or a choice in Settings.
- **The phone killing the app in the background:** the foreground service plus the "Never sleeping apps" setting remain the main defence. Show a warning in the Phone tab if the phone hasn't been heard from recently.
- **Signing:** the app is ad-hoc signed today, so macOS permissions (calendar, camera, Accessibility) may be asked for again after each rebuild. A free Apple Development certificate keeps them stable.
