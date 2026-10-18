// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import AVFoundation
import CoreGraphics

/// "What's this?": the child points the camera at something and Hum shows up to three words for it.
/// A word speaks only when the child taps it. Off until a parent turns it on in Settings.
nonisolated enum WhatsThisCamera {
    enum Availability: Equatable { case available, notInEnglish, noCamera }

    /// Whether this device can offer it. The names come from ObjectNamer, which knows English only.
    static func availability(language: String? = Bundle.main.preferredLocalizations.first, hasCamera: Bool) -> Availability {
        guard ObjectNamer.isAvailable(language: language) else { return .notInEnglish }
        return hasCamera ? .available : .noCamera
    }

    /// The child's button shows only when a parent turned it on and the camera may already be used, so
    /// the child never meets a permission prompt.
    static func showsButton(settingOn: Bool, availability: Availability, cameraAllowed: Bool) -> Bool {
        settingOn && availability == .available && cameraAllowed
    }

    /// Looked up once: asking for the camera device on every redraw would be slow.
    static let deviceHasCamera = CameraController.camera() != nil

    static var cameraAllowed: Bool { AVCaptureDevice.authorizationStatus(for: .video) == .authorized }

    /// Asks for the camera, in parent mode. True when Hum may use it.
    static func requestCamera() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }
}

extension AppModel {
    var whatsThisAvailability: WhatsThisCamera.Availability {
        WhatsThisCamera.availability(hasCamera: usesFakeCamera || WhatsThisCamera.deviceHasCamera)
    }

    var showsWhatsThisButton: Bool {
        WhatsThisCamera.showsButton(settingOn: settings.whatsThisCamera, availability: whatsThisAvailability,
                                    cameraAllowed: usesFakeCamera || WhatsThisCamera.cameraAllowed)
    }
}

/// The child's camera button: a small outlined circle like the word finder, by the lock.
struct WhatsThisButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(Theme.tileText.opacity(0.2), lineWidth: 3)
                Image(systemName: "camera.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.tileText.opacity(0.6))
            }
            .frame(width: 36, height: 36)
            .padding(4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What's this?")
        .accessibilityHint("Opens the camera")
        .accessibilityIdentifier("whatsThis")
    }
}

/// The full-screen camera. One big shutter, one big close button where Home is, and after a picture the
/// guessed words as big tile-like buttons. Nothing speaks by itself, and the picture is never kept.
struct WhatsThisView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Step: Equatable { case starting, live, looking, words([String]), noWords, noCamera }

    @State private var step = Step.starting
    @State private var photo: CGImage?
    @State private var camera = CameraController()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // The live view fills the screen. A picture taken sits above its words instead (below).
            if photo == nil {
                if model.usesFakeCamera {
                    FakeCameraPreview()
                } else if step != .noCamera {
                    CameraPreview(camera: camera).ignoresSafeArea()
                        .accessibilityHidden(true)
                }
            }
            VStack {
                HStack {
                    closeButton
                    Spacer()
                }
                if let photo {
                    Image(decorative: photo, scale: 1).resizable().scaledToFit()
                        .clipShape(.rect(cornerRadius: 18, style: .continuous))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("Your picture")
                } else {
                    Spacer()
                }
                bottom
            }
            .padding(Theme.gridPadding)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: step)
        .task { await startCamera() }
        .onDisappear { camera.stop() }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 560)
        #endif
    }

    /// Where the Home button is on the board, so the way back is where the child expects it.
    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 80, height: 64)
                .background(Theme.chrome, in: .rect(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .accessibilityHint("Back to the board")
        .accessibilityIdentifier("whatsThis.close")
    }

    @ViewBuilder private var bottom: some View {
        switch step {
        case .starting:
            EmptyView()
        case .live:
            Button { Task { await snap() } } label: {
                Circle().fill(.white)
                    .padding(8)
                    .background(Circle().stroke(.white, lineWidth: 6))
                    .frame(width: 104, height: 104)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Take a picture")
            .accessibilityIdentifier("whatsThis.shutter")
        case .looking:
            ProgressView().controlSize(.large).tint(.white)
                .padding(24)
                .accessibilityLabel("Looking at the picture")
        case .words(let words):
            VStack(spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { wordButtons(words) }
                    VStack(spacing: 12) { wordButtons(words) }
                }
                retakeButton(big: false)
            }
        case .noWords:
            VStack(spacing: 16) {
                Text("Try again")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                retakeButton(big: true)
            }
        case .noCamera:
            Text("The camera isn't working right now.")
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxHeight: .infinity)
        }
    }

    private func wordButtons(_ words: [String]) -> some View {
        ForEach(words, id: \.self) { word in
            Button { model.sayGuess(word) } label: {
                Text(word)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Theme.tileInk(function: nil, hex: nil))
                    .padding(.horizontal, 28)
                    .frame(minWidth: 140, minHeight: 96)
                    .background(Theme.tileColor(function: nil, hex: nil), in: .rect(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(word)
            .accessibilityHint("Says this word")
            .accessibilityIdentifier("whatsThis.word")
        }
    }

    private func retakeButton(big: Bool) -> some View {
        Button { retake() } label: {
            Label("Take another", systemImage: "camera.fill")
                .font(.system(big ? .title2 : .title3, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 24)
                .frame(minHeight: big ? 72 : 56)
                .background(Theme.chrome, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("whatsThis.retake")
    }

    // MARK: Actions

    private func startCamera() async {
        if model.usesFakeCamera {
            step = .live
            return
        }
        step = await camera.start() ? .live : .noCamera
    }

    private func snap() async {
        model.noteTouch()
        let raw = model.usesFakeCamera ? FakeCameraPreview.pictureData() : await camera.capture()
        guard let raw, let data = ImageProcessing.tileImageData(from: raw) else {
            step = .noWords
            return
        }
        photo = PlatformImage.thumbnail(data, maxPixels: 1024)
        step = .looking
        let words = await ObjectNamer.names(for: data, using: model.objectClassifier)
        // Ready before the child taps, so a word speaks as fast as a tile.
        model.speech.prepare(words)
        step = words.isEmpty ? .noWords : .words(words)
    }

    private func retake() {
        model.noteTouch()
        photo = nil
        step = .live
    }
}

/// The live picture from the camera.
private struct CameraPreview {
    let camera: CameraController
}

#if os(iOS)
extension CameraPreview: UIViewRepresentable {
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = camera.session
        view.previewLayer.videoGravity = .resizeAspectFill
        camera.attach(view.previewLayer)
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}
}
#else
extension CameraPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: camera.session)
        layer.videoGravity = .resizeAspectFill
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer = layer
        view.wantsLayer = true
        camera.attach(layer)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
#endif

/// UI tests have no camera: a still, colored "view" stands in, and the shutter takes this picture.
private struct FakeCameraPreview: View {
    var body: some View {
        LinearGradient(colors: [.teal, .indigo], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }

    static func pictureData() -> Data? {
        guard let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        return context.makeImage().flatMap { ImageProcessing.jpegData($0) }
    }
}

/// The camera itself (the back camera on iPad and iPhone, the FaceTime camera on a Mac). Pictures stay in
/// memory and are never saved.
nonisolated final class CameraController: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "hum.whatsThis.camera")
    private var pending: CheckedContinuation<Data?, Never>?
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private weak var previewLayer: AVCaptureVideoPreviewLayer?

    static func camera() -> AVCaptureDevice? {
        #if os(iOS)
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) ?? AVCaptureDevice.default(for: .video)
        #else
        AVCaptureDevice.default(for: .video)
        #endif
    }

    /// Sets the camera up once and starts it. False when there's no camera or Hum may not use it.
    func start() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.run()) }
        }
    }

    private func run() -> Bool {
        if session.inputs.isEmpty {
            guard WhatsThisCamera.cameraAllowed, let device = Self.camera(),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input), session.canAddOutput(output) else { return false }
            session.beginConfiguration()
            session.sessionPreset = .photo
            session.addInput(input)
            session.addOutput(output)
            session.commitConfiguration()
        }
        if !session.isRunning { session.startRunning() }
        return session.isRunning
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    /// Keeps the preview level as the iPad turns, and the picture the right way up.
    @MainActor func attach(_ layer: AVCaptureVideoPreviewLayer) {
        guard let device = Self.camera() else { return }
        previewLayer = layer
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: layer)
        rotation = coordinator
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.levelPreview() }
        }
    }

    @MainActor private func levelPreview() {
        guard let angle = rotation?.videoRotationAngleForHorizonLevelPreview,
              let connection = previewLayer?.connection, connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    /// One picture, as image data. Nil if the camera isn't running.
    func capture() async -> Data? {
        let angle = rotation?.videoRotationAngleForHorizonLevelCapture
        return await withCheckedContinuation { continuation in
            queue.async {
                guard self.session.isRunning, self.pending == nil else { return continuation.resume(returning: nil) }
                if let angle, let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
                self.pending = continuation
                self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        queue.async {
            self.pending?.resume(returning: data)
            self.pending = nil
        }
    }
}
