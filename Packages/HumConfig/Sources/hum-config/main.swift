// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

// `hum-config`: a small CLI for people and coding agents who write Hum setups by hand.
//
//   hum-config validate <file.hum | hum.json>...
//   hum-config pack <folder> <out.hum>       (folder holds hum.json and media/)
//   hum-config unpack <file.hum> <folder>
//
// Exit codes: 0 = OK (warnings allowed), 1 = the file has errors, 2 = usage or I/O problem.

import Foundation
import HumConfig

let usage = """
    Usage:
      hum-config validate <file>...        Check .hum or hum.json files against the Hum format and GLP rules
      hum-config pack <folder> <out.hum>   Zip a folder (hum.json + media/) into a .hum package
      hum-config unpack <file.hum> <folder> Extract a .hum package into a folder
    """

func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func readFile(_ path: String) -> Data {
    guard let data = FileManager.default.contents(atPath: path) else { fail("Can't read \(path)") }
    return data
}

/// Prints issues and returns true if there were no errors.
func report(_ path: String, _ issues: [ValidationIssue]) -> Bool {
    let errors = issues.filter { $0.severity == .error }
    if issues.isEmpty {
        print("✓ \(path)")
    } else {
        print(errors.isEmpty ? "✓ \(path) (with warnings)" : "✗ \(path)")
        for issue in issues { print("  \(issue)") }
    }
    return errors.isEmpty
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { fail(usage) }

switch command {
case "validate":
    let files = Array(args.dropFirst())
    guard !files.isEmpty else { fail(usage) }
    var ok = true
    for file in files {
        ok = report(file, HumConfigLoader.validate(readFile(file))) && ok
    }
    exit(ok ? 0 : 1)

case "pack":
    guard args.count == 3 else { fail(usage) }
    let folder = URL(fileURLWithPath: args[1], isDirectory: true)
    let json = readFile(folder.appendingPathComponent(HumPackage.jsonName).path)
    let loaded: LoadedConfig
    do { loaded = try HumConfigLoader.loadJSON(json) } catch {
        _ = report(args[1], HumConfigLoader.validate(json))
        fail("Not packed: fix the errors above first.", code: 1)
    }
    var media: [String: Data] = [:]
    for board in loaded.document.boards {
        for tile in board.tiles {
            for path in [tile.image, tile.audio].compactMap({ $0 }) where HumPackage.isSafe(path) {
                if let data = FileManager.default.contents(atPath: folder.appendingPathComponent(path).path) {
                    media[path] = data
                } else {
                    print("  warning: \(path) not found; tile '\(tile.label)' will have no media")
                }
            }
        }
    }
    do {
        // Re-encode from the parsed document so the packed JSON is normalized but keeps unknown fields.
        let out = try HumPackage.write(loaded.document, media: media)
        try out.write(to: URL(fileURLWithPath: args[2]))
        print("✓ Packed \(loaded.document.boards.count) board(s), \(media.count) media file(s) → \(args[2])")
    } catch {
        fail("Couldn't write \(args[2]): \(error.localizedDescription)")
    }

case "unpack":
    guard args.count == 3 else { fail(usage) }
    let contents: HumPackage.Contents
    do { contents = try HumPackage.read(readFile(args[1])) } catch {
        fail((error as? LocalizedError)?.errorDescription ?? "\(error)", code: 1)
    }
    let folder = URL(fileURLWithPath: args[2], isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try contents.json.write(to: folder.appendingPathComponent(HumPackage.jsonName))
        for (path, data) in contents.media where HumPackage.isSafe(path) {
            let url = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        if let credits = contents.credits {
            try credits.write(to: folder.appendingPathComponent(HumPackage.creditsName))
        }
        print("✓ Unpacked hum.json and \(contents.media.count) media file(s) → \(args[2])")
    } catch {
        fail("Couldn't write to \(args[2]): \(error.localizedDescription)")
    }

case "-h", "--help", "help":
    print(usage)

default:
    fail(usage)
}
