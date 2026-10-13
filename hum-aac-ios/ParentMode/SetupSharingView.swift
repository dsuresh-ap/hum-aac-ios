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
    #if os(iOS)
    /// The exported file, shown in the share sheet (AirDrop, Messages, Mail, Save to Files…).
    @State private var shareFile: SharedFile?
    /// The same file, kept until the sheet has closed so its temporary copy can be deleted.
    @State private var sharedCopy: SharedFile?
    #endif
    @State private var showImporter = false
    @State private var errorMessage: String?
    @State private var showAI = false
    /// True while the export file is being made (a big setup takes a few seconds).
    @State private var preparingExport = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Export all boards…", systemImage: "square.and.arrow.up") { export(boardID: nil) }
                        .accessibilityIdentifier("exportAll")
                        .disabled(preparingExport)
                    if let id = model.editingBoardID, let board = model.fetchBoard(id) {
                        // Not "square.and.arrow.up.on.square": on macOS 27 that symbol sits low and cuts off
                        // the bottom of the button.
                        Button("Export “\(board.name)” only…", systemImage: "square.and.arrow.up") { export(boardID: id, name: board.name) }
                            .disabled(preparingExport)
                    }
                    if preparingExport {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Preparing your boards…").foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Move boards to another device")
                } footer: {
                    #if os(iOS)
                    Text("Makes a Hum file with your boards and photos. AirDrop it, send it, or save it to Files, iCloud Drive, Google Drive or Dropbox, then open it in Hum on the other device.")
                    #else
                    Text("Saves a Hum file with your boards and photos. Put it in iCloud Drive, Google Drive or Dropbox, or AirDrop it, then open it in Hum on the other device.")
                    #endif
                }

                Section {
                    Toggle("Sync with iCloud", isOn: Binding(
                        get: { model.settings.iCloudSyncEnabled },
                        set: { model.setICloudSync($0) }))
                    if model.settings.iCloudSyncEnabled {
                        SyncStatusRows()
                    }
                } header: {
                    Text("Keep devices in sync")
                } footer: {
                    Text("Your boards are stored in your own iCloud. We never see them. Turn this on for each iPad, iPhone or Mac that should share boards. Tiles never move on their own when changes arrive from another device.")
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
                        openURL(HumLinks.configGuide)
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
            .task(id: model.iCloudActive) { if model.iCloudActive { await model.sync.refreshAccount() } }
            #if os(iOS)
            .sheet(item: $shareFile, onDismiss: { sharedCopy?.remove(); sharedCopy = nil }) { file in
                ShareSheet(url: file.url).ignoresSafeArea()
            }
            #endif
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
        .modifier(HumFileDrop())
        #endif
        // The preview opens right here, over this sheet, instead of waiting for it to close.
        .modifier(ImportPreviewHost(isActive: true))
        .onAppear { model.importHostedBySheet = true }
        .onDisappear { model.importHostedBySheet = false }
    }

    /// Reads the boards here, then zips them in the background with "Preparing your boards…" showing.
    private func export(boardID: UUID?, name: String? = nil) {
        guard !preparingExport else { return }
        preparingExport = true
        let (document, media) = ImportService(model: model).exportContents(boardID: boardID)
        Task {
            defer { preparingExport = false }
            do {
                let data = try await Task.detached(priority: .userInitiated) { try HumPackage.write(document, media: media) }.value
                let fileName = ImportService.exportFileName(boardName: name)
                #if os(iOS)
                let file = try SharedFile(data: data, name: fileName)
                sharedCopy = file
                shareFile = file
                #else
                exportDocument = HumFileDocument(data: data)
                exportName = fileName
                showExporter = true
                #endif
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#if os(iOS)
/// An export written to a temporary folder for the share sheet, under its real name
/// ("Hum setup 2026-10-12.hum"), so AirDrop and Messages show that name and Hum opens it on arrival.
struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }

    init(data: Data, name: String) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
    }

    /// Deletes the temporary copy once the share sheet has closed.
    func remove() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

/// The system share sheet for one file.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif

/// Wraps `.hum` bytes for `fileExporter` (Mac).
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

/// What iCloud sync is doing on this device, in plain words. (How a developer checks the records is in
/// docs/testing/ICLOUD.md, not in the app.)
private struct SyncStatusRows: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let sync = model.sync
        if !model.iCloudActive {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sync is on, but iCloud isn't available, so boards are only on this device for now.")
                    Text(FileManager.default.ubiquityIdentityToken == nil
                         ? "This device isn't signed in to iCloud (or iCloud Drive is off)."
                         : "Try turning sync off and on again.")
                        .foregroundStyle(.secondary)
                }
            } icon: { Image(systemName: "exclamationmark.icloud") }
            .font(.footnote)
        } else {
            LabeledContent("iCloud account", value: sync.account.description)
            LabeledContent("Sent to iCloud", value: describe(sync.lastExport, busy: sync.busy))
            LabeledContent("Received from iCloud", value: describe(sync.lastImport, busy: sync.busy))
            if [sync.lastSetup, sync.lastExport, sync.lastImport].contains(where: { $0?.error != nil }) {
                Label("iCloud isn't reachable right now. Your boards are safe on this device, and Hum tries again by itself.",
                      systemImage: "exclamationmark.icloud")
                    .font(.footnote).foregroundStyle(.orange)
            }
        }
    }

    private func describe(_ event: SyncMonitor.EventInfo?, busy: Bool) -> String {
        if busy { return "Syncing…" }
        guard let event else { return "Not yet since Hum opened" }
        let when = event.date.formatted(.relative(presentation: .named))
        return event.succeeded ? when.prefix(1).uppercased() + when.dropFirst() : "Failed \(when)"
    }
}
