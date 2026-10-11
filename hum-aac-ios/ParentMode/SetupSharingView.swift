// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import UniformTypeIdentifiers
import HumConfig

/// Export, import, and (later) iCloud sync and the AI helper.
struct SetupSharingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var exportDocument: HumFileDocument?
    @State private var exportName = ""
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var errorMessage: String?
    @State private var showAI = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Export all boards…", systemImage: "square.and.arrow.up") { export(boardID: nil) }
                        .accessibilityIdentifier("exportAll")
                    if let id = model.editingBoardID, let board = model.fetchBoard(id) {
                        Button("Export “\(board.name)” only…", systemImage: "square.and.arrow.up.on.square") { export(boardID: id, name: board.name) }
                    }
                } header: {
                    Text("Move boards to another device")
                } footer: {
                    Text("Saves a .hum file with your boards and photos. Put it in Files, iCloud Drive, Google Drive or Dropbox, or AirDrop it, then open it in Hum on the other device.")
                }

                Section {
                    Button("Import a setup…", systemImage: "square.and.arrow.down") { showImporter = true }
                        .accessibilityIdentifier("importSetup")
                    #if os(macOS)
                    Text("You can also drag a .hum file onto this window.")
                        .font(.footnote).foregroundStyle(.secondary)
                    #endif
                } footer: {
                    Text("You'll see what changes before anything happens. Tiles already on your boards never move.")
                }

                // Hidden entirely on devices without Apple Intelligence.
                if AIHelper.isSupportedOnThisDevice {
                    Section {
                        Button("Help me set up", systemImage: "sparkles") { showAI = true }
                    } footer: {
                        Text("Describe what your child needs, or paste phrases they say, and get suggested tiles to preview. Off until you turn it on.")
                    }
                }

                Section {
                    Button("How to make boards with a coding agent", systemImage: "doc.text") {
                        if let url = URL(string: "https://github.com/dsuresh-ap/hum-aac-ios/blob/main/docs/CONFIG.md") { openURL(url) }
                    }
                } footer: {
                    Text("Hum's setup file is an open format. You can write or edit boards in any text editor or with an AI coding agent, then import them here.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Setup & sharing")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showAI) { AIHelperView() }
            .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .humPackage, defaultFilename: exportName) { result in
                if case .failure(let error) = result { errorMessage = error.localizedDescription }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.humPackage, .json, .zip]) { result in
                switch result {
                case .success(let url): model.requestImport(url: url)
                case .failure(let error): errorMessage = error.localizedDescription
                }
            }
            .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 440)
        #endif
    }

    private func export(boardID: UUID?, name: String? = nil) {
        do {
            exportDocument = HumFileDocument(data: try ImportService(model: model).exportData(boardID: boardID))
            exportName = ImportService.exportFileName(boardName: name)
            showExporter = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Wraps `.hum` bytes for `fileExporter`.
nonisolated struct HumFileDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.humPackage]
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
