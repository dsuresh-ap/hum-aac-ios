# Cloud agent tasks

Self-contained tasks for cloud coding agents (Linux, no Xcode). Each one only touches
`Packages/HumConfig` (pure Swift, no dependencies) plus docs/examples, so they can run in parallel with
app work without merge conflicts. Each must end with `swift test --package-path Packages/HumConfig`
passing and a PR against `main`.

Common preamble for every task (paste it first):

> You are working in https://github.com/dsuresh-ap/hum-aac-ios, a free, open-source AAC app for
> Gestalt Language Processors. Read `Hum-agent-prompt.md` (product spec), `AGENTS.md`, `docs/PLAN.md`
> and `docs/CONFIG.md` first. Hard rules: no dependencies (Foundation only), the package must build
> and test on Linux (`swift test --package-path Packages/HumConfig`), every new source file starts
> with `// Copyright 2026 The Hum Authors` / `// SPDX-License-Identifier: Apache-2.0`, plain comments
> for first-time contributors, Swift 6 language mode, Swift Testing (`import Testing`). Never move
> existing tiles (motor-plan stability), never split a gestalt, never add praise/reward phrases.
> Work on a new branch and open a PR to `main` with a short summary. Do not modify files under
> `hum-aac-ios/` (the app); only `Packages/HumConfig`, `schema/`, `examples/`, `docs/`.

---

## Task A: Open Board Format (.obf / .obz) import and export

> Add Open Board Format support to HumConfig in new files under
> `Packages/HumConfig/Sources/HumConfig/OBF/`.
>
> Spec: https://www.openboardformat.org/docs (OBF is JSON; OBZ is a zip with `manifest.json`,
> boards and images). Implement:
> 1. `OBFImporter.document(fromOBF data: Data) throws -> LoadedConfig` and
>    `OBFImporter.document(fromOBZ data: Data) throws -> LoadedConfig` (use the existing
>    `ZipArchive.read`). Mapping: `vocalization` → `spokenText` (fall back to `label`), `label` →
>    `label`, `load_board` → `linkedBoardID`, `grid.order` → row/column (null = empty slot),
>    `background_color` → `color` (convert rgb()/rgba() to #RRGGBB), images from the zip →
>    `media/<name>` (data: URIs too; skip remote URLs, never fetch the network). OBF string IDs must map
>    to **stable** UUIDs (UUIDv5 over `"obf:" + board id` / `"obf:" + board id + "/" + button id`,
>    implemented with Foundation only: SHA-1 is not in Foundation on Linux, so add a small
>    dependency-free SHA-1), so re-importing the same file updates instead of duplicating.
>    The manifest's `root` board becomes `isHome`. Buttons with `hidden: true` → `hidden`.
>    Unsupported features (sounds by URL, actions like `:clear`) are skipped with a friendly warning.
> 2. `OBFExporter.obz(from document: HumDocument, media: [String: Data]) throws -> Data` producing a
>    valid OBZ (manifest + one board file per board + images), with `ext_hum_*` extension fields so a
>    Hum→OBZ→Hum round-trip keeps `function`, `symbol` and the original UUIDs.
> 3. CLI: add `hum-config obz-to-hum <in.obz> <out.hum>` and `hum-config hum-to-obz <in.hum> <out.obz>`
>    in `Sources/hum-config/main.swift`.
> 4. Tests: hand-written OBF fixtures (in the test file or `Tests/HumConfigTests/Fixtures/`) covering
>    grid mapping, empty slots, links, colors, hidden buttons, stable IDs on re-import, and
>    Hum→OBZ→Hum round-trip equality of boards/tiles. Run all tests.
> 5. Document the mapping in a new section of `docs/CONFIG.md`.

## Task B: AI-proposal rule checks: done locally

Implemented in `Packages/HumConfig/Sources/HumConfig/ProposalChecker.swift` (with tests). Extra adversarial
test cases are welcome as part of Task C.

## Task C: Hardening and fuzz tests for the config core

> Strengthen `Packages/HumConfig` without changing public APIs:
> - Property/fuzz-style tests (deterministic seeded generator, no dependencies) for `Inflate` and
>   `ZipArchive`: random byte mutations of valid archives must never crash or hang (bounded time).
>   Add a check in `Inflate` that output can't exceed a sane limit (e.g. 200 MB) to prevent zip bombs,
>   and in `ZipArchive.read` a limit on entry count (e.g. 10,000).
> - `SchemaValidator`: tests for every friendly-message branch.
> - `HumConfigLoader`: tests for files with BOM, trailing commas (should fail with a friendly error),
>   huge numbers, deeply nested unknown fields (preserved), non-UTF-8 input.
> - Run the examples through `hum-config validate` in a test.
> Keep all existing tests passing.
