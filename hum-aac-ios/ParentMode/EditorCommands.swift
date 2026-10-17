// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Keyboard shortcuts for the parent editor (Mac menu bar, and iPad with a keyboard: hold ⌘ to see them).
///
/// They only exist while the editor is on screen with no sheet open. There is deliberately no shortcut
/// *into* the editor: the grown-up lock stays the only way in.
struct EditorCommands {
    var newTile: () -> Void
    var newFolder: () -> Void
    var pastePhrases: () -> Void
    var aiHelper: (() -> Void)?
    var gridSize: () -> Void
    var foldersList: () -> Void
    var find: () -> Void
    var back: (() -> Void)?
    var home: () -> Void
    var history: () -> Void
    var sharing: () -> Void
    var settings: () -> Void
    var done: () -> Void
}

extension FocusedValues {
    @Entry var editorCommands: EditorCommands?
}

struct EditorMenuCommands: Commands {
    @FocusedValue(\.editorCommands) private var editor

    var body: some Commands {
        // File menu: replaces "New Window" (one window only; a second copy of the board would confuse).
        CommandGroup(replacing: .newItem) {
            Button("New Tile") { editor?.newTile() }
                .keyboardShortcut("n")
                .disabled(editor == nil)
            Button("New Folder") { editor?.newFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(editor == nil)
            Button("Paste Phrases…") { editor?.pastePhrases() }
                .keyboardShortcut("v", modifiers: [.command, .option])
                .disabled(editor == nil)
        }
        CommandMenu("Board") {
            Button("Back to Previous Board") { editor?.back?() }
                .keyboardShortcut("[")
                .disabled(editor?.back == nil)
            Button("Go to Home") { editor?.home() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(editor == nil)
            Button("Find…") { editor?.find() }
                .keyboardShortcut("f")
                .disabled(editor == nil)
            Button("Home & Folders…") { editor?.foldersList() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(editor == nil)
            Button("Tile Size…") { editor?.gridSize() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(editor == nil)
            Divider()
            Button("Help Me Set Up…") { editor?.aiHelper?() }
                .keyboardShortcut("k")
                .disabled(editor?.aiHelper == nil)
            Button("History") { editor?.history() }
                .keyboardShortcut("y")
                .disabled(editor == nil)
            Button("Share & Sync…") { editor?.sharing() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(editor == nil)
            Divider()
            Button("Done Editing") { editor?.done() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(editor == nil)
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { editor?.settings() }
                .keyboardShortcut(",")
                .disabled(editor == nil)
        }
    }
}
