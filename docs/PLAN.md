# Hum — Implementation Plan

Status: **draft for approval** · Toolchain checked: Xcode 27.0 (27A266a), Swift 6.4, iOS/macOS 27.0 SDKs.

Development order (per maintainer): **macOS first** for the core loop (fastest build/run, no simulator),
with every file written multiplatform from day one (`#if os(iOS)` seams only where the platform differs:
audio session, camera, haptics, two-finger gestures). iOS/iPadOS gets turned on and verified right after
the core works on Mac.

---

## 1. Repository layout

```
hum-aac-ios/
├─ Hum.xcodeproj                 (renamed from hum-aac-ios.xcodeproj; one multiplatform app target "Hum")
├─ Hum/                          app sources (file-system synchronized group)
│  ├─ App/                       HumApp, AppModel (root @Observable), scene/commands
│  ├─ Model/                     SwiftData @Model types + ModelContainer factory
│  ├─ Store/                     BoardStore (all mutations, undo, motor-plan rules), ImportService
│  ├─ Audio/                     AudioEngine, VoiceSampler (render node), SpeechRenderer, ClipCache, LatencyProbe
│  ├─ ChildMode/                 BoardGridView, TileView, HomeButton, EditGate
│  ├─ ParentMode/                Edit grid, TileEditor sheet, BoardManager, Settings, Setup & Sharing, DevLatency
│  ├─ Onboarding/                First-run flow
│  ├─ AI/                        (M5) FoundationModels helpers, @Generable types, GLP rule checks
│  ├─ Intents/                   (M4) App Intents + pending-change queue
│  ├─ Resources/                 starter.hum.json (copied from examples/), Localizable.xcstrings
│  └─ PrivacyInfo.xcprivacy
├─ HumTests/  HumUITests/
├─ Packages/HumConfig/           dependency-free Swift package (library + `hum-config` CLI), builds on macOS AND Linux
├─ schema/hum.schema.json        JSON Schema draft 2020-12
├─ examples/                     starter.hum.json, food.hum.json, linked-boards.hum.json
├─ docs/  PLAN.md CONFIG.md CHANGELOG.md
├─ AGENTS.md README.md LICENSE (Apache-2.0) CONTRIBUTING.md CODE_OF_CONDUCT.md
└─ .github/workflows/ci.yml
```

Build settings changes to the existing project: `SWIFT_VERSION = 6`, strict concurrency complete,
`IPHONEOS_DEPLOYMENT_TARGET = 17.0`, `MACOSX_DEPLOYMENT_TARGET = 14.0`,
`SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx` (drop visionOS for now), real bundle ID,
keep `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (UI-heavy app; audio/render code is explicitly `nonisolated`).
Both SDKs still accept these targets (iOS min 15.0, macOS min 13.1 in the 27.0 SDKs — verified).

---

## 2. Data model (SwiftData, CloudKit-compatible from M1)

CloudKit rules respected: every attribute optional or defaulted, no `@Attribute(.unique)`, all relationships
optional, delete rules `.cascade`/`.nullify` only, no ordered relationships.

```swift
@Model final class Board {
  var id: UUID = UUID()               // stable config ID (NOT unique-constrained; dedupe in code)
  var name: String = ""
  var rows: Int = 3
  var columns: Int = 3
  var isHome: Bool = false
  var createdAt: Date = .now
  var updatedAt: Date = .now
  var extraJSON: Data?                // unknown fields from config files, preserved for round-trip
  @Relationship(deleteRule: .cascade, inverse: \Tile.board) var tiles: [Tile]? = []
}

@Model final class Tile {
  var id: UUID = UUID()
  var label: String = ""
  var spokenText: String = ""         // one whole gestalt
  var functionRaw: String?            // protest | request | connection | comment | regulation | other
  var colorHex: String?
  var linkedBoardID: UUID?            // plain UUID, not a relationship (no cycles, survives deletes)
  var isHidden: Bool = false
  var row: Int?                       // nil = "unplaced" (see §4) — never shown to the child
  var column: Int?
  var positionUpdatedAt: Date = .now  // only bumped by an explicit parent move
  var symbol: String?                 // emoji placeholder for starter tiles
  @Attribute(.externalStorage) var imageData: Data?   // HEIC/JPEG ≤1024px long edge
  @Attribute(.externalStorage) var audioData: Data?   // M3 recorded phrase (m4a/AAC)
  var createdAt: Date = .now
  var updatedAt: Date = .now
  var extraJSON: Data?
  var board: Board?
}

@Model final class SharedSettings { … }   // settings that should follow the family across devices
```

**Settings split.** Synced (SwiftData `SharedSettings`): grid defaults, show labels, label position,
sentence strip, appearance. Device-local (`UserDefaults`, never synced): voice identifier/rate/pitch/volume
(installed voices differ per device), retrigger mode, haptics, edit-gate type, iCloud on/off, AI on/off and mode,
first-run-complete. If CloudKit produces two `SharedSettings` rows (two devices created one offline) we keep
the most recently updated and delete the other — settings contain no positions, so this is motor-plan safe.

**Media strategy:** `.externalStorage` `Data` as the prompt suggests. It syncs through CloudKit as CKAssets.
Images are downscaled on import/capture (ImageIO, HEIC where supported, JPEG fallback, quality 0.8).

---

## 3. Config format & HumConfig package

- `hum.json` top-level: `formatVersion` (1), `boards[]`, `settings?`, `homeBoardID?`. Board: `id, name, rows,
  columns, isHome, tiles[]`. Tile: `id, label, spokenText, row, column, function?, color?, linkedBoardID?,
  hidden?, image?` (relative path in `media/`), `audio?`, `symbol?`.
- **Unknown fields preserved:** every Codable type decodes into known fields + `extra: [String: JSONValue]`
  and re-encodes both. The app stores `extra` in `extraJSON`, so app export ⇄ import is lossless.
- **Migration:** `formatVersion < current` → step-wise migrators; `> current` → friendly
  "This setup was made with a newer Hum. Please update Hum to open it."
- **Validation:** schema-driven, dependency-free. HumConfig ships a small JSON Schema validator covering the
  keywords our schema uses (`type, properties, required, additionalProperties, items, enum, const,
  minLength, maxLength, minimum, maximum, pattern, format: uuid, $ref/$defs`), plus semantic checks the schema
  can't express (unique IDs, tile inside grid, no two tiles in one slot, linked board exists, exactly one home,
  protest/regulation tiles reachable on Home). Errors are friendly: *"Tile 'snack' has no words to say."*
- **Zip without dependencies:** a minimal pure-Swift ZIP reader/writer (writer uses STORE — media is
  already compressed; reader supports STORE + DEFLATE via a small pure-Swift inflate, so `.obz` files from
  CoughDrop etc. open). CRC-32 included. Works on Linux too.
- **CLI `hum-config`:** `validate <file>`, `pack <folder> <out.hum>`, `unpack <file.hum> <folder>`
  (+ later `obz-to-hum`). Used by CI and by coding agents.
- **OBF/OBZ (M4):** `vocalization → spokenText`, `label → label`, `load_board → linkedBoardID`
  (OBF string IDs mapped to stable UUIDv5 so re-import matches), grid order → row/column, images from the zip.

---

## 4. Motor-plan stability rules (enforced in `BoardStore`, unit-tested)

1. Tiles are addressed by (row, column). Nothing in the app computes positions from list order.
2. Hiding a tile keeps its slot (renders as empty space in child mode).
3. Only `BoardStore.move(tile:to:)` (explicit parent drag) changes `row/column` and `positionUpdatedAt`.
4. **Merge import / AI apply / App Intent apply:** existing tile IDs keep their current position (incoming
   row/column ignored unless "Replace everything"). New tiles go to their requested slot if free; otherwise
   they become **unplaced** and edit mode shows *"2 new tiles need a spot"* — they never push anything.
5. **Sync conflicts:** if two tiles end up in one slot after a CloudKit merge, the tile whose
   `positionUpdatedAt` is older keeps the slot; the other becomes unplaced (parent is told). A deterministic
   resolver runs on every remote-change notification, so all devices reach the same answer.
6. Shrinking a board's grid is blocked if it would cut off tiles ("Move or remove these 3 tiles first").
7. Child mode renders from a **snapshot** of the board. Incoming changes (sync, intent, import) are applied
   to the snapshot only after a quiet period (≥ 2 s since the last touch) — never mid-tap.

---

## 5. Audio engine (M1) — the core of the app

Design: a tiny **sampler** instead of player nodes, so retrigger, fades and overlap are sample-accurate.

```
AVAudioEngine (started once, kept running while foreground)
  └─ AVAudioSourceNode "VoiceSampler"  (mono Float32 @ hardware rate)
        └─ mainMixerNode → outputNode
```

- **Clips:** `PCMClip` = immutable, pre-allocated `Float` samples at the engine rate (resampled once with
  `AVAudioConverter` when rendered). The render callback only reads memory — no allocation, no ObjC, no locks
  held by the main thread longer than a pointer swap (`OSAllocatedUnfairLock.withLockIfAvailable`; if
  contended, the command is picked up in the next 5 ms cycle).
- **Voices:** up to 8. *Restart* (default): new tap fades the active voice out over 3 ms and starts the new
  clip at sample 0 in the same render cycle. *Let speech finish*: taps during playback queue at most one
  pending clip (taps are never rejected; latest wins). *Overlap*: each tap takes a free voice (oldest voice
  is faded and stolen at 8). Each voice has a 2 ms fade-in to avoid DC clicks at clip start.
- **Pre-render:** `SpeechRenderer` (serial actor) uses `AVSpeechSynthesizer.write(_:toBufferCallback:)`
  and concatenates the callback buffers into one clip. Rendering order: current board → boards one link
  away. Cache key = `sha256(spokenText|voiceID|rate|pitch)`. **Memory LRU** (cap ~64 MB ≈ 10+ minutes of mono
  float audio) + **disk cache** in `Caches/Speech/` (raw float32 files, auto-rebuildable, excluded from
  backup). Voice/rate/pitch change → keys change → re-render in the background.
- **Fallback:** uncached tap → speak live with a separate `AVSpeechSynthesizer` immediately (target
  < 150 ms) and render the clip in the background for next time.
- **Session (iOS):** `.playback`, mode `.default`, `setPreferredIOBufferDuration(0.005)`, activate once at
  launch, never deactivate between taps. Background → `engine.pause()`; foreground → restart.
  Interruption-ended / route-change / media-services-reset → rebuild + restart immediately.
  macOS has no AVAudioSession; `AVAudioEngineConfigurationChange` handles device changes.
- **Recorded audio (M3):** decoded with `AVAudioFile` into a `PCMClip` when the board loads. Recording
  plays if present, else TTS.
- **Latency probe:** the touch handler stamps `mach_absolute_time()`; the render callback stamps the host time
  of the first rendered sample of that clip; latency = render time − touch time + `outputLatency` + IO buffer.
  Last 200 samples kept in memory only, shown on the hidden developer screen (min/median/p95/max). Nothing stored.
- **Touch path:** tiles fire on **touch-down** by default (see open questions) using a zero-distance gesture,
  so a 10+ Hz tapping child gets one sound per touch. No debounce anywhere. Visual press state is a pure
  view-state change after the audio command is queued.

---

## 6. Child mode & parent mode (summary of UI architecture)

- `AppModel` (@Observable, MainActor): current board, mode (child/parent), settings, pending changes.
- Child grid is a fixed `Grid` sized to the window (no scrolling, ever). Empty/hidden slots render as space.
  Linked tiles show a folder corner; Home button fixed top-leading. Lock gate fixed in the opposite corner.
- **Edit gate:** (1) press-and-hold lock 3 s with a filling ring (default); (2) two-finger triple-tap
  (iOS via a `UIGestureRecognizer` representable; on Mac this option is replaced by a menu command
  ⌘⌥E since a trackpad has no two-finger tap count). One-time Guided Access tip (iPad/iPhone).
- Parent mode reuses the same grid with edit affordances: tap empty → Add, tap tile → Edit, drag to move,
  "needs a spot" tray for unplaced tiles, Undo (SwiftData `UndoManager` + import snapshots).
- Sheets & forms follow the order and wording in the brief. Visual design pass comes last (milestone 4 of
  the maintainer's plan) — functional UI first, with design tokens centralized so the design pass is cheap.

---

## 7. iCloud sync (M4) — API check

- `ModelConfiguration(schema:url:cloudKitDatabase: .private("iCloud.<bundle-id>"))` vs `.none`.
  Toggling sync re-creates the `ModelContainer` against the **same store file** (history tracking keeps
  local data). The switch only happens from Settings in parent mode, with the plain-language explanation.
- Needs the iCloud (CloudKit) capability + Background Modes → Remote notifications on iOS.
- Conflict policy: Core Data/CloudKit mirroring exports changed attributes per record and the store uses
  property-level merge (`NSMergeByPropertyObjectTrumpMergePolicy`) — effectively last-edit-wins per field.
  Position collisions are then repaired by the deterministic resolver in §4.5.
- **Privacy label:** data in the user's *private* CloudKit database is not accessible to the developer, so
  Apple's guidance treats it as not "collected" → **Data Not Collected** stays true. No CloudKit public DB,
  no shared zones.

## 8. AI helper (M5) — API check (verified in the iOS 27.0 SDK interface)

- On-device: `SystemLanguageModel.default`, `.availability` (`.available` / `.unavailable(.deviceNotEligible
  | .appleIntelligenceNotEnabled | .modelNotReady)`), `LanguageModelSession(model:instructions:)`,
  `session.respond(to:generating:)` with `@Generable` / `@Guide`. Available since **iOS/macOS 26** — I propose
  gating on-device AI at 26 (more devices) and PCC at 27, instead of 27 for both. Say if you prefer 27 only.
- Private Cloud Compute: `PrivateCloudComputeLanguageModel()` (iOS/macOS 27), `.availability`
  (`.deviceNotEligible | .systemNotReady`), `.quotaUsage`, used via `LanguageModelSession(model: some LanguageModel, …)`.
  ⚠️ **Correction to the brief:** PCC needs a **managed entitlement** that Apple grants on request
  (currently limited to Small Business Program developers under 2M first-time downloads). The code will be
  written and compiled behind a feature flag; it only works once the entitlement is approved for the
  App ID. Until then the PCC option is hidden.
- Only text (parent's request + labels/spokenText/function tags) is sent. Never images/audio.
- Output → `HumConfig` DTOs → same validator → `GLPRuleCheck` (rejects/fixes praise/reward/compliance phrases,
  split gestalts, removals, protest-tile demotion) → the same Import Preview → parent taps **Apply**.
- PCC privacy: Apple processes but doesn't retain request data and we never receive it → label stays
  **Data Not Collected**.

## 9. Privacy manifest

`PrivacyInfo.xcprivacy`: `NSPrivacyTracking = false`, no tracking domains, no collected data types.
Required-reason APIs actually used: `UserDefaults` (CA92.1 — app's own data), file timestamps for the
disk cache (C617.1 — inside app container). Re-audited each milestone.

## 10. CI

GitHub Actions `macos-26` runner with the newest Xcode selected (`xcodes`/`xcode-select`):
`swift test` for HumConfig (+ an `ubuntu-latest` job — proves the package is Linux-clean),
`hum-config validate examples/*.json`, `xcodebuild build test` for macOS, iOS Simulator, iPadOS Simulator.
Risk: if the hosted image doesn't have Xcode 27 yet, the app jobs pin to the newest available and skip
SDK-27-only code paths via `#if compiler`/`#available` (FoundationModels PCC symbols).

---

## 11. Milestones (as specified, with order adjusted for macOS-first)

| # | Scope | Platform focus |
|---|---|---|
| M1 | Project setup, license headers, privacy manifest, SwiftData model, HumConfig (types, schema, validator, zip, CLI), AGENTS.md, CONFIG.md draft, examples, starter board via import path, child grid, audio sampler + TTS pre-render cache, latency screen, CI | **macOS first**, then iOS/iPadOS build green |
| M2 | Edit gate, tile add/edit/move/hide/delete with photos, boards + links, settings, voices + Personal Voice, first-run | Mac + iPad |
| M3 | `.hum` import/export + preview + merge rules + undo, UTType/document type, recorded audio, sentence strip | all |
| M4 | iCloud sync + resolver, OBF/OBZ, App Intents + pending queue | all |
| M5 | Foundation Models helpers + GLP checks | all |
| M6 | Accessibility, String Catalog, README, screenshots, **design pass** (kid-friendly UI, easy parent setup) | all |

Each milestone ends with: all 3 platforms build, tests pass, `docs/CHANGELOG.md` updated.

## 12. Work split: local vs cloud agents

Cloud agents (Claude Code on the web) run in **Linux** containers — no Xcode, so they can't build the app.
They are a great fit for the dependency-free parts, which we deliberately keep Linux-clean:
- HumConfig: OBF/OBZ converter, inflate/zip hardening, validator edge cases, golden-file tests.
- `schema/`, `examples/`, `docs/CONFIG.md`, `AGENTS.md`, README/GLP background, CONTRIBUTING.
- GLP rule-check engine (pure Swift, string rules) + its adversarial test corpus.
App/UI/audio/SwiftData work stays local (this machine, Xcode MCP).

## 13. Open questions

1. **Bundle ID / org** (needed for CloudKit container + UTType): e.g. `org.humaac.Hum` with UTI `org.humaac.hum`.
2. **GitHub repo name** (public, Apache-2.0): e.g. `dsuresh-ap/hum-aac`.
3. **Touch-down vs lift-off activation.** Touch-down is ~50–150 ms faster and best for vocal stimming;
   lift-off lets a child slide off to "cancel". Proposal: touch-down default, lift-off as a setting.
4. **On-device AI on iOS/macOS 26** (proposal above) or keep 27-only?
5. **visionOS:** the template enabled it; I'll drop it for now unless you want it.
6. **Repo/app name:** keep the Xcode project named `hum-aac-ios` or rename to `Hum` (proposal: rename target
   and product to `Hum`; repo folder can stay).
