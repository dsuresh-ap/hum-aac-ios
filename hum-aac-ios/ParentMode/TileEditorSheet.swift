// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import HumConfig
#if canImport(ImagePlayground)
import ImagePlayground
#endif

/// Add or edit one tile (or a folder). The everyday fields come first:
/// Picture → What it says → Label → Folder. Color, hide and delete wait under "More options".
struct TileEditorSheet: View {
    let request: TileEditorRequest

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Board.createdAt) private var boards: [Board]

    /// What a tile does when tapped, besides speaking.
    enum Link: Hashable { case none, newFolder, board(UUID) }

    /// Everything the parent can change, to tell whether Cancel would lose anything.
    struct Draft: Equatable {
        var spokenText = ""
        var label = ""
        var function: TileFunction?
        var colorHex: String?
        var link = Link.none
        var isHidden = false
        var symbol = ""
        var imageData: Data?
        var audioData: Data?
    }

    enum Field: Hashable { case phrase, label }

    @State private var spokenText = ""
    @State private var label = ""
    @State private var labelEdited = false
    @State private var function: TileFunction?
    @State private var useCustomColor = false
    @State private var customColor = Color(hex: 0xCFE6CC)
    @State private var link = Link.none
    @State private var isHidden = false
    /// The parent's emoji. While untouched, the tile shows (and saves) a guess from its words.
    @State private var symbol = ""
    @State private var symbolTouched = false
    @State private var imageData: Data?
    /// The symbol set's credit while the picture is a symbol from it. Set only through `setPicture`.
    @State private var imageCredit: String?
    /// Names guessed from the current photo ("dog", "ball"). Only shown; nothing changes until the parent taps one.
    @State private var photoIdeas = PhotoNameIdeas()
    @State private var audioData: Data?
    @State private var recorder = PhraseRecorder()
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showFileImporter = false
    @State private var showEmojiPicker = false
    @State private var pickerSource = EmojiPickerView.Source.emoji
    @State private var showImagePlayground = false
    @State private var showMore = false
    @State private var confirmDelete = false
    @State private var confirmDiscard = false
    @State private var loaded = false
    @State private var initial = Draft()
    @FocusState private var focus: Field?

    private var existing: Tile? {
        guard case .edit(let id) = request.kind else { return nil }
        return (try? model.context.fetch(FetchDescriptor<Tile>(predicate: #Predicate { $0.id == id })))?.first
    }

    private var hasWords: Bool { !spokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var hasLabel: Bool { !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// A tile needs words to say, except a folder tile, which can just open its folder (it needs a name).
    private var canSave: Bool { hasWords || (link != .none && hasLabel) }
    /// New folders ask for the name first; the phrase is optional.
    private var folderFirst: Bool { request.startsAsFolder && existing == nil }

    private var suggestedSymbol: String? { EmojiSuggester.suggestion(label: label, spokenText: spokenText) }
    /// The emoji the tile shows and saves.
    private var shownSymbol: String { symbolTouched || !symbol.isEmpty ? symbol : (suggestedSymbol ?? "") }

    private var draft: Draft {
        Draft(spokenText: spokenText, label: label, function: function,
              colorHex: useCustomColor ? customColor.hexString : nil, link: link, isHidden: isHidden,
              symbol: symbolTouched ? symbol : initial.symbol, imageData: imageData, audioData: audioData)
    }
    private var hasChanges: Bool { loaded && draft != initial }

    var body: some View {
        NavigationStack {
            Form {
                pictureSection
                if folderFirst {
                    labelSection
                    phraseSection
                } else {
                    phraseSection
                    labelSection
                }
                recordingSection
                folderSection
                moreSection
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityIdentifier("saveTile")
                }
            }
            .interactiveDismissDisabled(hasChanges)
            .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                if canSave { Button("Save") { save() } }
                Button("Keep editing", role: .cancel) {}
            } message: {
                Text("You changed this tile but haven't saved it yet.")
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
                        setPhoto(ImageProcessing.tileImageData(from: data))
                    }
                }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image]) { result in
                guard case .success(let url) = result else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) { setPhoto(ImageProcessing.tileImageData(from: data)) }
            }
            .sheet(isPresented: $showEmojiPicker) {
                EmojiPickerView(selection: Binding(get: { shownSymbol }, set: {
                    symbol = $0
                    symbolTouched = true
                    // A photo always wins over an emoji, so choosing an emoji means "use this instead".
                    if pickerSource == .emoji { setPicture(nil) }
                }),
                                label: label, spokenText: spokenText,
                                onSymbol: { setPicture($0, credit: $1) },
                                source: pickerSource)
            }
            .modifier(ImagePlaygroundSheet(isPresented: $showImagePlayground, concept: playgroundConcept) { data in
                setPicture(ImageProcessing.tileImageData(from: data))
            })
            #if os(iOS)
            .fullScreenCover(isPresented: $showCamera) {
                // Cancel (nil) keeps the photo the tile already has.
                CameraPicker { data in
                    if let photo = data.flatMap(ImageProcessing.tileImageData(from:)) { setPhoto(photo) }
                }
                    .ignoresSafeArea()
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 620)
        #endif
    }

    private var title: String {
        if existing != nil { return link == .none ? String(localized: "Edit tile") : String(localized: "Edit folder") }
        return folderFirst ? String(localized: "New folder") : String(localized: "New tile")
    }

    /// What VoiceOver reads for the picture square.
    private var pictureAccessibilityLabel: String {
        if imageData != nil { return String(localized: "Picture: photo") }
        return shownSymbol.isEmpty ? String(localized: "Picture: none") : String(localized: "Picture: \(shownSymbol)")
    }

    // MARK: Sections

    private var pictureSection: some View {
        Section {
            HStack(alignment: .top, spacing: 16) {
                Group {
                    if let imageData, let image = PlatformImage.thumbnail(imageData, maxPixels: 300) {
                        Image(decorative: image, scale: 1).resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.chrome)
                    } else {
                        Text(shownSymbol.isEmpty ? "📷" : shownSymbol).font(.system(size: 44))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.chrome)
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(.rect(cornerRadius: 14))
                .dropDestination(for: ImagePayload.self) { items, _ in
                    guard let data = items.first?.data, let processed = ImageProcessing.tileImageData(from: data) else { return false }
                    setPhoto(processed)
                    return true
                }
                .accessibilityLabel(pictureAccessibilityLabel)

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
                    PasteButton(payloadType: ImagePayload.self) { items in
                        if let data = items.first?.data, let processed = ImageProcessing.tileImageData(from: data) {
                            setPhoto(processed)
                        }
                    }
                    .labelStyle(.titleAndIcon)
                    .controlSize(.small)
                    CreateImageButton { showImagePlayground = true }
                    Button("Find a symbol…", systemImage: "square.grid.3x3.square") {
                        pickerSource = .symbols
                        showEmojiPicker = true
                    }
                    Button(imageData == nil ? "Choose emoji…" : "Use an emoji instead…", systemImage: "face.smiling") {
                        pickerSource = .emoji
                        showEmojiPicker = true
                    }
                    if imageData != nil {
                        Button("Remove photo", systemImage: "xmark.circle", role: .destructive) { setPicture(nil) }
                    }
                }
                .buttonStyle(.borderless)
            }
            if imageData != nil, let imageCredit {
                Text(imageCredit)
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Picture credit: \(imageCredit)")
                    .accessibilityIdentifier("tileEditor.imageCredit")
            }
            if imageData != nil, !photoIdeas.names.isEmpty {
                objectIdeasRow
            }
            if imageData == nil {
                let ideas = EmojiSuggester.suggestions(label: label, spokenText: spokenText, limit: 6)
                if !ideas.isEmpty {
                    HStack(spacing: 6) {
                        Text("Ideas:").font(.callout).foregroundStyle(.secondary)
                        ForEach(ideas, id: \.self) { emoji in
                            Button {
                                symbol = emoji
                                symbolTouched = true
                            } label: {
                                Text(emoji).font(.title2)
                                    .padding(4)
                                    .background(emoji == shownSymbol ? Color.accentColor.opacity(0.25) : .clear, in: .rect(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        } header: {
            Text("Picture")
        } footer: {
            Text(imageData == nil
                 ? "Hum picks an emoji from the words until you add a photo. Real photos often work better than drawings. You can also drag a picture onto the square."
                 : "Real photos often work better than drawings.")
        }
    }

    /// "Looks like: dog · puppy": Hum's guesses for a new photo. A tap fills in the words; the parent still saves.
    private var objectIdeasRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Looks like:").font(.callout).foregroundStyle(.secondary)
            // One line when they fit; otherwise one name per line, so a long name never wraps mid-word.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { objectIdeaButtons }
                VStack(alignment: .leading, spacing: 6) { objectIdeaButtons }
            }
            Text("Hum's guess from the photo, made on this device. Tap one to use it, or type your own words.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var objectIdeaButtons: some View {
        ForEach(photoIdeas.names, id: \.self) { name in
            Button { useObjectName(name) } label: {
                Text(name).lineLimit(1).fixedSize()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityHint("Uses this word for the tile")
            .accessibilityIdentifier("tileEditor.objectIdea")
        }
    }

    private var phraseSection: some View {
        Section {
            HStack(alignment: .top) {
                TextField(folderFirst ? "e.g. I want a snack (optional)" : "e.g. Let's get out of here!", text: $spokenText, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focus, equals: .phrase)
                    .onSubmit(submit)
                    .accessibilityIdentifier("spokenTextField")
                    .onChange(of: spokenText) { _, new in if !labelEdited { label = Self.suggestLabel(new) } }
                Button {
                    model.speech.speak(spokenText)
                } label: {
                    Image(systemName: "play.circle.fill").font(.title2)
                }
                .buttonStyle(.borderless)
                .disabled(!hasWords)
                .accessibilityLabel("Hear the phrase")
                .help("Hear the phrase")
            }
            if let phrase = GLPRules.discouragedPhrase(in: spokenText) {
                Text("“\(phrase)” sounds like praise or an instruction. Hum tiles are your child's own voice, so we suggest a phrase your child would say.")
                    .font(.footnote).foregroundStyle(.orange)
            }
        } header: {
            Text(folderFirst ? "Say something when it opens? (optional)" : "What does this tile say?")
        } footer: {
            Text(folderFirst
                 ? "Leave empty to just open the folder."
                 : "Type the full phrase, just the way your child says it, even if it's from a show or a song. Keep it in one piece. Don't split it into single words.")
        }
    }

    private var labelSection: some View {
        Section {
            TextField(folderFirst ? "e.g. Snacks" : "Label", text: $label)
                .focused($focus, equals: .label)
                .onSubmit(submit)
                .onChange(of: label) { _, new in labelEdited = new != Self.suggestLabel(spokenText) }
                .accessibilityIdentifier("labelField")
        } header: {
            Text(folderFirst ? "Folder name" : "Label")
        } footer: {
            Text(folderFirst
                 ? "Shown on the folder tile and at the top of the folder."
                 : "The short words printed on the tile. Hum fills them in from the phrase. You can change them if you like.")
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
                    Text(Duration.seconds(recorder.elapsed).formatted(.units(allowed: [.seconds], width: .narrow, fractionalPart: .show(length: 1))))
                        .monospacedDigit().foregroundStyle(.secondary)
                } else {
                    Button(audioData == nil ? "Record your voice" : "Record again", systemImage: "mic.circle") {
                        Task { await recorder.start() }
                    }
                    if let audioData {
                        Button("Play", systemImage: "play.circle") { recorder.play(audioData) }
                        Spacer()
                        Button("Remove recording", systemImage: "trash", role: .destructive) { self.audioData = nil }
                            .labelStyle(.iconOnly)
                            .help("Remove the recording")
                    }
                }
            }
            .buttonStyle(.borderless)
            if recorder.state == .denied {
                Text("Hum isn't allowed to use the microphone. You can allow it in Settings → Privacy & Security → Microphone.")
                    .font(.footnote).foregroundStyle(.orange)
            }
        } footer: {
            Text("Optional. Record the phrase with the same tune and rhythm your child knows. The tile plays your recording instead of the computer voice. It stays on this device.")
        }
    }

    private var folderSection: some View {
        Section {
            Picker("When tapped, also open", selection: $link) {
                Text("Nothing (just speak)").tag(Link.none)
                Text(newFolderTitle).tag(Link.newFolder)
                let others = boards.filter { $0.id != currentBoardID }
                if !others.isEmpty {
                    Divider()
                    ForEach(others) { b in
                        Text(b.isHome ? String(localized: "\(b.name) (Home)") : b.name).tag(Link.board(b.id))
                    }
                }
            }
        } header: {
            Text("Folder")
        } footer: {
            Text("A folder tile opens another page of tiles, like \"Food\" or \"Outside\". Your child comes back with the Back or Home button.")
        }
    }

    private var newFolderTitle: String {
        hasLabel ? String(localized: "A new folder: \(BoardStore.folderName(from: label))") : String(localized: "A new folder")
    }

    private var moreSection: some View {
        Section {
            DisclosureGroup("More options", isExpanded: $showMore) {
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
                Toggle("Hide for now", isOn: $isHidden)
                Text("\"What is it for?\" only sets the color. A hidden tile keeps its spot as empty space, so nothing else moves.")
                    .font(.footnote).foregroundStyle(.secondary)
                if existing != nil {
                    Button("Delete tile", systemImage: "trash", role: .destructive) { confirmDelete = true }
                }
            }
        }
    }

    // MARK: Actions

    private var currentBoardID: UUID? {
        switch request.kind {
        case .new(let boardID, _, _): return boardID
        case .edit: return existing?.board?.id
        }
    }

    /// The words Image Playground starts from.
    private var playgroundConcept: String {
        let words = spokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        return words.isEmpty ? label : words
    }

    /// A short label from a long phrase: the first few words, without trailing punctuation.
    static func suggestLabel(_ phrase: String) -> String {
        ProposalChecker.shortLabel(for: phrase.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func load() {
        guard !loaded else { return }
        defer {
            initial = draft
            loaded = true
            // Start typing right away on a new tile.
            if existing == nil {
                DispatchQueue.main.async { focus = folderFirst ? .label : .phrase }
            }
        }
        if folderFirst { link = .newFolder }
        guard let tile = existing else { return }
        spokenText = tile.spokenText
        label = tile.label
        labelEdited = tile.label != Self.suggestLabel(tile.spokenText)
        function = tile.function
        if let hex = tile.colorHex, let value = UInt32(hex.dropFirst(), radix: 16) {
            useCustomColor = true
            customColor = Color(hex: value)
        }
        link = tile.linkedBoardID.map { id in boards.contains { $0.id == id } ? .board(id) : .none } ?? .none
        isHidden = tile.isHidden
        symbol = tile.symbol ?? ""
        imageData = tile.imageData
        imageCredit = tile.imageData == nil ? nil : tile.imageCredit
        audioData = tile.audioData
        initial.symbol = symbol
    }

    /// Every picture change goes through here. A photo, a drawing or no picture clears the credit;
    /// only a symbol from a symbol set brings one.
    private func setPicture(_ data: Data?, credit: String? = nil) {
        imageData = data
        imageCredit = data == nil ? nil : credit
        photoIdeas.pictureChanged(to: data)
    }

    /// A photo from the camera, Photos, a file, a drop or the clipboard. Hum guesses what's in it (on this
    /// device), to offer names. Symbols and created images already come from words, so they skip this.
    private func setPhoto(_ data: Data?) {
        setPicture(data)
        guard let data else { return }
        Task { await photoIdeas.guess(data, using: model.objectClassifier) }
    }

    /// Fills the label, and the phrase too while it's empty or still an earlier guess. The parent's own
    /// words are kept.
    private func useObjectName(_ name: String) {
        spokenText = photoIdeas.phrase(using: name, instead: spokenText)
        label = name
    }

    /// Return in a text field saves, when there's enough to save.
    private func submit() {
        if canSave { save() }
    }

    private func cancel() {
        if recorder.state == .recording { _ = recorder.finish() }
        if hasChanges { confirmDiscard = true } else { dismiss() }
    }

    private func save() {
        if recorder.state == .recording, let data = recorder.finish() { audioData = data }
        let text = spokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalLabel = hasLabel ? label.trimmingCharacters(in: .whitespacesAndNewlines) : Self.suggestLabel(text)
        let finalSymbol = shownSymbol
        let folderName = link == .newFolder ? BoardStore.folderName(from: finalLabel) : nil
        let apply: (Tile) -> Void = { tile in
            tile.spokenText = text
            tile.label = finalLabel
            tile.function = function
            tile.colorHex = useCustomColor ? customColor.hexString : nil
            if case .board(let id) = link { tile.linkedBoardID = id } else { tile.linkedBoardID = nil }
            tile.isHidden = isHidden
            tile.symbol = finalSymbol.isEmpty ? nil : finalSymbol
            tile.imageData = imageData
            tile.imageCredit = imageData == nil ? nil : imageCredit
            tile.audioData = audioData
        }
        // A new folder starts with one row (two if it's one across); it grows as tiles are added.
        let columns = model.settings.newBoardColumns, rows = columns == 1 ? 2 : 1
        var saved: Tile?
        switch request.kind {
        case .new(let boardID, let row, let column):
            guard let board = model.store.board(boardID) else { break }
            saved = model.store.addTile(to: board, row: row, column: column, phoneSpot: request.phoneSpot, newFolderName: folderName,
                                        rows: rows, columns: columns, apply)
        case .edit:
            if let tile = existing {
                model.store.update(tile, newFolderName: folderName, rows: rows, columns: columns, apply)
                saved = tile
            }
        }
        if !text.isEmpty { model.speech.prepare([text]) }
        dismiss()
        // A brand-new folder is empty: go straight in so the parent can fill it.
        if folderName != nil, let id = saved?.linkedBoardID { model.openFolderInEditor(id) }
    }
}

/// "Create image": Apple's Image Playground, starting from the tile's words. Only shown on devices that
/// support it. Styles are limited to Apple's own (no outside image services).
private struct CreateImageButton: View {
    let action: () -> Void

    var body: some View {
        #if canImport(ImagePlayground)
        if #available(iOS 18.4, macOS 15.4, *) {
            Available(action: action)
        }
        #endif
    }

    #if canImport(ImagePlayground)
    @available(iOS 18.4, macOS 15.4, *)
    private struct Available: View {
        let action: () -> Void
        @Environment(\.supportsImagePlayground) private var supported

        var body: some View {
            if supported {
                Button("Create image…", systemImage: "wand.and.sparkles", action: action)
            }
        }
    }
    #endif
}

private struct ImagePlaygroundSheet: ViewModifier {
    @Binding var isPresented: Bool
    let concept: String
    let onImage: (Data) -> Void

    func body(content: Content) -> some View {
        #if canImport(ImagePlayground)
        if #available(iOS 18.4, macOS 15.4, *) {
            content
                .imagePlaygroundSheet(isPresented: $isPresented, concept: concept) { url in
                    if let data = try? Data(contentsOf: url) { onImage(data) }
                }
                .imagePlaygroundGenerationStyle(.illustration, in: [.illustration, .animation, .sketch])
        } else {
            content
        }
        #else
        content
        #endif
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
