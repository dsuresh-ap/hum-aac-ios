// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import HumConfig

/// Add or edit one tile. Fields follow the order parents think in:
/// Photo → What it says → Label → Color → Opens a board.
struct TileEditorSheet: View {
    let request: TileEditorRequest

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Board.createdAt) private var boards: [Board]

    @State private var spokenText = ""
    @State private var label = ""
    @State private var labelEdited = false
    @State private var function: TileFunction?
    @State private var useCustomColor = false
    @State private var customColor = Color(hex: 0xCFE6CC)
    @State private var linkedBoardID: UUID?
    @State private var isHidden = false
    @State private var symbol = ""
    @State private var imageData: Data?
    @State private var audioData: Data?
    @State private var recorder = PhraseRecorder()
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showFileImporter = false
    @State private var confirmDelete = false
    @State private var loaded = false
    /// A folder board made from this sheet; removed again if the parent cancels.
    @State private var createdFolderID: UUID?

    private var existing: Tile? {
        guard case .edit(let id) = request.kind else { return nil }
        return (try? model.context.fetch(FetchDescriptor<Tile>(predicate: #Predicate { $0.id == id })))?.first
    }

    private var hasWords: Bool { !spokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// A tile needs words to say, except a folder tile, which can just open its board (it needs a label).
    private var canSave: Bool {
        hasWords || (linkedBoardID != nil && !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                photoSection
                Section {
                    HStack(alignment: .top) {
                        TextField("e.g. Let's get out of here!", text: $spokenText, axis: .vertical)
                            .lineLimit(1...4)
                            .accessibilityIdentifier("spokenTextField")
                            .onChange(of: spokenText) { _, new in if !labelEdited { label = Self.suggestLabel(new) } }
                        Button {
                            model.speech.speak(spokenText)
                        } label: {
                            Image(systemName: "play.circle.fill").font(.title2)
                        }
                        .buttonStyle(.borderless)
                        .disabled(!hasWords)
                        .accessibilityLabel("Play")
                    }
                    if let phrase = GLPRules.discouragedPhrase(in: spokenText) {
                        Text("“\(phrase)” sounds like praise or an instruction. Hum tiles are your child's own voice, so we suggest a phrase your child would say.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                } header: {
                    Text("What does this tile say?")
                } footer: {
                    Text("Type the whole phrase, just the way your child says it, even if it's from a show or a song. Keep it whole. Don't split it into single words.")
                }

                recordingSection

                Section {
                    TextField("Label", text: $label)
                        .onChange(of: label) { _, new in labelEdited = new != Self.suggestLabel(spokenText) }
                        .accessibilityIdentifier("labelField")
                } header: {
                    Text("Label")
                } footer: {
                    Text("The short words printed on the tile. Your child hears the whole phrase.")
                }

                Section {
                    Picker("What is it for?", selection: $function) {
                        Text("Not sure").tag(TileFunction?.none)
                        Text("Asking for something").tag(TileFunction?.some(.request))
                        Text("Saying no / stop").tag(TileFunction?.some(.protest))
                        Text("Body & feelings").tag(TileFunction?.some(.regulation))
                        Text("Hello, bye, together").tag(TileFunction?.some(.connection))
                        Text("Sharing what they notice").tag(TileFunction?.some(.comment))
                        Text("Something else").tag(TileFunction?.some(.other))
                    }
                    Toggle("Choose my own color", isOn: $useCustomColor)
                    if useCustomColor {
                        ColorPicker("Tile color", selection: $customColor, supportsOpacity: false)
                    }
                } header: {
                    Text("Color")
                } footer: {
                    Text("Used only for color. Every tile always works the same, and \"no\" tiles are as big as all the others.")
                }

                Section {
                    Picker("When tapped, also open", selection: $linkedBoardID) {
                        Text("Nothing (just speak)").tag(UUID?.none)
                        ForEach(boards.filter { $0.id != currentBoardID }) { b in
                            Text(b.name).tag(Optional(b.id))
                        }
                    }
                    if linkedBoardID == nil {
                        Button("Make this tile a new folder", systemImage: "folder.badge.plus") { makeFolder() }
                    }
                } header: {
                    Text("Folder")
                } footer: {
                    Text("A folder tile opens another board, like \"Food\" or \"Outside\". Your child comes back with the Back or Home button. A folder tile can say its phrase first, or just open (leave \"What does this tile say?\" empty).")
                }

                Section {
                    TextField("Emoji until you add a photo", text: $symbol)
                    Toggle("Hide for now", isOn: $isHidden)
                } footer: {
                    Text("A hidden tile keeps its spot as empty space, so nothing else moves.")
                }

                if existing != nil {
                    Section {
                        Button("Delete tile", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existing == nil ? "New tile" : "Edit tile")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        // Don't leave behind an empty folder board the parent didn't keep.
                        if let id = createdFolderID, let board = model.store.board(id), (board.tiles ?? []).isEmpty {
                            try? model.store.delete(board)
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .accessibilityIdentifier("saveTile")
                }
            }
            .confirmationDialog("Delete this tile?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete tile", role: .destructive) {
                    if let tile = existing { model.store.delete(tile) }
                    dismiss()
                }
            } message: {
                Text("Its spot will be empty. Other tiles stay where they are. You can undo this.")
            }
            .onAppear(perform: load)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        imageData = ImageProcessing.tileImageData(from: data)
                    }
                }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image]) { result in
                guard case .success(let url) = result else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) { imageData = ImageProcessing.tileImageData(from: data) }
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { data in imageData = data.flatMap(ImageProcessing.tileImageData(from:)) }
                    .ignoresSafeArea()
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 620)
        #endif
    }

    private var photoSection: some View {
        Section {
            HStack(spacing: 16) {
                Group {
                    if let imageData, let image = PlatformImage.thumbnail(imageData, maxPixels: 300) {
                        Image(decorative: image, scale: 1).resizable().scaledToFill()
                    } else {
                        Text(symbol.isEmpty ? "📷" : symbol).font(.system(size: 44))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.chrome)
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(.rect(cornerRadius: 14))
                .dropDestination(for: Data.self) { items, _ in
                    guard let data = items.first, let processed = ImageProcessing.tileImageData(from: data) else { return false }
                    imageData = processed
                    return true
                }

                VStack(alignment: .leading, spacing: 8) {
                    #if os(iOS)
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Take photo", systemImage: "camera") { showCamera = true }
                    }
                    #endif
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose photo", systemImage: "photo.on.rectangle")
                    }
                    #if os(macOS)
                    Button("Choose file…", systemImage: "folder") { showFileImporter = true }
                    #endif
                    if imageData != nil {
                        Button("No photo", systemImage: "xmark.circle", role: .destructive) { imageData = nil }
                    }
                }
                .buttonStyle(.borderless)
            }
        } header: {
            Text("Photo")
        } footer: {
            Text("Add a photo of the real thing. Real photos often work better than drawings.")
        }
    }

    private var recordingSection: some View {
        Section {
            HStack(spacing: 12) {
                if recorder.state == .recording {
                    Button("Stop", systemImage: "stop.circle.fill") {
                        if let data = recorder.finish() { audioData = data }
                        model.speech.engine.restart()
                    }
                    .foregroundStyle(.red)
                    Text(String(format: "%.1f s", recorder.elapsed)).monospacedDigit().foregroundStyle(.secondary)
                } else {
                    Button(audioData == nil ? "Record" : "Record again", systemImage: "mic.circle") {
                        Task { await recorder.start() }
                    }
                    if let audioData {
                        Button("Play", systemImage: "play.circle") { recorder.play(audioData) }
                        Spacer()
                        Button("Remove", systemImage: "trash", role: .destructive) { self.audioData = nil }
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .buttonStyle(.borderless)
            if recorder.state == .denied {
                Text("Hum isn't allowed to use the microphone. You can allow it in Settings → Privacy & Security → Microphone.")
                    .font(.footnote).foregroundStyle(.orange)
            }
        } header: {
            Text("Say it in your own voice (optional)")
        } footer: {
            Text("Record the phrase the way your child hears it, with the same tune. The tile plays your recording instead of the computer voice. It stays on this device.")
        }
    }

    /// Creates an empty board named after this tile and links the tile to it.
    private func makeFolder() {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "New folder" : trimmed.prefix(1).uppercased() + trimmed.dropFirst()
        let board = model.store.createBoard(name: name, rows: model.settings.newBoardRows, columns: model.settings.newBoardColumns)
        createdFolderID = board.id
        linkedBoardID = board.id
        if label.isEmpty { label = name }
        labelEdited = true
    }

    private var currentBoardID: UUID? {
        switch request.kind {
        case .new(let boardID, _, _): return boardID
        case .edit: return existing?.board?.id
        }
    }

    /// A short label from a long phrase: the first few words, without trailing punctuation.
    static func suggestLabel(_ phrase: String) -> String {
        let words = phrase.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        let short = words.prefix(4).joined(separator: " ")
        return short.trimmingCharacters(in: CharacterSet(charactersIn: "!?.,;:"))
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let tile = existing else { return }
        spokenText = tile.spokenText
        label = tile.label
        labelEdited = tile.label != Self.suggestLabel(tile.spokenText)
        function = tile.function
        if let hex = tile.colorHex, let value = UInt32(hex.dropFirst(), radix: 16) {
            useCustomColor = true
            customColor = Color(hex: value)
        }
        linkedBoardID = tile.linkedBoardID
        isHidden = tile.isHidden
        symbol = tile.symbol ?? ""
        imageData = tile.imageData
        audioData = tile.audioData
    }

    private func save() {
        let text = spokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalLabel = label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Self.suggestLabel(text) : label
        let apply: (Tile) -> Void = { tile in
            tile.spokenText = text
            tile.label = finalLabel
            tile.function = function
            tile.colorHex = useCustomColor ? customColor.hexString : nil
            tile.linkedBoardID = linkedBoardID
            tile.isHidden = isHidden
            tile.symbol = symbol.isEmpty ? nil : symbol
            tile.imageData = imageData
            tile.audioData = audioData
        }
        switch request.kind {
        case .new(let boardID, let row, let column):
            guard let board = model.store.board(boardID) else { break }
            model.store.change("Add Tile") {
                let tile = Tile(label: finalLabel, spokenText: text, row: row, column: column)
                model.context.insert(tile)
                tile.board = board
                apply(tile)
            }
        case .edit:
            if let tile = existing { model.store.update(tile, apply) }
        }
        if !text.isEmpty { model.speech.prepare([text]) }
        dismiss()
    }
}

extension Color {
    /// "#RRGGBB" for storing a parent's custom color.
    var hexString: String? {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        #else
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let (r, g, b) = (c.redComponent, c.greenComponent, c.blueComponent)
        #endif
        return String(format: "#%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }
}

#if os(iOS)
/// Camera capture (iOS/iPadOS). Asks for camera permission only when the parent taps "Take photo".
struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (Data?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (Data?) -> Void
        init(onFinish: @escaping (Data?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            onFinish(image?.jpegData(compressionQuality: 0.9))
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
            picker.dismiss(animated: true)
        }
    }
}
#endif
