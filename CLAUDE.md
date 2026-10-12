# CLAUDE.md

Read [`AGENTS.md`](AGENTS.md) first: the product rules and config-editing rules there apply to Claude too.

## Build and test with the Xcode MCP

Use the Xcode MCP tools (`mcp__xcode__*`) for the app, not raw `xcodebuild`:

- `XcodeListWorkspaces` → pass the `workspaceIdentifier` to every other call.
- Build: `BuildProject` (add `buildForTesting: true` before tests). Read errors with `GetBuildLog`,
  or `XcodeRefreshCodeIssuesInFile` for one file.
- Tests: `XcodeSwitchRunDestination` to an **iOS 27 simulator** (e.g. "iPhone 18 Pro" or
  "iPad Pro 13-inch (M5) (27.0)"), then `RunAllTests` / `RunSomeTests` (find IDs with `GetTestList`).
  Don't run app tests on "My Mac": a crashing macOS test host pops crash dialogs on the owner's Mac.
  Switch the destination back to "My Mac" afterwards (the owner develops on macOS first).
- The `HumConfig` package is plain SwiftPM: `swift test --package-path Packages/HumConfig`.

## Notes

- The app targets iOS 18 / macOS 14 (the project-level 27 is overridden by every target). iOS 18 is the
  minimum on purpose: older iPads stay supported (7th-gen iPad and later). Unit tests pass on iOS 18.5,
  26.5 and 27 simulators; test on iOS 18 before relying on a newer API. Before iOS 27, SwiftData's own undo loses a tile's board, so any
  change to a tile's board needs its own undo (BUGS.md, HUM-052).
- AI tests use a fake model. The real on-device model test only runs with `HUM_LIVE_AI=1`
  (`TEST_RUNNER_HUM_LIVE_AI=1` through xcodebuild).
- Network: only parent-started iCloud sync, Private Cloud Compute and the symbol search (ARASAAC,
  Mulberry via Global Symbols; see `docs/PLAN.md` §8b). Ask before adding any other network use.
