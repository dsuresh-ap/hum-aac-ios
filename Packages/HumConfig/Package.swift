// swift-tools-version: 6.0
// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

// HumConfig: the open Hum config format (`hum.json` / `.hum`), with no dependencies.
// It is shared by the Hum app and the `hum-config` command-line tool. It uses only
// Foundation, so it also builds on Linux (CI and cloud agents).

import PackageDescription

let package = Package(
    name: "HumConfig",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "HumConfig", targets: ["HumConfig"]),
        .executable(name: "hum-config", targets: ["hum-config"]),
    ],
    targets: [
        .target(
            name: "HumConfig",
            resources: [.copy("Resources/hum.schema.json")]
        ),
        .executableTarget(name: "hum-config", dependencies: ["HumConfig"]),
        .testTarget(name: "HumConfigTests", dependencies: ["HumConfig"]),
    ],
    swiftLanguageModes: [.v6]
)
