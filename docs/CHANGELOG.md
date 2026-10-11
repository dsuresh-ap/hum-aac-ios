# Changelog

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
