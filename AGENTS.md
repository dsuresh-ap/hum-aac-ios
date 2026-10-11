# AGENTS.md — instructions for coding agents

This file is for AI coding agents (Claude Code, Codex, Cursor, etc.) working in this repo, especially
agents asked by a parent to **write or edit a Hum setup** (`hum.json` / `.hum`).

## If you are generating or editing a Hum config

1. **Read the schema first:** [`schema/hum.schema.json`](schema/hum.schema.json). Every field's
   `description` explains the rules. The human guide is [`docs/CONFIG.md`](docs/CONFIG.md).
2. **One tile = one whole gestalt.** Put the child's full phrase in `spokenText`
   (e.g. `"to infinity and beyond!"`). Never split a phrase into several tiles. Long phrases are normal.
   `label` is a short version shown on the tile.
3. **Keep IDs and positions stable.** When you edit an existing file, never change an existing tile's
   `id`, `row` or `column` unless the parent explicitly asked to move it. The child has learned where
   every tile is (motor planning). New tiles get a fresh random UUID and an **empty** spot.
4. **Never add praise, reward or compliance phrases**: no "good job", "well done", "quiet hands",
   "look at me", "first work then…", stickers, tokens or stars. Tiles are the child's voice.
5. **Protest and regulation tiles are first-class.** "No thank you", "Stop!", "All done",
   "I need a break", "Too loud" and "Help me" stay on the Home board, with the same size as every
   other tile. Never remove or hide them.
6. **Never remove tiles** unless the parent asked. Prefer `"hidden": true`, which keeps the slot.
7. **Validate before handing the file back:**
   ```bash
   swift run --package-path Packages/HumConfig hum-config validate path/to/hum.json
   ```
   Fix every `error`. Read every `warning` and fix it unless the parent wants it.
8. To bundle photos: put `hum.json` and a `media/` folder in one folder, then
   `hum-config pack <folder> <out.hum>`. Reference images as `"image": "media/apple.jpg"`.
9. Do not add `iCloud` or AI settings to config files. Only a parent can turn those on, inside the app.

## If you are changing the app's code

- Read [`docs/PLAN.md`](docs/PLAN.md) and the hard product rules in it (free forever, no tracking, no
  network except opt-in Apple iCloud/PCC and the parent-started ARASAAC symbol search, no dependencies, no reward mechanics, never gate
  communication, motor-plan stability, audio latency first).
- `Packages/HumConfig` must stay dependency-free and build on Linux (`swift test` there).
- Run `swift test --package-path Packages/HumConfig` and build the `Hum` scheme for macOS and iOS.
- Every source file starts with the Apache-2.0 SPDX header.
- Keep comments plain and short; this project welcomes first-time contributors.
