# Contributing to Hum

Thank you for helping! Hum is used by young children to communicate, so a few rules come before
everything else. Please read them before opening a pull request.

## Product rules (non-negotiable)

1. Free forever: no purchases, ads, subscriptions or tip jars.
2. No analytics, tracking, accounts, third-party SDKs or developer servers. The only network use is
   opt-in, parent-started Apple iCloud (private database), Apple Private Cloud Compute, and the symbol
   search (ARASAAC, Mulberry via Global Symbols; see `docs/PLAN.md` §8b), and parent-started local
   device-to-device transfer (§8c: local network only, never the internet). Update
   [`docs/privacy.md`](docs/privacy.md) if you change what leaves the device.
3. No new dependencies without a maintainer's approval (Apple frameworks only).
4. Never gate communication; protest tiles have the same size and weight as requests.
5. No reward or compliance mechanics (stars, tokens, praise sounds, confetti…).
6. Repeated tapping is valid: no debounce, no rate limit, no warnings.
7. Motor-plan stability: tiles never move unless a parent moves them, including after imports, sync and AI.
8. Audio latency is a top priority. Don't add work to the tap path.

## How to contribute

- **Bugs and ideas:** open an issue. For anything about the child-facing experience, describe how it
  affects a child who is a Gestalt Language Processor.
- **Code:** fork, branch, and open a PR. Keep PRs small and focused.
  - Every source file starts with:
    ```swift
    // Copyright 2026 The Hum Authors
    // SPDX-License-Identifier: Apache-2.0
    ```
  - Run `swift test --package-path Packages/HumConfig` and build the `Hum` scheme for macOS and iOS.
  - `Packages/HumConfig` must stay dependency-free and Linux-compatible.
  - Plain, warm language in all parent-facing text; no jargon.
- **Boards and examples:** new example configs in `examples/` must pass `hum-config validate` and follow
  the GLP rules in [`docs/CONFIG.md`](docs/CONFIG.md).

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). Be kind. Many contributors are
parents, therapists and autistic people themselves.
