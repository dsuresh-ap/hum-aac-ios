# Hum human test plan

What the automated UI tests (`HumUITests/`, see [README.md](README.md)) can't check: sound, the camera and
microphone, real devices, iCloud, Apple Intelligence, multi-touch gestures, the Mac, and how things feel.
Run this before each release on real hardware. Mark each row ✅ / ❌ (add a HUM-0xx ID in [BUGS.md](BUGS.md)
for each ❌).

**Devices to cover:** a small iPhone (iPhone SE / 17e), a big iPhone, an older iPad (iPad 9th/10th gen, if
possible ~5 years old), iPad mini, a 13" iPad, and a Mac (window small and large). Do the child-mode
sections on at least one iPhone and one iPad.

**Before you start:** delete Hum, reinstall, and keep `Express2-v2.hum` (or another big real setup) handy
in Files / iCloud Drive / AirDrop.

---

## 1. Sound (the most important part)

| # | Steps | Expected |
|---|-------|----------|
| 1.1 | Starter board, tap “hi” once. | Speech starts the moment your finger touches (no lag you can feel). |
| 1.2 | Tap the same tile 10+ times a second for 30 s, with two fingers if you can. | Every tap restarts the phrase. No pops, clicks, crackle, or a moment of silence. The app never stutters. |
| 1.3 | Film 20 taps with another phone in slow motion (240 fps) next to the device, sound on. Count frames from the finger touching to the sound starting (1 frame ≈ 4 ms). The in-app latency screen was removed (HUM-022). | Median under 30 ms; slowest under 150 ms. Write down the numbers per device. |
| 1.4 | Settings → Tapping → “Let speech finish first”, then tap two tiles quickly. | The first phrase finishes, then the second plays. Nothing is dropped. |
| 1.5 | “Play both together”, tap three tiles quickly. | All three play over each other. |
| 1.6 | “Lifts off the tile”: press a tile, slide off, lift. | Nothing is said. Press and lift on the tile: it speaks on lift. |
| 1.7 | iPhone: flip the silent (ring) switch / Action button to silent. Tap a tile. | Hum still speaks. |
| 1.8 | Plug in headphones / connect Bluetooth while tapping; unplug. | Sound moves to the new output at once and keeps working, no restart needed. |
| 1.9 | Get a phone call (or FaceTime) and hang up; trigger Siri and dismiss. | Tiles speak right after, with no delay or silent first tap. |
| 1.10 | Send Hum to the background for 1 min, come back, tap. | First tap after returning speaks right away. |
| 1.11 | Settings → Voice: pick each style (Natural, Younger, Calm); move Speed, Pitch and Volume sliders; Play a sample. | Each change is heard on the next tile tap (not the old voice). |
| 1.12 | Download a Premium voice (Settings app → Accessibility → Read & Speak → Voices) while Hum is open, then return. | Hum switches to it on its own; the “Get a more natural voice” card disappears. |
| 1.13 | Settings → “Use my own voice (Personal Voice)…” on a device with a Personal Voice. | Permission prompt; after Allow, the voice is selected and tiles speak in it. Deny shows the plain message. |
| 1.14 | Check the voices offered on first run and in Settings. | No robotic legacy voices (Fred, Junior, Kathy, Ralph…) among the suggestions (HUM-017). |

## 2. Recording, camera, photos and pictures

| # | Steps | Expected |
|---|-------|----------|
| 2.1 | Edit a tile → Record your voice. | Microphone permission is asked **only now**. Record, Stop, Play, re-record, Remove all work. |
| 2.2 | Deny the microphone, try again. | Plain orange message pointing to Settings → Privacy. Nothing crashes. |
| 2.3 | Save a recorded tile, go to the child's board, tap it. | Your recording plays (not the computer voice), instantly, and restarts on fast taps. |
| 2.4 | Take photo (iPhone/iPad). | Camera permission asked only now; the photo appears, upright, fits the tile. |
| 2.5 | Edit a tile **with a photo** → Take photo → Cancel. | The old photo is still there after Save (HUM-015). |
| 2.6 | Choose photo (Photos picker); a huge panorama; a tiny image; a HEIC; a screenshot with transparency. | Each fits inside the tile, label still visible, no black background. |
| 2.7 | Copy an image in Photos, then Paste in the tile editor; drag a picture onto the picture square (iPad split view / Mac). | Picture is used. |
| 2.8 | Create image… (Image Playground device). | Starts from the tile's words; the result becomes the picture. |
| 2.9 | Find a symbol… → ARASAAC and Mulberry; search “swing”, “let's have juice”, a nonsense word; turn on Airplane mode and search. | Results show; the phrase falls back to a single word; no-results text is friendly; offline gives a clear message. Picked symbols work offline afterwards. |
| 2.10 | Choose emoji while a photo is set. | Something visible happens or the option explains itself (HUM-028). |

## 3. Child mode by touch

| # | Steps | Expected |
|---|-------|----------|
| 3.1 | Hold the lock for exactly 3 s (count) on iPhone **and iPad**. | The ring fills and grown-up mode opens at ~3 s on both (HUM-044 fix: the hold counts from the touch itself). A 1–2 s hold never opens it. |
| 3.2 | A child-like test: tap and mash the corners, swipe from edges, hold random tiles, two-finger taps. | Never reaches grown-up mode, settings, AI, import or sync. |
| 3.3 | Settings → Grown-up lock → Two-finger triple-tap. Then do a two-finger triple-tap anywhere. | Grown-up mode opens. One-finger triple taps and two-finger double taps don't open it. |
| 3.4 | Guided Access: turn it on (Settings → Accessibility), triple-click the side button in Hum. | Works with Hum; the one-time tip appeared the first time you entered grown-up mode (HUM-041). |
| 3.5 | Reduce Motion on; tap tiles. | Only a highlight; the tile doesn't move down. |
| 3.6 | Increase Contrast on. | Tiles get a dark outline; text readable in light and dark. |
| 3.7 | Dark Mode (system and the in-app setting) on every child screen. | All tiles, the history box, the sentence strip and the Home/Back/lock are readable. |
| 3.8 | iPhone with a big board (import `Express2-v2.hum` → Replace): page through with More, Back, Home. | Pages are big enough to tap (≥ 88 pt), More always sits bottom-right, Back returns to the right page. |
| 3.9 | Rotate iPhone and iPad to landscape on the child's board and in the editor. | Grid refits; nothing overlaps; tiles keep their order. |
| 3.10 | Haptics on (iPhone only), tap tiles. | A light tap each time; none by default. |

## 4. Grown-up mode by touch (things UI tests can't do reliably)

| # | Steps | Expected |
|---|-------|----------|
| 4.1 | Drag a tile to an empty spot; onto another tile. | Moves / swaps only those two. Undo puts them back. |
| 4.2 | Drag a tile onto a folder tile's “Open” chip. | Chip says “Put inside”; the tile moves into the folder; banner offers Open folder. |
| 4.3 | Shrink a grid so tiles go to “needs a spot”, then drag them back from the tray. | Each lands where dropped; the tray empties. |
| 4.4 | iPhone phone layout: drag tiles between phone pages. | Only the phone layout changes; the iPad/Mac layout (check on another device or after sync) doesn't. |
| 4.5 | Undo after: add, edit, delete, hide, move, move to folder, duplicate, grid size, paste phrases, AI add, merge import, replace import. | Each undoes exactly one step. Delete and Replace everything (HUM-002, HUM-038) bring back exactly what was there; after one of those, older steps can't be undone any more (by design, see BUGS.md). |
| 4.6 | iPhone 17e / SE: open the editor on the starter board. | Pencil/camera badges don't hide pictures (HUM-007); folder tiles can be tapped to edit (HUM-006). |
| 4.7 | Type a very long phrase (200 characters) and a label with one long word (“Entertainment”). | The child's tile shows the label without breaking mid-word (HUM-043); VoiceOver reads the whole phrase. |

## 5. Import, export and sharing (system sheets)

| # | Steps | Expected |
|---|-------|----------|
| 5.1 | First run → Import a setup → Cancel the file picker, then Cancel the import preview too. | You're back on “How do you want to start?” each time; no blank board was made (HUM-004). |
| 5.2 | First run → Import a setup → pick `Express2-v2.hum`. | The file's Home becomes the child's Home, with its pictures (HUM-001, HUM-037). |
| 5.3 | Setup & sharing → Export all boards… → save to Files; Export “Home” only… → AirDrop to another device. | A `.hum` file is saved/sent; a “preparing” state shows if it takes a while (HUM-042). |
| 5.4 | On the other device: tap the `.hum` in Files / AirDrop / Mail → “Open in Hum”. | Hum opens; if the child is using it, the preview waits until grown-up mode. |
| 5.5 | Import the same file twice with Merge. | Second time: “0 new tiles…” and nothing duplicated. |
| 5.6 | Import `Express2-v2.hum`; time the “Preparing pictures…” bar, then look at the board right away. | Every picture shows as soon as the import closes (HUM-037). Write down how long the import took on the oldest supported iPad. |
| 5.7 | Merge `Express2-v2.hum` into the starter board. | A banner says it's in a folder called “Express2-v2” on Home, with Open; a folder tile is in Home's first empty spot; only one board is called Home (HUM-001, HUM-027). |
| 5.7 | Mac: drag a `.hum` onto the window in grown-up mode; in child mode. | Preview opens in grown-up mode only. |
| 5.8 | Import a `.obz` from CoughDrop (if supported in this build). | Boards, links and pictures come through, or a friendly “not supported yet”. |
| 5.9 | Background Hum in the middle of a big import; kill it mid-import and relaunch. | No crash, no half-imported mess, or a clear way to retry. |
| 5.10 | How to make boards with a coding agent. | Opens the CONFIG.md page in the browser. |

## 6. iCloud sync (two devices on the same Apple Account)

| # | Steps | Expected |
|---|-------|----------|
| 6.1 | Device A: Setup & sharing → Sync with iCloud on. Device B: same. | Plain status rows; no developer wording (HUM-023). Boards appear on B. |
| 6.2 | Add a tile on A while the child taps on B. | B's board changes only after ~2 s without touches; nothing moves under a finger. |
| 6.3 | Both devices offline: add a different tile to the same empty spot on each, then go online. | One keeps the spot, the other waits in “needs a spot”. No tile is lost or moved. |
| 6.4 | Edit the same tile's words on both devices offline. | Last edit wins; position unchanged. |
| 6.5 | Delete a folder on A while B's child is inside it. | B's child is taken Home, not left on an empty screen. |
| 6.6 | Turn sync off on one device, make changes, turn it back on. | Local boards are kept; no duplicates. |
| 6.7 | Device not signed in to iCloud, turn sync on. | Clear message; boards stay on the device. |
| 6.8 | Starter board on a new device that joins an existing family's iCloud. | The family's Home wins; the untouched starter is removed. |

## 7. AI helper (on an Apple Intelligence device)

| # | Steps | Expected |
|---|-------|----------|
| 7.1 | Help me set up → Turn on the helper → Describe: “My child loves trains and says ‘all aboard!’ when she wants to go.” | Suggestions keep “all aboard!” whole; no praise or compliance phrases; Add puts them in empty spots; one Undo removes them. |
| 7.2 | Paste their phrases: 5 scripts from a show. | One tile per line, never split into words. |
| 7.3 | Apple Intelligence off / model still downloading. | The helper explains why it can't run, in plain words; the toolbar button only shows when it can (HUM-031). |
| 7.4 | Ask the helper about a topic that deserves its own folder (“he loves trains, Thomas, all aboard…”) while editing Food; Add. | Tiles with no folder land on Food. A suggested new folder gets a folder tile on Food, and a banner says where the tiles went with Open (HUM-047). |
| 7.4 | Private Cloud Compute (if the entitlement is granted): run until the quota warning. | The one-line privacy note shows; quota text is clear; falls back to on-device. |
| 7.5 | A device without Apple Intelligence. | No AI button anywhere; everything else works. |

## 8. Shortcuts / Siri (App Intents)

| # | Steps | Expected |
|---|-------|----------|
| 8.1 | Shortcuts: “Add a tile to Hum” while the child uses Hum. | Nothing changes for the child; the preview appears next time grown-up mode opens. |
| 8.2 | “Import a Hum config”, “Export Hum setup”. | Same preview rule; export produces a file. |
| 8.3 | Queue three changes, then open grown-up mode. | They appear one at a time; Cancel on one moves to the next. |

## 9. Mac

| # | Steps | Expected |
|---|-------|----------|
| 9.1 | Resize the window from very small to full screen in child and grown-up mode. | No overlap; tiles stay in place; the min size is usable. |
| 9.2 | Menu commands and shortcuts: ⌘N, ⇧⌘N, ⌥⌘V, ⌘[, ⇧⌘H, ⇧⌘B, ⇧⌘G, ⌘K, ⌘Y, ⇧⌘E, ⌘⏎, ⌘,. | Each works in the editor and is disabled while a sheet is open and in child mode. |
| 9.3 | Choose file… for a picture; “Show all emoji…”. | Works. |
| 9.4 | Trackpad: there's no two-finger triple tap; the lock is the only way in. | Correct; ⌘⌥E (if added) documented. |

## 10. Accessibility and language

| # | Steps | Expected |
|---|-------|----------|
| 10.1 | VoiceOver on: child board, folder, Home/Back, history box, sentence strip. | Each tile reads its whole phrase; folders say “Opens a board”; nothing reads “folder” wrongly (HUM-035) or with doubled punctuation (HUM-021). |
| 10.2 | VoiceOver in the editor and every sheet. | Every control has a clear name; the lock's “Open grown-up settings” action works. |
| 10.3 | Switch Control: scan the child board and select a tile. | Speaks. |
| 10.4 | Largest Dynamic Type: every grown-up screen. | Text wraps, nothing truncated (compare HUM-016, HUM-020, HUM-005). |
| 10.5 | Read every grown-up screen as a parent with no tech background. | No developer words: “points”, “latency”, “render”, “CloudKit”, “phone layout”, raw errors (HUM-005, 022, 023, 032). |

## 11. Performance and robustness

| # | Steps | Expected |
|---|-------|----------|
| 11.1 | Cold launch on the oldest iPad with `Express2-v2.hum` imported. | Usable grid in under 1 s. |
| 11.2 | Open every folder of the big setup quickly. | No lag before the first tap of each folder speaks. |
| 11.3 | Low storage (fill the device), then import a big file. | Friendly error, no crash, nothing half-applied. |
| 11.4 | Leave Hum open on the child's board for an hour (Guided Access). | No memory warning, no crash, still instant. |

## 12. Re-check bugs that need a device

These were fixed in code (2026-10-12) but can only be confirmed on hardware.

| Bug | What to check |
|-----|---------------|
| HUM-014 | Is the first tap after closing a sheet / launching ever ignored on a real device? (Not reproduced by UI tests.) |
| HUM-015 | Camera → Cancel keeps the old photo. |
| HUM-031 | AI availability on a device whose model is still downloading: no form that can't work. |
| HUM-037 | Big imports: all pictures show right away; how long “Preparing pictures…” takes on an older iPad. |
| HUM-041 | The Guided Access tip appears the first time, every time (try 5 fresh installs). |
| HUM-044 | A 3-second hold opens grown-up mode on a real iPad and iPhone; a quick hold never does. |
| HUM-045 | On a 13" iPad, Settings, the tile editor, Home & folders and Setup & sharing open page-sized. |
