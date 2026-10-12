# Testing Hum

- [BUGS.md](BUGS.md): bugs found in the end-to-end pass, with steps and severity.
- [HUMAN-TEST-PLAN.md](HUMAN-TEST-PLAN.md): what a person checks on real devices before a release.
- `HumUITests/`: the automated end-to-end tests (below).
- `HumTests/` and `Packages/HumConfig/Tests/`: unit tests.

## Running the UI tests

Use an **iOS 27 simulator** (see `CLAUDE.md`): e.g. “iPhone 18 Pro Max” and “iPad Pro 13-inch (M5)”.
Run one suite at a time; each test relaunches Hum, so a suite takes 2–10 minutes. The scheme stops any
single test after 5 minutes.

The big-import tests need a real family setup that is **not in git**: put a `.hum` file at
`TestFixtures/Local/Express2-v2.hum` (see `TestFixtures/README.md`). Without it those tests are skipped.

Every launch uses `-uiTesting` (in-memory store, fresh settings). Extra launch arguments, all test-only:
`-skipFirstRun`, `-startInParent`, `-demoFolder`, `-demoHistory`, `-demoPendingImport`, `-wideHome`,
`-darkMode`, `-phoneLayout` (UI-test launches use the iPhone page layout only with this),
`-importFile <path>` (as if the file arrived through “Open in Hum”).

### Known bugs inside tests

A check that reproduces a logged bug is wrapped in `XCTExpectFailure("HUM-0xx …")`, so the suite stays green
while the bug is open. When a fix lands, that test fails with “expected failure but none recorded”: remove
the wrapper. Checks that only fail on some screen sizes use `options: .nonStrict()`. As of 2026-10-12 every
logged bug is fixed, so no wrappers are left; the checks name the bug they guard (e.g. “(HUM-002)”).

Store-level fixes are in `HumTests/BugFixTests.swift`. Unit tests that undo more than one step call
`model.endEvent()` between steps: tests don't turn the run loop, so otherwise the undo manager would group
every change in the test into one step.

## What the suites cover

| Suite | Scenarios |
|-------|-----------|
| `FirstRunUITests` | Empty board gets the chosen size; Back keeps choices; Skip voice; starter card says it's 5 × 4 (HUM-003); cancelling “Import a setup” keeps setup open (HUM-004); starter grows to a big grid and keeps protest tiles on Home; choosing a voice. |
| `ChildModeUITests` | Protest tiles as big as request tiles; 88 pt minimum; 10 fast taps all counted, no warning; folder speaks + opens, Home returns; Home and lock never move; return-Home setting; hidden tile leaves a hole and nothing moves; sentence strip; labels off; VoiceOver labels; two-finger gate hides the lock; a 3.5 s hold opens grown-up mode on iPad too (HUM-044); history box (HUM-021). |
| `EditorUITests` | Label follows phrase, Save needs words (HUM-018); new tile reaches the child; editing keeps the spot; praise warning; Cancel asks; delete confirms + Undo (HUM-002); menu delete confirms (HUM-008); duplicate; move to folder; folder tile tap edits (HUM-006); Back from a folder; grow grid; shrink asks and uses the tray (HUM-024); no jargon warning (HUM-005). |
| `BoardsUITests` | Make a folder; rename folder renames its tile (HUM-039); duplicate flagged unreachable; delete folder keeps its tile; make a folder Home warns (HUM-040). |
| `ParentToolsUITests` | Paste phrases (praise and duplicates left out, one undo step); AI helper starts off; Guided Access tip once (HUM-041); export opens the save sheet; no developer section (HUM-022); Dark appearance. |
| `ImportUITests` | Big-file preview and Cancel (HUM-011); merged setup reachable through a folder tile, with a banner (HUM-001, HUM-027); Replace everything asks, child sees the file's Home in pages, folders open, Undo (HUM-038); broken file; newer format; tile with no words named; import waits for grown-up mode. |
| `LandscapeUITests` | iPhone sideways: the editor scrolls and tiles never overlap (HUM-051); the child's tiles keep their spots and the history box steps aside (HUM-050). |
| `ScreenTourTests` | Walks every screen and attaches screenshots for review by eye. |
| `HumUITests` | The original smoke tests (first run, speak into history, gate, add + undo, phone layout, new folder, folder back, import preview + undo). |
