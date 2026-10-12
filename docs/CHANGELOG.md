# Changelog

## Unreleased: About Hum and picture credits

- **Settings → About Hum** shows the version, what Hum is (a communication tool, not a medical device
  or therapy), links to the privacy policy, help, source code and licence, and the symbol credits.
- **First run** says how to get back into settings and links to the privacy policy.
- **The AI helper** says that suggestions can be wrong and nothing is added until you choose it.
- **Symbol credits travel with the picture.** A symbol from ARASAAC or Mulberry keeps its credit in the
  tile (shown under the picture in the tile editor), in exported files (`imageCredit`, plus a
  `CREDITS.txt` in the `.hum`) and through undo, duplicate and import. A photo clears it.

## Unreleased: fixes from the end-to-end test pass

All 47 bugs in `docs/testing/BUGS.md` except HUM-014 (not reproduced). The biggest:

- **Merging a setup with its own Home** makes that Home a folder named after the file, with a tile on
  your Home that opens it (like TD Snap's "import and link"). Before, every imported board was unreachable.
- **Undo after deleting a tile or folder, and after "Replace everything"**, brings back exactly what was
  there. After one of these, older steps can't be undone.
- **AI suggestions stay on the board you're editing.** A suggested new folder gets a folder tile there,
  and a banner after any import or Add says where things went.
- **Imported SVG symbols are drawn during the import**, so the board has its pictures when it closes.
- **First run:** "Import a setup" no longer makes an empty Home first; the starter card says it is 5 × 4.
- **No more static at the end of phrases:** speech is resampled once per phrase instead of in 11 ms
  chunks, and clips fade to silence at the end. Cached clips render again once after updating.
- **Export opens the share sheet on iPhone and iPad** (AirDrop, Messages, Mail, Save to Files) instead
  of going straight to Files.
- **iPhone sideways:** tiles show their picture beside the label instead of losing it, and the editor
  scrolls instead of piling tiles on top of each other.
- **The lock opens after 3 seconds on iPad too.**
- **Plainer wording:** no "88 points", "phone layout", developer screens, CloudKit steps or raw errors.
  The latency screen is removed. Robotic legacy voices are no longer offered.
- Long-press Delete asks first; renaming a folder renames its tile; making a board Home warns when it
  lacks the protest tiles; labels shrink instead of breaking mid-word.

## Unreleased

- **Fixed:** importing from Setup & sharing showed the preview only after the sheet was closed. The
  preview now opens right over it.
- **Fixed:** pictures saved as SVG (by builds before "Process imported pictures", or synced from another
  device) showed as blank tiles. Hum now converts them to JPEG at launch, and the Mac draws them meanwhile.
  Big imports convert in batches without freezing the app.
- **Phone layout:** on iPhone, a board wider than 4 columns or taller than 8 rows is shown as pages of
  4 × 8 instead of shrinking the board. Tiles fill the phone pages in the board's reading order the first
  time, then keep their phone spot (the phone's own motor plan); "More" in the bottom-right spot opens the
  next page and Back returns. Moving tiles on the iPhone only changes the phone layout, so iPad and Mac
  keep theirs, and nothing goes to the "needs a spot" tray when you switch devices. Phone spots sync.
- **Imports show progress and don't freeze the app:** pictures are prepared on background threads,
  several at a time, with a progress bar ("Preparing pictures… 340 of 1,581"). Only the final save runs
  on the main thread, so the whole import stays one undo step.
- **Fixed:** an iPhone crash while drawing big boards: SwiftUI resolves Hum's Light/Dark colours on its
  render thread, and they were marked main-thread-only, which the Swift runtime stops on.
- **Fixed:** a crash when an import or a synced change deleted tiles while their SVG pictures were being
  converted, or while edit mode was still drawing them.
- **Fixed:** a device that joined iCloud sync could take Home away from an imported setup: it uploaded
  its own starter board, and the "two Homes" repair kept the *oldest* Home. Now a family's own Home
  always beats the starter, then the newest Home wins (the latest import sticks on every device), and
  a starter board nobody changed is removed instead of lingering as a second "Home".
- **Fixed:** tiles with their own colour (e.g. a near-white one from an import) had light labels in Dark Mode and were
  unreadable. Labels, folder marks, the sentence strip and history now pick dark or light text by the
  tile colour's contrast.

## Unreleased: imported pictures, pictures that fit

- **Imported pictures are processed like photos added in the app:** resized to 1024 px, flattened onto
  white, saved as JPEG. Hum's own small JPEGs are kept byte for byte (no quality loss on round trips);
  files that aren't pictures never replace a tile's picture; SVG works (on iOS it's drawn right after the
  import). SVGs without a `viewBox` now scale correctly.
- **Fixed:** big or square pictures (e.g. from Image Playground) spilled outside their tile in edit mode
  and pushed the label out in child mode. Pictures now fit inside the tile, whole, with the label below.
- Xcode previews for tile pictures (child and edit mode).

## Unreleased: second symbol set, duplicate, paste

- **Mulberry symbols** next to ARASAAC in "Find a symbol…" (switch with the segmented control; the choice
  is remembered). Mulberry's SVG pictures are drawn by `NSImage` on Mac and a locked-down WebKit view on iOS.
- **Fixed:** transparent symbol pictures (ARASAAC PNGs) would have turned black when saved as JPEG; every
  picture is now flattened onto white.
- **Duplicate** in a tile's menu (copy goes to the first empty spot, nothing moves) and **Paste** a picture
  into the tile editor.
- `CLAUDE.md`: build and test through the Xcode MCP, on an iOS 27 simulator.

## Unreleased: easier tiles and folders, pictures, shortcuts

- **Folders are easier.** Every empty spot offers "Tile" and (when roomy, or by right-click / long-press)
  "Folder". A new folder asks for a name only, is one undo step, and opens right away so you can fill
  it. "Move to folder" on a tile's menu (or drop a tile on a folder's Open button) moves it inside,
  keeping its photo and recording; it takes the first empty spot there. Renaming a folder tile renames
  its folder. "Boards" is now "Home & folders"; folders no tile opens are flagged, and "Make folder"
  also adds the tile that opens it.
- **Tile editor:** the phrase field is focused on open, Return saves, ⌘Return saves anywhere, Cancel asks
  before throwing away changes. Color, hide and delete moved under "More options".
- **Pictures:** an emoji is picked from the tile's words until there's a photo (offline, ~200 AAC-focused
  emoji with search), "Find a symbol…" searches the ARASAAC symbol library, and "Create image…" opens
  Apple Image Playground (Apple's own styles only).
- **Paste phrases:** add many tiles at once, one line per tile, no AI needed.
- **AI helper:** one page — turn on, describe or paste, tick the suggested tiles, Add. Return no longer
  closes the page; Return (or ⌘Return in the phrase list) suggests. Suggestions come with an emoji.
- **Keyboard shortcuts** (Mac menu bar; hold ⌘ on iPad): ⌘N new tile, ⇧⌘N new folder, ⌥⌘V paste phrases,
  ⌘[ back, ⇧⌘H Home, ⇧⌘B Home & folders, ⇧⌘G grid size, ⌘K AI helper, ⌘Y history, ⇧⌘E setup & sharing,
  ⌘, settings, ⌘Return done editing. There is no shortcut into editing: the grown-up lock stays the only way in.
- **iCloud status:** Setup & sharing shows the iCloud account state, when boards were last sent and
  received, sync errors in plain words, and how developers can find the records in the CloudKit Console.
- **Fixed:** jumping to a board from the board list left a stale Back button; the grid-size sheet now asks
  before discarding a new size; switching iCloud sync could crash SwiftData through a stale undo manager.
- **Tests:** AI pipeline with a fake model (prompt contents, praise/split repair, duplicates, emoji, retry
  on context overflow, PCC fallback), a live on-device model test (`TEST_RUNNER_HUM_LIVE_AI=1`), folder
  moves and renames, emoji suggestions, pasted phrases.

## Unreleased: voices, AI resilience, app icon

- **Voices:** Hum now uses the most natural voice installed (Premium > Enhanced > Standard, Apple's
  default breaks ties) and switches automatically when a better one is downloaded, including the
  Premium version of the voice a parent picked. A "Get a more natural voice" card with exact steps shows
  while only robotic compact voices exist. Style presets: Natural, Younger (higher, a little slower) and
  Calm. Apple has no children's voices; the app points parents to sibling recordings for a real child's voice.
- **AI helper:** on-device by default. Private Cloud Compute (when entitled) falls back to on-device when
  the network or service is down, shows today's quota before it runs out (with Apple's own options), and
  switches to on-device when the quota is used. Friendly messages for every model error, and an automatic
  retry with a shorter prompt when a big setup overflows the on-device context.
- **App icon:** "hum", a gentle wave of five soft keys in the tile colors on Hum's teal. iOS light, dark
  and tinted variants and a macOS icon, all rendered by `tools/render-icon.swift` so anyone can tweak it.

## Unreleased: tests and iCloud sync

- **App tests:** `HumTests` (41 Swift Testing tests: motor-plan rules for every edit path and undo,
  SwiftData config round-trips including golden files and unknown fields, merge never moving or deleting,
  folders/Back/Home and link loops, history, sync conflict repair, and the audio sampler: 600 taps at
  20/s with none dropped, click-free retrigger, restart/finish/overlap, cache LRU/disk, engine restarts)
  and `HumUITests` (6 flows: first run, tap → history, short hold doesn't unlock, gate → add tile → undo,
  folder → Back, import preview → apply → undo). App unit tests run in CI on an iOS Simulator.
- **Fixed (found by tests):** undo steps were recorded outside their group, so one Undo could revert
  more than the last change; the starter board could be undone away after setup.
- **iCloud sync (off by default):** SwiftData + CloudKit private database `iCloud.dhananjaysuresh.hum-aac`,
  same store file on or off, falls back to local if iCloud is unavailable. `SyncResolver` repairs
  duplicates, extra Home boards and spot collisions after remote changes: the tile placed first keeps
  its spot; the other waits in "needs a spot". Child view refreshes only after 2 s without touches.
  Remote-notification background mode on iOS.

## Unreleased: folders, grid size, history

- **Folders and navigation:** a Back button next to Home (fixed slot, so nothing shifts), loop-safe
  board path, clearer folder mark, silent folder tiles (no phrase, just open the board), "Make this tile a
  new folder" in the tile editor, Open folder in edit mode (button, context menu and VoiceOver action) with
  Back to the parent board, and an optional "go back Home after a tile in a folder speaks" setting.
- **Grid size:** a grid button on the editing band opens presets (2×2 to 6×8), steppers and a live
  preview. Bigger grids add empty spots. Smaller grids show which tiles won't fit and, only if the parent
  agrees, move them to the "needs a spot" tray (never deleted, nothing else moves). Default size for new
  boards in Settings.
- **History:** an optional history box on the child's screen (recent phrases, tap to say again) and a
  History screen for parents (grouped by day, repeats collapsed, clear). Stored on this device only.
- Config format: `spokenText` may be empty for folder tiles that have `linkedBoardID` (41 tests).

## Unreleased: Milestones 2–5 (in progress)

- **M2 Parent mode:** `BoardStore` (undoable edits; tiles move only by explicit drag; grids grow freely and
  shrink only when nothing is cut off), parent editor with drag-to-move and a "needs a spot" tray, tile editor
  (photo, camera, file/drag on Mac, play preview, label, color/function, links, hide, delete), board manager,
  settings (voices, Personal Voice, speech, tapping, display, gate), first-run setup, two-finger triple-tap
  gate (iOS), Guided Access tip, optional haptics.
- **M3 Import/export:** import preview (Merge default / Replace everything with automatic backup), undo,
  `.hum` export (whole setup or one board), `.hum` UTType and document type, Open in Hum, Mac drag-and-drop,
  per-tile parent recordings (mic asked only on Record), sentence strip (off by default).
- **M4 (partial):** App Intents (Add a Tile, Import a Setup, Export Setup) that queue changes for the parent's
  preview instead of applying them. iCloud sync and OBF/OBZ are still to do.
- **M5 AI helper:** Foundation Models (on-device on 26+, Private Cloud Compute on 27+ behind availability
  and compiler checks), guided generation, `ProposalChecker` code-level GLP rules (praise/compliance removed,
  split gestalts rejoined, dedupe, short labels, protest tiles also offered on Home, add-only placement),
  the same import preview as files. Verified live on-device on macOS 27.

## Unreleased: Milestone 1 (in progress)

**Done**
- Project set up as one SwiftUI multiplatform target (iOS/iPadOS 17+, macOS 14+), Swift 6 with
  strict concurrency, bundle ID `com.dhananjaysuresh.hum-aac`. Builds with 0 warnings on macOS and iOS Simulator.
- `HumConfig` Swift package (no dependencies, Linux-clean): Codable config types that keep unknown fields,
  a JSON Schema validator with friendly messages, GLP rule checks, version migration hook, pure-Swift
  ZIP reader/writer (STORE + DEFLATE), `.hum` packages, the merge planner (motor-plan safe imports),
  and the `hum-config` CLI (`validate`, `pack`, `unpack`). 33 tests.
- `schema/hum.schema.json` (draft 2020-12) with agent-oriented descriptions; `examples/` (starter, food,
  linked boards); `docs/CONFIG.md`; `AGENTS.md`.
- CloudKit-compatible SwiftData model (`Board`, `Tile`) and `ConfigBridge` (import/export through the
  merge planner). The starter board loads through the normal import path.
- Low-latency audio: one always-running `AVAudioEngine` with a custom real-time sampler
  (`AVAudioSourceNode`), sample-accurate retrigger with 3 ms fades, restart/finish/overlap modes,
  TTS pre-rendered with `AVSpeechSynthesizer.write`, leading silence trimmed, memory LRU + disk cache,
  live-speech fallback, interruption/route-change restarts.
- Child mode grid (touch-down activation, fixed Home button, 3-second hold lock), developer latency
  screen with a 20-taps/second stress test, privacy manifest, CI workflow.

**Still to do in M1**
- App unit and UI test targets (waiting on the Xcode target step), audio tests, latency measured on real devices.
