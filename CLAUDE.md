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

- The project sets iOS/macOS 27 at the project level, so simulators older than iOS 27 can't run it.
- AI tests use a fake model. The real on-device model test only runs with `HUM_LIVE_AI=1`
  (`TEST_RUNNER_HUM_LIVE_AI=1` through xcodebuild).
- Network: only parent-started iCloud sync, Private Cloud Compute and the symbol search (ARASAAC,
  Mulberry via Global Symbols; see `docs/PLAN.md` §8b). Ask before adding any other network use.
