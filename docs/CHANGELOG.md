# Changelog

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
