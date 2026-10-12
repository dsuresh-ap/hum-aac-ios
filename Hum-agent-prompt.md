# Coding Agent Prompt — "Hum" (free, open-source AAC for Gestalt Language Processors) — v3

Copy everything below the line into your coding agent.

---

## Role

You are a senior Apple-platform engineer. You will build **Hum**, a free, open-source AAC (Augmentative and Alternative Communication) app for **iOS, iPadOS, and macOS**. The primary users are **autistic children (about age 2–8) who are Gestalt Language Processors (GLPs)** and are minimally speaking. The secondary users are **parents and caregivers**, who set the app up.

Do not start coding right away. First read this whole prompt, then write `docs/PLAN.md` (architecture, data model, config format, milestone breakdown, open questions). Stop and wait for my approval of the plan before you write app code.

## Why this app exists (read this — it drives every design choice)

Gestalt Language Processors learn language in **whole chunks** ("gestalts"), not single words. A child may say "let's get out of here!" (from a movie) to mean "I want to leave." In the Natural Language Acquisition (NLA) framework (Marge Blanc), children move through stages: whole gestalts first, then mixing parts of gestalts, then single words, then their own grammar.

Most AAC apps are built for **analytic** learners: a core-word grid where the child builds sentences word by word. That model does not fit a Stage 1–2 GLP. Hum is built for whole phrases first.

The product is **neurodiversity-affirming** and **non-behavioral** (no ABA patterns). This is a core requirement, not a style choice.

## Hard product rules (never break these)

1. **Free forever.** No in-app purchases, no ads, no subscriptions, no "pro" tier, no tip jar inside the app.
2. **No analytics, no tracking, no developer servers.** No third-party SDKs. No crash reporters that phone home. The app must work fully offline. The only network use allowed is **opt-in, parent-started**: (a) iCloud sync to the user's **private** CloudKit database, (b) Apple **Private Cloud Compute** through the Foundation Models framework, and (c) the symbol search (ARASAAC, Mulberry via Global Symbols), an exception the owner added later (see `docs/PLAN.md` §8b). Both are off until a parent turns them on. No third-party LLM providers (no Claude/Gemini/OpenAI routing) in the app. The App Store privacy label must be "Data Not Collected" — confirm in PLAN.md that iCloud and PCC use keeps this label true. Add a `PrivacyInfo.xcprivacy` manifest that declares no tracking and lists only required-reason APIs actually used.
3. **No accounts, no sign-in.** Data stays on the device or in the family's own iCloud. (COPPA: we collect nothing, so we must keep it that way.)
4. **No external dependencies** unless I approve them. Use only Apple frameworks (SwiftUI, SwiftData, CloudKit, FoundationModels, AVFoundation, PhotosUI, UniformTypeIdentifiers, AppIntents, etc.).
5. **Never gate communication.** No tile is ever locked, timed out, hidden behind a task, or "earned." Protest and refusal tiles ("no", "stop", "all done", "I don't like it") have the **same size and visual weight** as request tiles.
6. **No reward or compliance mechanics.** No stars, tokens, streaks, scores, "good job!" sounds, confetti, or praise animations. A tap speaks. That is all.
7. **Repeated tapping is valid communication** (and can be stimming). Never block it, never show a warning, never shame it. Fast repeated taps (10+ per second) must each produce sound. No debounce, no rate limit, no "please wait."
8. **Motor-plan stability.** A tile never moves to a new position on its own. Adding or hiding a tile must not shift the other tiles. Hidden tiles keep their slot (empty space), unless the parent explicitly moves them. **This rule also applies to AI suggestions, config imports, and sync merges.**
9. **Child mode cannot accidentally reach edit mode, AI, import, or sync settings.** But the gate must not be a puzzle that feels like a test.
10. **AI never changes boards by itself.** AI only makes a proposal. A parent sees a preview and taps Apply. The child never sees or uses AI features.
11. **Audio latency is a top priority.** Many GLP children vocally stim with their AAC (tapping the same tile again and again to hear the sound). Tap-to-sound must feel instant. The audio output stays open the whole time the app is in the foreground — never close and reopen it between taps (many AAC apps do this and add a delay or a click). See "Audio engine" below.

## Platforms and tech

- **One SwiftUI multiplatform target** (native macOS, not Catalyst) for iOS, iPadOS, macOS.
- Minimum OS: **iOS/iPadOS 17, macOS 14** (older family iPads matter). AI features use `#available` checks and need iOS/iPadOS/macOS 27 plus an Apple Intelligence device. On other devices, AI features are hidden and everything else works the same.
- Swift 6 language mode, strict concurrency, `@Observable` view models.
- Persistence: **SwiftData**. Design the model from M1 to be **CloudKit-compatible** (all attributes optional or with defaults, no `@Attribute(.unique)`, relationships optional, no deny delete rules). Store images and audio as `@Attribute(.externalStorage) Data` so they sync with iCloud. Explain in PLAN.md if you choose a different media strategy.
- Speech: **`AVSpeechSynthesizer`** (native TTS), played through a low-latency audio engine (see "Audio engine"). Audio session category `.playback` so speech plays even when the ringer switch is silent.
- Images: `PhotosPicker` (no Photos library permission needed), camera capture on iOS/iPadOS, drag-and-drop and file import on macOS. Downscale and store as HEIC/JPEG at a max of ~1024 px on the long edge.
- License: **Apache-2.0** for code (App Store compatible). Put the license header in every source file. Add `CONTRIBUTING.md` and `CODE_OF_CONDUCT.md`.
- CI: a GitHub Actions workflow that builds all three platforms and runs tests with `xcodebuild`, and validates every example config file against the JSON Schema.

## Audio engine (low latency — required from M1)

Goal: a tap makes sound in **under 30 ms** for a cached tile (measure it), and never more than 150 ms for an uncached tile.

- **Keep the output open.** Configure `AVAudioSession` once (`.playback`, mode `.default`, a small `setPreferredIOBufferDuration` such as 0.005 s) and activate it at launch. Do **not** call `setActive(false)` between utterances. Keep one `AVAudioEngine` running with an `AVAudioPlayerNode` (or a small pool of nodes) attached for the whole foreground session. Only stop it when the app goes to the background; restart it on return, and handle interruptions (phone call, Siri) and route changes (headphones, Bluetooth) by restarting it right away.
- **Pre-render speech.** For every tile on the current board, and the boards one link away, render the TTS to PCM buffers ahead of time with `AVSpeechSynthesizer.write(_:toBufferCallback:)`. Cache the buffers in memory (LRU, with a size cap) and on disk keyed by (spokenText, voice, rate, pitch). Re-render when the text or voice settings change. A tap then only schedules a buffer that is already in memory — no synthesis on the tap path.
- **Recorded audio** (M3) is decoded into PCM buffers when the board loads, the same way.
- **Retrigger behavior on fast taps.** Default: each tap stops the current sound and starts the new one from the start at once (like a musical instrument). Settings: "Restart on every tap" (default), "Let speech finish," and "Overlap" (several nodes play at the same time). No tap is ever dropped in "Restart" or "Overlap" mode.
- **No clicks.** Apply a very short fade (2–5 ms) when you cut a sound, so fast retriggers do not pop.
- **Fallback.** If a buffer is not ready yet, speak live with `AVSpeechSynthesizer` and render the cache in the background. Never block the main thread.
- **Haptics are off by default** (some children dislike them); optional light haptic per tap in settings, iPhone only.
- Add a hidden developer screen (edit mode only) that shows measured tap-to-sound latency, so we can test on real devices. Store nothing; this is not analytics.

## Core concepts and data model (starting point — refine in PLAN.md)

- **Board** — a grid of tiles. Fields: id (UUID), name, rows, columns, tiles (by grid position), isHome, createdAt, updatedAt.
- **Tile** — id (UUID), `label` (short text shown on the tile), `spokenText` (what is said; defaults to label but can be different, e.g. label "more" → spoken "let's do it again!"), image (optional), recorded audio (optional, see Milestone 3), background color (optional), `function` (optional tag: protest, request, connection, comment, regulation, other — used for color and AI grouping, never for gating), `linkedBoardID` (optional — tapping opens another board), `isHidden`, grid row/column.
- **Settings** — voice identifier, rate, pitch, volume, grid size, show labels on/off, label position, sentence strip on/off (default **off**), edit-gate type, appearance, iCloud sync on/off (default **off**), AI on/off and AI mode (default **off**).

Key GLP rule in the model: **one tile = one whole gestalt.** Never split a phrase into multiple tiles automatically. A tile with a long phrase is normal.

## Config format — designed for coding agents and humans

The whole setup (boards, tiles, settings, media) must be described by one open, documented, versioned file format, so a parent can use **any coding agent or text editor** (for example Claude Code on a Mac) to write or change boards outside the app, then import them.

- **`.hum` package** = a zip with:
  - `hum.json` — boards, tiles, and settings as JSON. Top-level `"formatVersion": 1`.
  - `media/` — images and audio, referenced from `hum.json` by relative path.
- A plain **`hum.json` alone** is also valid (tiles without media, or with media referenced by URL-free relative paths that are skipped if missing).
- **JSON Schema** at `schema/hum.schema.json` (draft 2020-12). Every field has a `description` written so a coding agent understands the GLP rules (for example, the `spokenText` description says "one whole gestalt; do not split into words").
- **`docs/CONFIG.md`** — a human- and agent-readable guide: the format, the GLP rules, and 3 complete examples in `examples/` (starter board, a food board using a "Let's have ___" style of whole phrases, a board with linked sub-boards).
- **`AGENTS.md`** at the repo root — short instructions for coding agents that want to generate Hum configs (read the schema, follow GLP rules, keep tile IDs and positions stable when you edit an existing file, never add reward phrases).
- A small, dependency-free **Swift package `HumConfig`** (shared by the app and a command-line tool `hum-config`) with commands: `validate <file>`, `pack <folder> <out.hum>`, `unpack <file.hum> <folder>`. Agents and CI use it.
- **Stable IDs.** Every board and tile has a UUID. Import matches by ID, so an edited file updates the existing tiles instead of making duplicates.
- **Forward and backward compatibility.** Unknown fields are kept, not dropped. Older `formatVersion` files are migrated. Newer ones show a clear "update Hum to open this" message.

## Import and export (moving setups between devices)

- **Export:** whole setup, or one board, to a `.hum` file. Use the system share sheet and `fileExporter`, so the parent can save to Files, **iCloud Drive**, AirDrop, Mail, or any cloud provider that has a Files app extension (Google Drive, Dropbox, etc.). The app talks to no cloud service directly except iCloud sync below.
- **Import:** from Files/`fileImporter`, AirDrop, drag-and-drop on Mac, or "Open in Hum" (register the `.hum` UTType and document type).
- **Import preview (required):** before anything changes, show a plain summary: "3 new tiles, 2 changed tiles, 0 removed. No tiles will move." Choices: **Merge** (default — add new, update matching IDs, never move or delete existing tiles) or **Replace everything** (asks to confirm, makes an automatic backup first).
- Validate against the schema on import. Show friendly errors ("Tile 'snack' has no words to say"), not stack traces. Never crash on a bad file.
- **Open Board Format** (`.obf` / `.obz`) import and export for interop with other AAC tools (CoughDrop, etc.). Map OBF `vocalization` → `spokenText`, `label` → `label`, `load_board` → `linkedBoardID`.
- **iCloud sync (optional, off by default):** SwiftData + CloudKit **private** database, so one family's iPad, iPhone, and Mac stay in sync. Parent turns it on in settings with a plain explanation ("Your boards are stored in your own iCloud. We never see them."). Sync must follow the motor-plan rule: a sync conflict never moves a tile; last edit wins per field, and position changes only come from an explicit parent move.

## AI helper for parents (optional, off by default)

Goal: help a busy parent set up and grow boards fast, in GLP-aware ways. AI lives **only in parent mode**.

- Use Apple's **Foundation Models** framework. Two modes, parent chooses:
  1. **On-device** (default when AI is on) — nothing leaves the device.
  2. **Private Cloud Compute** — Apple's larger model, for harder tasks. Show a one-line note: "This sends your text request to Apple's Private Cloud Compute. Apple does not store it."
- Never send photos or recorded audio to any model. Send only the parent's text request and the text of the current boards (labels, spoken text, function tags).
- Use **guided generation** (`@Generable` structs) so model output maps directly to the config types. Run the output through the same schema validation and the same **import preview** as a file import. The parent must tap Apply.
- Features (start with the first two; propose the rest in PLAN.md):
  1. **"Describe what you need"** — e.g. "My child loves trains and says 'all aboard!' when she wants to go." → proposed tiles/board.
  2. **Gestalt capture** — parent types or pastes phrases the child says (scripts, movie lines) and the context; AI proposes whole-gestalt tiles with a short label, the full `spokenText`, and a `function` tag. It never splits a gestalt into words.
  3. **Organize** — suggest grouping tiles into sub-boards by communicative function. Must keep protest/regulation tiles on Home and must not move tiles that already exist unless the parent picks that option.
  4. **Label helper** — suggest a short tile label for a long gestalt.
- Put the GLP rules in the model's instructions (system prompt), and also **enforce them in code** after generation: no reward/praise/compliance phrases, no splitting gestalts, protest tiles keep equal weight, no tile removals. Code checks win over model output.
- Show a clear message when the model is not available (device not eligible, Apple Intelligence off, model still downloading). The rest of the app works normally.
- Add **App Intents** (parent-facing Shortcuts / Siri AI actions): "Add a tile to Hum", "Import a Hum config", "Export Hum setup". These let other agents and automations on the device change boards, but they also go through the import preview the next time the parent opens the app (queue the change; do not apply silently while the child is using the app).

## Child mode (the default screen)

- Full-screen grid of large tiles. Photo on top, label below (label can be turned off).
- **Tap a tile → speak it immediately.** No message bar by default. The tile gives a short, calm visual press feedback (scale 0.96 and a soft highlight, about 150 ms). If "Reduce Motion" is on, use only the highlight.
- A tile with a linked board shows a small folder corner mark. Tap → speaks its phrase (if it has one) and opens the linked board. A large, fixed **Home** button is always in the same corner.
- If a tile is tapped while speech is playing: stop the current sound and play the new tap at once (default). Same tile tapped again → restart it at once. See "Audio engine" for the other modes.
- Visual press feedback must never delay the sound, and must keep up with fast repeated taps.
- No scrolling in child mode. If the board has more tiles than fit, the parent must choose a bigger grid or split into sub-boards (warn the parent in edit mode, not the child).
- Calm visuals: no animation loops, no sounds except speech, muted default palette, full Dark Mode support, honor Increase Contrast and Reduce Motion.
- Minimum tile hit target: 88 × 88 pt on iPhone; larger on iPad. Support grids from 1×2 up to 6×8.
- A sync or import must never change the screen while the child is tapping. Apply incoming changes only when the child is not in the middle of a tap, and never reorder tiles.
- Optional **sentence strip** (off by default; for children later in NLA Stage 3+): tapped tiles collect in a bar; tap the bar to speak all; a clear button. Even with the strip on, each tile still speaks on tap.

## Parent (edit) mode

**Entry gate** (choose one in settings; default first):
1. Press and hold a small lock icon in a corner for 3 seconds (a ring fills while holding).
2. Two-finger triple-tap.
Show a one-time tip that explains Apple **Guided Access** for full lock-down. Never use a math question or a "test."

**Edit mode must feel very easy:**
- Tap an empty slot → "Add tile" sheet. Tap an existing tile → edit sheet. Drag to move tiles (only in edit mode).
- Add-tile sheet fields, in this order: **Photo** (Take photo / Choose photo / No photo) → **What it says** (spokenText, with a ▶ play preview button) → **Label** (prefilled from spokenText, editable) → **Color** (optional) → **Opens a board** (optional).
- Plain, warm language in all parent UI. Examples: "What does this tile say?", "Add a photo of the real thing — real photos often work better than drawings."
- Undo for the last change (including an applied import or AI proposal). Delete asks to confirm.
- Board manager: create, rename, duplicate, delete boards; set Home board.
- **Setup & sharing** screen: Export, Import, iCloud sync toggle, "Help me set up" (AI, if available), and a link to `docs/CONFIG.md` for people who use coding agents.
- Voice settings: list installed system voices for the device language, with preview. Show a tip on how to download better (Enhanced/Premium) voices in Settings → Accessibility → Spoken Content. Support **Personal Voice** with `requestPersonalVoiceAuthorization` so a parent can use their own voice.

## First-run setup (must take under 2 minutes)

1. Welcome screen (one sentence, one button).
2. Pick a voice (3–4 suggested voices with play buttons; "Skip" uses system default).
3. Pick grid size with visual previews (2×2, 3×3, 3×4, 4×5). Default 3×3 on iPhone, 4×5 on iPad/Mac.
4. Start with the **starter board**, an **empty board**, or **Import a setup** (a `.hum` or `.obz` file from another device or made by a coding agent).

**Starter board** (whole-gestalt, function-grouped; placeholder images are system emoji, with a clear "replace with a real photo" prompt in edit mode). Ship it as `examples/starter.hum.json` loaded through the normal import path:
- Protest / regulation: "No thank you", "Stop!", "All done", "I need a break", "Too loud", "Help me"
- Requests: "Let's go!", "I want more", "Let's have a snack", "Let's play", "Up!", "I want to go outside"
- Connection / commenting: "Uh oh!", "Look at that!", "Hi!", "Bye-bye!", "That's funny!", "Let's do it again!"
Protest tiles must not be on a hidden sub-board; they are on Home.

## Milestones

**M1 — Skeleton + config core:** project, CI, license, privacy manifest, CloudKit-compatible SwiftData model, `HumConfig` package with JSON Schema, Codable types, `validate` CLI, `AGENTS.md`, `docs/CONFIG.md` draft, starter board loaded from JSON, child-mode grid, **low-latency audio engine with pre-rendered TTS cache** and the latency screen.
**M2 — Parent mode:** edit gate, add/edit/move/hide/delete tiles with photos, boards and links, settings, first-run setup.
**M3 — Import/export + GLP depth:** `.hum` export/import with preview, merge rules, and undo; `.hum` UTType; optional **recorded audio per tile** (parent records the phrase with the real intonation — intonation carries meaning for gestalts; on-device only; mic permission asked only when the parent taps Record). Tile plays recording if present, else TTS. Optional sentence strip.
**M4 — Sync + interop:** optional iCloud sync (private database) with motor-plan-safe conflict handling; Open Board Format (`.obf`/`.obz`) import/export; App Intents.
**M5 — AI helper:** Foundation Models on-device and Private Cloud Compute modes, "Describe what you need" and "Gestalt capture," code-level GLP rule checks, availability handling.
**M6 — Polish and release:** full accessibility pass (VoiceOver labels on every tile = spokenText, Switch Control, Dynamic Type in parent UI), localization-ready strings (String Catalog), App Store screenshots, `README.md` with GLP background, privacy statement, and a "Make boards with a coding agent" section.

## Quality bar

- Unit tests for the model, grid placement (motor-plan stability rules), config validation, schema migration, import merge rules (IDs matched, nothing moved, nothing deleted on Merge), `.hum` and `.obz` round-trips, and the AI output rule checks (feed it bad outputs: split gestalts, praise phrases, removals — all must be rejected or fixed).
- Audio tests: cache hit/miss, re-render on voice change, engine restart after interruption and route change, and a stress test of 20 taps per second for 30 seconds with no dropped taps, no crash, and no audio pops.
- Golden-file tests: every file in `examples/` imports and exports back to equal JSON.
- UI tests for: first-run setup, add a tile with a photo, tap tile speaks, edit gate, import preview, undo of an import.
- Test on iPhone SE size, iPad 10th gen size, iPad Pro 13", and a Mac window resized small and large.
- No crashes when images are missing, a linked board was deleted, a config file is broken, or the AI model is unavailable.
- Cold launch to usable grid in under 1 second on a 5-year-old iPad.

## Working rules for you (the agent)

- Write `docs/PLAN.md` first and wait for approval. In the plan, list the exact Foundation Models and CloudKit APIs you will use and confirm they exist in the current SDK — if an API in this prompt is wrong or changed, say so.
- Work one milestone at a time. At the end of each milestone: build passes on all 3 platforms, tests pass, and you write a short summary in `docs/CHANGELOG.md`.
- If a requirement here conflicts with Apple guidelines or is not technically possible, stop and tell me — do not quietly change the product rules.
- Do not add any dependency, network call, analytics, third-party AI provider, or reward mechanic. If you think one is needed, ask first.
- Keep code simple and well commented; this project will take outside contributors.
