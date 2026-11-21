// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

#if os(iOS)
import CarPlay
import SwiftData
import CoreData
import ImageIO

/// Hum on a car's screen: one grid of up to 8 tiles from the car board (CarBoard.swift). Tapping a
/// tile says its phrase through the car's speakers. "Show" puts the last phrase on the screen in big
/// text, for someone outside the window to read, with "Say again".
///
/// CarPlay draws the screen itself from Apple's templates; Hum only says what's on it. Named in
/// Hum-Info.plist (UIApplicationSceneManifest), so its name must not change.
@objc(CarPlaySceneDelegate)
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var grid: CPGridTemplate?
    private var showButton: CPBarButton?
    /// What the grid shows now, so a save elsewhere only redraws it when something changed.
    private var shown: [String] = []
    /// The phrase "Show" puts on screen: the last tile tapped in the car.
    private var lastSaid: (id: UUID, text: String)?
    private var observers: [NSObjectProtocol] = []

    private var model: AppModel? { CarPlayHost.model }

    // MARK: Scene life cycle

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
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
        model?.speech.sharesOutput = false
        self.interfaceController = nil
        grid = nil
        shown = []
        lastSaid = nil
    }

    // MARK: Screen

    private func makeRoot() -> CPTemplate {
        guard let model, !model.needsFirstRun, let board = CarBoard.board(in: model) else {
            return message(String(localized: "Set up Hum on your iPhone first.", comment: "CarPlay: shown in the car before Hum has a board."))
        }
        let tiles = CarBoard.tiles(on: board)
        shown = signature(board, tiles)
        guard !tiles.isEmpty else {
            grid = nil
            return message(String(localized: "This board has no tiles yet. Add some in Hum on your iPhone.",
                                  comment: "CarPlay: the board chosen for the car is empty."))
        }
        let show = CPBarButton(title: String(localized: "Show", comment: "CarPlay: button that shows the last phrase in big text.")) { [weak self] _ in
            self?.showLastPhrase()
        }
        show.isEnabled = lastSaid != nil
        showButton = show
        let template = CPGridTemplate(title: board.name, gridButtons: tiles.map(button))
        template.trailingNavigationBarButtons = [show]
        grid = template
        prepareSpeech(tiles)
        return template
    }

    private func message(_ text: String) -> CPTemplate {
        grid = nil
        return CPInformationTemplate(title: "Hum", layout: .leading,
                                     items: [CPInformationItem(title: text, detail: nil)], actions: [])
    }

    private func button(for tile: Tile) -> CPGridButton {
        let id = tile.id
        let title = tile.label.isEmpty ? tile.spokenText : tile.label
        let text = tile.spokenText.isEmpty ? title : tile.spokenText
        return CPGridButton(titleVariants: [title], image: image(for: tile)) { [weak self] _ in
            self?.say(id, text: text)
        }
    }

    /// A save on this iPhone or a sync from another device: redraw only if the car board changed.
    private func refresh() {
        guard let interfaceController, let model else { return }
        guard let board = CarBoard.board(in: model), !model.needsFirstRun else {
            if !shown.isEmpty || grid != nil { interfaceController.setRootTemplate(makeRoot(), animated: false, completion: nil) }
            return
        }
        let tiles = CarBoard.tiles(on: board)
        let now = signature(board, tiles)
        guard now != shown else { return }
        if let grid, !tiles.isEmpty {
            shown = now
            grid.updateTitle(board.name)
            grid.updateGridButtons(tiles.map(button))
            prepareSpeech(tiles)
        } else {
            interfaceController.setRootTemplate(makeRoot(), animated: false, completion: nil)
        }
    }

    private func signature(_ board: Board, _ tiles: [Tile]) -> [String] {
        [board.id.uuidString, board.name] + tiles.map {
            "\($0.id)|\($0.label)|\($0.spokenText)|\($0.symbol ?? "")|\($0.imageData?.count ?? 0)|\($0.audioData?.count ?? 0)"
        }
    }

    private func observeChanges() {
        let center = NotificationCenter.default
        let refresh: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        observers.append(center.addObserver(forName: ModelContext.didSave, object: nil, queue: .main, using: refresh))
        observers.append(center.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main, using: refresh))
        observeCarBoardChoice()
    }

    /// A parent picks another board for the car in Settings.
    private func observeCarBoardChoice() {
        guard let model else { return }
        withObservationTracking {
            _ = model.settings.carBoardID
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.interfaceController != nil else { return }
                self.refresh()
                self.observeCarBoardChoice()
            }
        }
    }

    // MARK: Speaking

    private func say(_ id: UUID, text: String) {
        guard let model else { return }
        lastSaid = (id, text)
        showButton?.isEnabled = true
        Task { _ = await model.say(tileID: id) }
    }

    /// The last phrase in big text, for someone outside the window to read.
    private func showLastPhrase() {
        guard let interfaceController, let lastSaid else { return }
        let sayAgain = CPAlertAction(title: String(localized: "Say again", comment: "CarPlay: says the phrase on screen again."),
                                     style: .default) { [weak self] _ in
            guard let self, let model = self.model else { return }
            Task { _ = await model.say(tileID: lastSaid.id) }
        }
        let done = CPAlertAction(title: String(localized: "Done"), style: .cancel) { [weak interfaceController] _ in
            interfaceController?.dismissTemplate(animated: true, completion: nil)
        }
        interfaceController.presentTemplate(CPAlertTemplate(titleVariants: [lastSaid.text], actions: [sayAgain, done]),
                                            animated: true, completion: nil)
    }

    /// Renders the car tiles' phrases ahead of time, so the first tap in the car doesn't wait.
    private func prepareSpeech(_ tiles: [Tile]) {
        guard let model else { return }
        model.speech.prepare(tiles.map(\.spokenText))
        model.speech.prepareRecordings(tiles.compactMap { tile in
            tile.audioData.map { (AppModel.recordingKey(tile.id, $0), $0) }
        })
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
