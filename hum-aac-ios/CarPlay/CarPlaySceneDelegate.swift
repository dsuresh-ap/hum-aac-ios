// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

#if os(iOS)
import CarPlay
import SwiftData
import CoreData
import ImageIO

/// Hum on a car's screen. Each car board (CarBoard.swift) is a tab with a grid of up to 8 tiles; a
/// folder tile on a tab opens its folder. Tapping a tile says its phrase through the car's speakers.
/// The About me card (AboutMeCard.swift), when filled in, is one more tab.
///
/// Every grid has two buttons at the top: "Show" puts the last phrase on the screen in big text, for
/// someone outside the window to read, with "Say again" and "Earlier" (what was said since the car
/// connected); "Stop" cuts off a phrase that's playing.
///
/// CarPlay draws the screen itself from Apple's templates; Hum only says what's on it. Driving task
/// apps may go two screens deep, so a folder or the Earlier list opens from a tab and nothing opens
/// further. Named in Hum-Info.plist (UIApplicationSceneManifest), so its name must not change.
@objc(CarPlaySceneDelegate)
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private struct ShownGrid {
        let boardID: UUID
        let template: CPGridTemplate
        let isFolder: Bool
        var signature: [String]
    }

    private var interfaceController: CPInterfaceController?
    /// The tabs as they were built (boards, names, the card), so a change that adds or removes a tab
    /// rebuilds the screen and anything smaller updates a grid in place.
    private var layout: [String] = []
    /// The templates a tab starts with (and the tab bar): anything else on top is one screen deep.
    private var roots: [CPTemplate] = []
    /// Every grid built since the last rebuild: one per tab, and the open folder.
    private var grids: [ShownGrid] = []
    private var stopButtons: [CPBarButton] = []
    /// Earlier lists only what was said after this, never older history.
    private var connectedAt = Date.now
    private var speakingWatch: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private var model: AppModel? { CarPlayHost.model }

    // MARK: Scene life cycle

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        connectedAt = .now
        model?.speech.sharesOutput = true
        // The car can start Hum while the iPhone is locked, before its window ever shows: find the voice
        // the board uses, like launch does.
        if let model, model.defaultVoiceIdentifier == nil { Task { await model.upgradeVoiceIfBetterInstalled() } }
        interfaceController.setRootTemplate(makeRoot(), animated: false, completion: nil)
        observeChanges()
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        speakingWatch?.cancel()
        model?.speech.sharesOutput = false
        self.interfaceController = nil
        layout = []
        roots = []
        grids = []
        stopButtons = []
    }

    // MARK: Tabs

    private struct Layout {
        var key: [String]
        var boards: [Board]
        /// Boards a folder tile may open from a tab: the ones with something to tap.
        var openable: Set<UUID>
        var card: AboutMeCard?
    }

    private func currentLayout(_ model: AppModel) -> Layout {
        guard !model.needsFirstRun else { return Layout(key: ["setup"], boards: [], openable: [], card: nil) }
        let openable = Set(model.store.boards().filter { !CarBoard.tiles(on: $0).isEmpty }.map(\.id))
        let card = model.settings.aboutMe.isEmpty ? nil : model.settings.aboutMe
        // The card keeps its tab when the car allows fewer tabs than there are boards.
        let boardTabs = max(CPTabBarTemplate.maximumTabCount - (card == nil ? 0 : 1), 1)
        let boards = Array(CarBoard.boards(in: model).prefix(boardTabs))
        var key = boards.map { "\($0.id)|\($0.name)|\(CarBoard.tiles(on: $0, openable: openable).isEmpty)" }
        if let card { key.append("card|\(card.name)|\(card.shownLines)|\(card.contactText)") }
        return Layout(key: key, boards: boards, openable: openable, card: card)
    }

    private func makeRoot() -> CPTemplate {
        roots = []
        grids = []
        stopButtons = []
        guard let model else {
            layout = []
            return message(String(localized: "Set up Hum on your iPhone first.", comment: "CarPlay: shown in the car before Hum has a board."))
        }
        let current = currentLayout(model)
        layout = current.key
        var tabs = current.boards.map { tab(for: $0, openable: current.openable) }
        if let card = current.card { tabs.append(aboutMe(card)) }
        guard !tabs.isEmpty else {
            let root = message(String(localized: "Set up Hum on your iPhone first.", comment: "CarPlay: shown in the car before Hum has a board."))
            roots = [root]
            return root
        }
        roots = tabs
        guard tabs.count > 1 else { return tabs[0] }
        let bar = CPTabBarTemplate(templates: tabs)
        roots.append(bar)
        return bar
    }

    private func tab(for board: Board, openable: Set<UUID>) -> CPTemplate {
        let reachable = openable.subtracting([board.id])
        let tiles = CarBoard.tiles(on: board, openable: reachable)
        let template: CPTemplate = tiles.isEmpty
            ? message(String(localized: "This board has no tiles yet. Add some in Hum on your iPhone.",
                             comment: "CarPlay: a board chosen for the car is empty."), title: board.name)
            : grid(for: board, tiles: tiles, openable: reachable, isFolder: false)
        template.tabTitle = board.name
        template.tabImage = UIImage(systemName: board.isHome ? "house.fill" : "square.grid.2x2.fill")
        return template
    }

    private func message(_ text: String, title: String = "Hum") -> CPInformationTemplate {
        CPInformationTemplate(title: title, layout: .leading, items: [CPInformationItem(title: text, detail: nil)], actions: [])
    }

    private func grid(for board: Board, tiles: [Tile], openable: Set<UUID>, isFolder: Bool) -> CPGridTemplate {
        let template = CPGridTemplate(title: board.name, gridButtons: tiles.map { button(for: $0, openable: openable) })
        let show = CPBarButton(title: String(localized: "Show", comment: "CarPlay: button that shows the last phrase in big text.")) { [weak self] _ in
            self?.show()
        }
        let stop = CPBarButton(title: String(localized: "Stop", comment: "CarPlay: button that stops the phrase playing now.")) { [weak self] _ in
            self?.stopSpeaking()
        }
        stop.isEnabled = speakingWatch != nil
        stopButtons.append(stop)
        template.trailingNavigationBarButtons = [show, stop]
        grids.append(ShownGrid(boardID: board.id, template: template, isFolder: isFolder,
                               signature: signature(board, tiles, openable)))
        prepareSpeech(tiles)
        return template
    }

    private func button(for tile: Tile, openable: Set<UUID>) -> CPGridButton {
        let id = tile.id
        let speaks = CarBoard.speaks(tile)
        let folder = CarBoard.opens(tile, openable: openable)
        let title = tile.label.isEmpty ? tile.spokenText : tile.label
        return CPGridButton(titleVariants: [title], image: image(for: tile)) { [weak self] _ in
            // Like on the iPhone: a folder tile says its phrase (if it has one), then opens.
            if speaks { self?.say(tileID: id) }
            if let folder { self?.openFolder(folder) }
        }
    }

    private func signature(_ board: Board, _ tiles: [Tile], _ openable: Set<UUID>) -> [String] {
        [board.name] + tiles.map {
            "\($0.id)|\($0.label)|\($0.spokenText)|\($0.symbol ?? "")|\($0.imageData?.count ?? 0)|\($0.audioData?.count ?? 0)|\(CarBoard.opens($0, openable: openable)?.uuidString ?? "")"
        }
    }

    // MARK: Folders

    private func openFolder(_ id: UUID) {
        guard let interfaceController, let model, let board = model.store.boards().first(where: { $0.id == id }) else { return }
        // Inside a folder nothing opens further: its folder tiles only speak.
        let tiles = CarBoard.tiles(on: board)
        guard !tiles.isEmpty else { return }
        grids.removeAll(where: \.isFolder)
        interfaceController.pushTemplate(grid(for: board, tiles: tiles, openable: [], isFolder: true), animated: true, completion: nil)
    }

    private var isAtRoot: Bool {
        guard let top = interfaceController?.topTemplate else { return true }
        return roots.contains { $0 === top }
    }

    // MARK: Keeping up with changes

    /// A save on this iPhone, a sync from another device or a change in Settings: rebuild if the tabs
    /// changed, else redraw only the grids whose tiles changed.
    private func refresh() {
        guard let interfaceController, let model else { return }
        let current = currentLayout(model)
        guard current.key == layout else {
            interfaceController.setRootTemplate(makeRoot(), animated: false, completion: nil)
            return
        }
        let all = model.store.boards()
        var closeFolder = false
        for index in grids.indices {
            let shown = grids[index]
            guard let board = all.first(where: { $0.id == shown.boardID }) else {
                if shown.isFolder { closeFolder = true }
                continue
            }
            let openable = shown.isFolder ? [] : current.openable.subtracting([board.id])
            let tiles = CarBoard.tiles(on: board, openable: openable)
            let now = signature(board, tiles, openable)
            guard now != shown.signature else { continue }
            if tiles.isEmpty {
                // A tab that became empty changes the layout key, so only a folder gets here.
                if shown.isFolder { closeFolder = true }
                continue
            }
            grids[index].signature = now
            shown.template.updateTitle(board.name)
            shown.template.updateGridButtons(tiles.map { button(for: $0, openable: openable) })
            prepareSpeech(tiles)
        }
        if closeFolder {
            grids.removeAll(where: \.isFolder)
            if !isAtRoot { interfaceController.popToRootTemplate(animated: true, completion: nil) }
        }
    }

    private func observeChanges() {
        let center = NotificationCenter.default
        let refresh: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        observers.append(center.addObserver(forName: ModelContext.didSave, object: nil, queue: .main, using: refresh))
        observers.append(center.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main, using: refresh))
        observeSettings()
    }

    /// A parent changes the car boards or the About me card in Settings.
    private func observeSettings() {
        guard let model else { return }
        withObservationTracking {
            _ = model.settings.carBoardIDs
            _ = model.settings.aboutMe
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.interfaceController != nil else { return }
                self.refresh()
                self.observeSettings()
            }
        }
    }

    // MARK: Speaking

    private func say(tileID id: UUID) {
        guard let model else { return }
        Task {
            guard await model.say(tileID: id) else { return }
            watchSpeaking()
            if model.settings.carShowsEachPhrase, let entry = model.history.entries.last, entry.tileID == id {
                present(entry, offerEarlier: true)
            }
        }
    }

    /// Stop works while something plays, and goes grey again once it ends.
    private func watchSpeaking() {
        speakingWatch?.cancel()
        setStopEnabled(true)
        speakingWatch = Task { [weak self] in
            // Live speech takes a moment to start.
            try? await Task.sleep(for: .milliseconds(400))
            while !Task.isCancelled, self?.model?.speech.isSpeaking == true {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled, let self else { return }
            self.speakingWatch = nil
            self.setStopEnabled(false)
        }
    }

    private func stopSpeaking() {
        model?.speech.stop()
        speakingWatch?.cancel()
        speakingWatch = nil
        setStopEnabled(false)
    }

    private func setStopEnabled(_ enabled: Bool) {
        for button in stopButtons where button.isEnabled != enabled { button.isEnabled = enabled }
    }

    /// Renders the car tiles' phrases ahead of time, so the first tap in the car doesn't wait.
    private func prepareSpeech(_ tiles: [Tile]) {
        guard let model else { return }
        model.speech.prepare(tiles.map(\.spokenText).filter { !$0.isEmpty })
        model.speech.prepareRecordings(tiles.compactMap { tile in
            tile.audioData.map { (AppModel.recordingKey(tile.id, $0), $0) }
        })
    }

    // MARK: Show

    /// The last phrase said since the car connected, in big text. With nothing said yet, the (empty)
    /// Earlier list, which says what will show up there.
    private func show() {
        guard let model else { return }
        if let last = model.history.recent(1, since: connectedAt).first, CPAlertTemplate.maximumActionCount >= 3 {
            present(last, offerEarlier: true)
        } else {
            pushEarlier()
        }
    }

    /// A phrase in big text, for someone outside the window to read. It stays until Done.
    private func present(_ entry: SpeechHistory.Entry, offerEarlier: Bool) {
        guard let interfaceController else { return }
        var actions = [CPAlertAction(title: String(localized: "Say again", comment: "CarPlay: says the phrase on screen again."),
                                     style: .default) { [weak self] _ in
            guard let self, let model = self.model else { return }
            Task {
                await model.sayAgain(entry)
                self.watchSpeaking()
            }
        }]
        if offerEarlier && CPAlertTemplate.maximumActionCount >= 3 {
            actions.append(CPAlertAction(title: String(localized: "Earlier", comment: "CarPlay: lists the phrases said before, since the car connected."),
                                         style: .default) { [weak self] _ in
                self?.interfaceController?.dismissTemplate(animated: true) { _, _ in
                    Task { @MainActor in self?.pushEarlier() }
                }
            })
        }
        actions.append(CPAlertAction(title: String(localized: "Done"), style: .cancel) { [weak self] _ in
            self?.interfaceController?.dismissTemplate(animated: true, completion: nil)
        })
        let alert = CPAlertTemplate(titleVariants: [entry.spokenText], actions: actions)
        if interfaceController.presentedTemplate != nil {
            interfaceController.dismissTemplate(animated: false) { [weak self] _, _ in
                Task { @MainActor in self?.interfaceController?.presentTemplate(alert, animated: true, completion: nil) }
            }
        } else {
            interfaceController.presentTemplate(alert, animated: true, completion: nil)
        }
    }

    /// What was said since the car connected, newest first. Tapping one shows it big. The list doesn't
    /// change while it's open, so a row never moves under a finger.
    private func pushEarlier() {
        guard let interfaceController, let model else { return }
        let entries = model.history.recent(CPListTemplate.maximumItemCount, since: connectedAt)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let items = entries.map { entry in
            let item = CPListItem(text: entry.spokenText, detailText: formatter.localizedString(for: entry.date, relativeTo: .now))
            item.handler = { [weak self] _, completion in
                MainActor.assumeIsolated { self?.present(entry, offerEarlier: false) }
                completion()
            }
            return item
        }
        let list = CPListTemplate(title: String(localized: "Said in the car", comment: "CarPlay: title of the list of phrases said since the car connected."),
                                  sections: [CPListSection(items: items)])
        list.emptyViewTitleVariants = [String(localized: "Nothing said yet", comment: "CarPlay: the list of phrases said in the car is empty.")]
        list.emptyViewSubtitleVariants = [String(localized: "Phrases said since the car connected show here.",
                                                 comment: "CarPlay: explains the empty list of phrases said in the car.")]
        // Two screens deep at most: from a folder, go back to the tab first.
        if isAtRoot {
            interfaceController.pushTemplate(list, animated: true, completion: nil)
        } else {
            interfaceController.popToRootTemplate(animated: false) { [weak self] _, _ in
                Task { @MainActor in self?.interfaceController?.pushTemplate(list, animated: true, completion: nil) }
            }
        }
    }

    // MARK: About me

    private func aboutMe(_ card: AboutMeCard) -> CPTemplate {
        var items: [CPInformationItem] = []
        let name = card.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { items.append(CPInformationItem(title: name, detail: nil)) }
        items += card.shownLines.map { CPInformationItem(title: $0, detail: nil) }
        if card.hasContact {
            items.append(CPInformationItem(title: String(localized: "Emergency contact", comment: "CarPlay About me card: heading for the contact's name and number."),
                                           detail: card.contactText))
        }
        let spoken = card.spokenText
        let say = CPTextButton(title: String(localized: "Say this", comment: "CarPlay About me card: reads the card out."), textStyle: .confirm) { [weak self] _ in
            self?.model?.say(phrase: spoken)
            self?.watchSpeaking()
        }
        let stop = CPTextButton(title: String(localized: "Stop", comment: "CarPlay: button that stops the phrase playing now."), textStyle: .normal) { [weak self] _ in
            self?.stopSpeaking()
        }
        let title = String(localized: "About me", comment: "CarPlay: tab with the driver's card for an officer or helper to read.")
        let template = CPInformationTemplate(title: title, layout: .leading, items: items, actions: [say, stop])
        template.tabTitle = title
        template.tabImage = UIImage(systemName: "person.text.rectangle.fill")
        model?.speech.prepare([spoken])
        return template
    }

    // MARK: Pictures

    /// The tile's photo or symbol, at the size CarPlay draws grid buttons.
    private func image(for tile: Tile) -> UIImage {
        let scale = interfaceController?.carTraitCollection.displayScale ?? 2
        let side: CGFloat
        if #available(iOS 26.0, *) {
            side = max(CPGridTemplate.maximumGridButtonImageSize.width, 40)
        } else {
            side = 60
        }
        let size = CGSize(width: side, height: side)
        if let data = tile.imageData, let photo = Self.decode(data, maxPixels: Int(side * scale)) {
            return UIImage(cgImage: photo, scale: scale, orientation: .up)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        if let symbol = tile.symbol, !symbol.isEmpty {
            return UIGraphicsImageRenderer(size: size, format: format).image { _ in
                let text = NSAttributedString(string: symbol, attributes: [.font: UIFont.systemFont(ofSize: side * 0.8)])
                let box = text.size()
                text.draw(at: CGPoint(x: (side - box.width) / 2, y: (side - box.height) / 2))
            }
        }
        if tile.linkedBoardID != nil { return UIImage(systemName: "folder.fill") ?? UIImage() }
        return UIImage(systemName: "text.bubble.fill") ?? UIImage()
    }

    private static func decode(_ data: Data, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
#endif
