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
│  ├─ ParentMode/                Edit grid, TileEditor sheet, BoardManager, Settings, Share & Sync, DevLatency
│  ├─ Onboarding/                First-run flow
│  ├─ AI/                        (M5) FoundationModels helpers, @Generable types, GLP rule checks
│  ├─ Intents/                   (M4) App Intents + pending-change queue
│  ├─ Resources/                 starter.hum.json (copied from examples/), starter.<language>.hum.json
│  ├─ *.xcstrings                String Catalogs (Localizable, InfoPlist, AppShortcuts, EmojiKeywords,
│  │                             PraisePhrases); see docs/LOCALIZATION.md
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
`IPHONEOS_DEPLOYMENT_TARGET = 18.0` (raised from 17.0 on 2026-10-12: iOS 18 covers the iPhone XS/XR and every iPad from the 7th generation on, and it is the oldest simulator Xcode 27 can install), `MACOSX_DEPLOYMENT_TARGET = 14.0`,
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
  can't express (unique IDs, tile inside grid, no two tiles in one slot, linked board exists, exactly one home).
  Which boards protest and regulation tiles go on is the parent's choice (changed 2026-10). Errors are friendly: *"Tile 'snack' has no words to say."*
- **Zip without dependencies:** a minimal pure-Swift ZIP reader/writer (writer uses STORE — media is
  already compressed; reader supports STORE + DEFLATE via a small pure-Swift inflate, so `.obz` files from
  CoughDrop etc. open). CRC-32 included. Works on Linux too.
- **CLI `hum-config`:** `validate <file>`, `pack <folder> <out.hum>`, `unpack <file.hum> <folder>`
  (+ later `obz-to-hum`). Used by CI and by coding agents.
- **OBF/OBZ (M4):** `vocalization → spokenText`, `label → label`, `load_board → linkedBoardID`
  (OBF string IDs mapped to stable UUIDv5 so re-import matches), grid order → row/column, images from the zip.

---

## 4. Motor-plan stability rules (enforced in `BoardStore`, unit-tested)

1. Tiles are addressed by (row, column). The only time positions come from reading order is a parent's
   own tile size change (fewer or more across): tiles re-flow left to right, top to bottom, so their order
   stays the same (changed 2026-10).
2. Hiding a tile keeps its slot (renders as empty space in child mode).
3. Only `BoardStore.move(tile:to:)` (explicit parent drag) and `setColumns` (the parent's tile size
   change) change `row/column` and `positionUpdatedAt`.
4. **Merge import / AI apply / App Intent apply:** existing tile IDs keep their current position (incoming
   row/column ignored unless "Replace everything"). New tiles go to their requested slot if free; otherwise
   they become **unplaced** and edit mode shows *"2 new tiles need a spot"* — they never push anything.
5. **Sync conflicts:** if two tiles end up in one slot after a CloudKit merge, the tile whose
   `positionUpdatedAt` is older keeps the slot; the other becomes unplaced (parent is told). A deterministic
   resolver runs on every remote-change notification, so all devices reach the same answer.
6. A tile size change never cuts tiles off: it re-flows the tiles and gives the board the rows they need
   (the board scrolls). Parents don't set rows: the editor shows one spare empty row, and a tile placed
   there makes the board a row taller. A tile synced below the last row grows the board too.
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
  Last 200 samples kept in memory only, not shown in the app (the developer screen was removed, BUGS.md HUM-022). Nothing stored.
- **Touch path:** tiles fire on **touch-down** by default (see open questions) using a zero-distance gesture,
  so a 10+ Hz tapping child gets one sound per touch. No debounce anywhere. Visual press state is a pure
  view-state change after the audio command is queued.

---

## 6. Child mode & parent mode (summary of UI architecture)

- `AppModel` (@Observable, MainActor): current board, mode (child/parent), settings, pending changes.
- Child grid has fixed rows × columns. Tiles fill the window when they fit; when a board is taller than the
  window, it scrolls down (never sideways) and always opens at the top. Tiles on a scrolling board speak when
  the finger lifts, so a scroll never speaks. iPhone phone-layout pages don't scroll. Empty/hidden slots
  render as space. (Changed 2026-10: the child grid used to never scroll. If scrolling doesn't work for
  children, the fallback is up/down arrows next to Home and Back.)
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
  split gestalts, removals, protest-tile demotion) → a checklist preview inside the helper (every tile,
  its emoji and where it goes; Merge only — "Replace everything" makes no sense for suggestions) → parent
  taps **Add** → the same `MergePlanner` merge as a file import, one undo step. (Changed 2026-10: the
  separate Import Preview hop with a Merge/Replace choice confused parents.) "Paste phrases" uses the
  same checklist and checks without any model.
- PCC privacy: Apple processes but doesn't retain request data and we never receive it → label stays
  **Data Not Collected**.

## 8b. Symbol library (online, parent-started) — exception agreed 2026-10-11

- The owner allowed fetching AAC symbols as an exception to "no network". The picture picker's
  **Symbols** tab searches ARASAAC (`api.arasaac.org`, pictograms CC BY-NC-SA 4.0; Hum is free, so
  non-commercial use fits). Only the parent's search word is sent, from an ephemeral `URLSession` (no
  cookies, no disk cache). A chosen symbol is downloaded once and saved in the tile like a photo, so child
  mode never touches the network. Credit is shown in the picker and in Settings → About Hum.
- macOS needs the sandbox **Outgoing Connections (Client)** capability for this; iOS needs nothing.
- Privacy label: ARASAAC receives a search word that isn't linked to the user or device. Re-check the
  label wording before release.
- Second set: **Mulberry** (CC BY-SA 4.0) through the Global Symbols API (`globalsymbols.com`,
  `symbolset=mulberry`). Its pictures are SVG: macOS draws them with `NSImage`; iOS with an off-screen
  `WKWebView` (JavaScript off, non-persistent data store, CSP `default-src 'none'`), see `SVGRenderer`.
- Every picture is flattened onto white before JPEG encoding (symbol PNGs are transparent; JPEG would
  turn the background black).

## 8c. Nearby transfer (local, parent-started device-to-device) — added 2026-10-18 at the owner's request

- **Send with AirDrop…** (Share & sync) is a `ShareLink` holding the setup as a `.hum` file that is made
  only when a destination asks for it. AirDrop is Apple's; Hum adds no network code for it. On arrival,
  "Open in Hum" ends in `AppModel.requestImport` like any file.
- **Send to / Receive from a nearby device** sends the `.hum` file straight to Hum on another iPad,
  iPhone or Mac. Network framework only: Bonjour (`_hum-setup._tcp`) on the local network plus
  peer-to-peer Wi-Fi (`includePeerToPeer`). No internet, no servers, no accounts. MultipeerConnectivity
  isn't used: it is deprecated in the iOS/macOS 27 SDKs.
- Parent mode only (Share & sync is behind the grown-up lock); child mode never touches it. A device can
  be found only while its **Receive** screen is open, it is waiting, and Hum is the app in front. Any
  ending other than a finished transfer (Decline, Cancel, a timeout, an error, Hum leaving the front
  while a code or question is showing) stops the listener until the parent taps "Receive again", so
  nobody can keep putting prompts on the screen. It never restarts by itself once a file has arrived.
  Every ending says why on both screens (`cancel` carries a reason: Cancel, timeout, Hum left the
  front), with "Try again" on the sender and a prominent "Receive again" on the receiver; code fields
  start empty on every try. "Send with AirDrop…" shows "Preparing…" with Cancel while the file is made;
  zipping runs off the main actor (`ImportService.exportPackage`).
- Devices appear under a label made for each Receive screen, like "iPad 472" or "Mac 138", never the
  device's own name (a Mac's name is often its owner's). Labels are not proof of anything; the codes are.
  The listener accepts only link-local, private (RFC 1918), unique-local IPv6 and loopback addresses,
  never cellular, and not through a VPN or other tunnel (utun, ipsec, ppp…), so a device with a public
  address or a VPN peer can't reach it.
- Each transfer starts with an X25519 key exchange (CryptoKit). The sender commits to its key (sends a
  hash) before it sees the receiver's, then both derive ChaChaPoly keys and a **six-digit code**. The
  receiving screen shows the code and the parent **types it on the sending device** (passkey entry, as
  in Bluetooth pairing). Nothing about the file, not even its name, is sent until it matches, so a
  look-alike device that answers first gets nothing, and a device in the middle has a one-in-a-million
  chance. Then the sender shows a **second code** (derived the same way) and the parent types it on the
  receiver to **Accept**, so a stranger's device on the same Wi-Fi can't push a setup in either.
- Every frame after the handshake is sealed with a counter nonce (no replay, reorder or tampering); the
  file is also checked against its size and SHA-256 and written to a temporary file as it arrives.
  Limits: 200 MB per file (older iPads must import it in memory), 128 KB per frame, 1 KB per offer.
  The zip reader works on the mapped file in place. Timeouts: 10 s to finish the handshake; 30 s
  without a whole frame while sending (a trickle of bytes doesn't count); 2 minutes for a person to
  type a code or answer. Partial files left by a transfer that never finished are deleted at the next
  start, and are unreadable while the device is locked (iOS file protection).
- The received bytes go to `AppModel.requestImport(data:fileName:)`, the same validator, preview and
  Merge/Replace as every import. Nothing changes until the parent chooses. The zip reader refuses more
  than 20 000 files, more than 600 MB unpacked, impossible compression ratios and overlapping entries
  before it unpacks anything (`ZipArchive.read`), which protects every import path. The import itself
  still runs on the main actor, like every import (moving it off is a separate change to ImportService).
- People on the same network can see that Hum is on its Send or Receive screen (the Bonjour service
  name) and roughly how big a file is. Security review: 2026-10-18; findings and fixes in PR #15.
- Needs `NSLocalNetworkUsageDescription` and `NSBonjourServices`, and on macOS the sandbox's incoming
  connections (server) entitlement for the listener. Code: `Store/NearbyProtocol.swift`,
  `Store/NearbyTransfer.swift`, `Store/NetworkTransport.swift`, `ParentMode/NearbyTransferView.swift`.

## 9. Privacy manifest

`PrivacyInfo.xcprivacy`: `NSPrivacyTracking = false`, no tracking domains, no collected data types.
Required-reason APIs actually used: `UserDefaults` (CA92.1 — app's own data) and `mach_absolute_time()`
for the tap-to-sound latency probe (35F9.1). No file timestamp APIs are used (re-checked 2026-10-12).
Re-audited each milestone.

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
