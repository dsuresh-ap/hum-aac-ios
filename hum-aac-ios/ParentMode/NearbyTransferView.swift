// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import HumConfig

/// Share & sync → Send to a nearby device. Lists devices that have their Receive screen open.
struct NearbySendView: View {
    @Environment(AppModel.self) private var model
    @State private var transfer = NearbyTransfer(role: .send, transport: NetworkTransport())
    @State private var preparing = true
    @State private var prepareError: String?
    /// The board to send on its own, or nil for all boards.
    @State private var onlyBoardID: UUID?
    /// The code the parent reads on the other device.
    @State private var typedCode = ""

    var body: some View {
        Form {
            Section {
                Text("On the other device, open Hum, go to Share & sync, and tap “Receive from a nearby device”.")
                // Like "Export “Home” only…": the board being edited can go on its own.
                if let board = editingBoard {
                    Picker("What to send", selection: $onlyBoardID) {
                        Text("All boards").tag(UUID?.none)
                        Text("Only “\(board.name)”").tag(UUID?.some(board.id))
                    }
                    .disabled(!canChoose && !preparing)
                }
            }

            if preparing || prepareError != nil || transfer.state != .looking {
                Section { status }
            }

            Section {
                if transfer.peers.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Looking for devices…").foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                ForEach(transfer.peers) { peer in
                    Button { transfer.send(to: peer) } label: {
                        Label(peer.name, systemImage: NearbyDeviceIcon.name(for: peer.name))
                    }
                    .disabled(!canChoose)
                }
            } header: {
                Text("Nearby devices")
            } footer: {
                if let board = editingBoard, onlyBoardID == board.id {
                    Text("Sends “\(board.name)” with its photos and recordings. Nothing goes through the internet.")
                } else {
                    Text("Sends all your boards, photos and settings. Nothing goes through the internet.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Send to a nearby device")
        .onAppear { transfer.start() }
        .onDisappear { transfer.stop() }
        // Made again when the choice changes.
        .task(id: onlyBoardID) { await prepareFile() }
    }

    private var editingBoard: Board? { model.editingBoardID.flatMap(model.fetchBoard) }

    @ViewBuilder private var status: some View {
        if let prepareError {
            Label(prepareError, systemImage: "exclamationmark.triangle")
        } else if preparing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Preparing your boards…").foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
        switch transfer.state {
        case .connecting(let peer):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Connecting to “\(peer.name)”…")
            }
            .accessibilityElement(children: .combine)
            Button("Cancel", role: .cancel) { transfer.cancel() }
        case .confirming(let peer):
            // The parent types the code from the other screen, so it can't be skipped: nothing about the
            // boards is sent until it matches.
            VStack(alignment: .leading, spacing: 8) {
                Text("Type the code shown on “\(peer.name)”.")
                TextField("Code", text: $typedCode)
                    .font(.system(.title, design: .monospaced))
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .onSubmit(confirm)
                    .onChange(of: typedCode) { _, code in
                        if code.filter(\.isNumber).count == 6 { confirm() }
                    }
                    .accessibilityIdentifier("nearbyCode")
                if transfer.codeWasWrong {
                    Text("That code doesn't match. Check the code on the other device and type it again.")
                        .foregroundStyle(.red)
                }
                Text("Nothing is sent until the code matches.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .onAppear { typedCode = "" }
            Button("Send", systemImage: "paperplane", action: confirm)
                .disabled(typedCode.filter(\.isNumber).count != 6)
            Button("Cancel", role: .cancel) { transfer.cancel() }
        case .waitingForAnswer(let peer):
            Text("Waiting for “\(peer.name)” to accept.")
            Button("Cancel", role: .cancel) { transfer.cancel() }
        case .transferring(let fraction):
            ProgressView(value: fraction) { Text("Sending…") }
            Button("Cancel", role: .cancel) { transfer.cancel() }
        case .sent:
            Label("Sent. On the other device, choose how to add the boards.", systemImage: "checkmark.circle")
        case .declined:
            Label("The other device didn't accept.", systemImage: "xmark.circle")
        case .failed(let error):
            Label(error.message, systemImage: "exclamationmark.triangle")
        case .idle, .looking, .pairing, .asking, .received:
            EmptyView()
        }
    }

    private func confirm() {
        if !transfer.confirm(code: typedCode) { typedCode = "" }
    }

    private var canChoose: Bool {
        guard transfer.hasFile, !preparing else { return false }
        switch transfer.state {
        case .looking, .declined, .sent, .failed: return true
        default: return false
        }
    }

    /// Makes the `.hum` file (all boards, or one) in the background while devices are found.
    private func prepareFile() async {
        preparing = true
        prepareError = nil
        let boardID = onlyBoardID
        let name = boardID.flatMap(model.fetchBoard)?.name
        let (document, media) = ImportService(model: model).exportContents(boardID: boardID)
        do {
            let data = try await Task.detached(priority: .userInitiated) { try HumPackage.write(document, media: media) }.value
            // The parent changed their mind while this was being made: the newer one wins.
            guard !Task.isCancelled else { return }
            defer { preparing = false }
            try transfer.setFile(data, name: ImportService.exportFileName(boardName: name))
        } catch let error as NearbyTransferError {
            prepareError = error.message
            preparing = false
        } catch {
            prepareError = error.localizedDescription
            preparing = false
        }
    }
}

/// Share & sync → Receive from a nearby device. This device can only be found while this screen is open.
struct NearbyReceiveView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var transfer: NearbyTransfer?
    /// Stopped while Hum wasn't the app in front; starts again when it is.
    @State private var paused = false

    var body: some View {
        Form {
            if let transfer {
                Section {
                    content(transfer)
                } footer: {
                    Text("Other devices see this one as “\(transfer.localName)” while this screen is open. Nothing goes through the internet.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Receive from a nearby device")
        .onAppear {
            let transfer = transfer ?? NearbyTransfer(role: .receive, transport: NetworkTransport()) { [model] data, name in
                // The same preview as a file from AirDrop or Files.
                model.requestImport(data: data, fileName: name)
            }
            self.transfer = transfer
            transfer.start()
        }
        .onDisappear { transfer?.stop() }
        // Findable only while Hum is the app in front.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { resume() } else { pause() }
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in pause() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in resume() }
        #endif
    }

    /// Stops being findable while only waiting. A transfer under way carries on, and once a file has
    /// arrived the screen never starts listening again by itself.
    private func pause() {
        guard let transfer, transfer.state == .looking else { return }
        transfer.stop()
        paused = true
    }

    private func resume() {
        guard paused else { return }
        paused = false
        transfer?.start()
    }

    @ViewBuilder private func content(_ transfer: NearbyTransfer) -> some View {
        switch transfer.state {
        case .idle, .looking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for a device…")
            }
            .accessibilityElement(children: .combine)
            Text("On your other device, open Hum, go to Share & sync, and tap “Send to a nearby device”.")
                .foregroundStyle(.secondary)
        case .pairing(let code):
            VStack(alignment: .leading, spacing: 8) {
                Text("A device wants to send you boards. Type this code on it:")
                MatchingCode(code: code)
                Text("Only type it on your own device, the one where you just tapped it in the list.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button("Cancel", role: .cancel) { transfer.cancel() }
        case .asking(let offer):
            VStack(alignment: .leading, spacing: 8) {
                Text("“\(offer.senderName)” wants to send “\(offer.fileName)” (\(Int64(offer.byteCount).formatted(.byteCount(style: .file)))).")
                Text("Accept only if you're sending this from your own device right now.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button("Accept", systemImage: "checkmark") { transfer.accept() }
                .accessibilityIdentifier("acceptNearby")
            Button("Decline", systemImage: "xmark", role: .destructive) { transfer.decline() }
        case .transferring(let fraction):
            ProgressView(value: fraction) { Text("Receiving…") }
            Button("Cancel", role: .cancel) { transfer.cancel() }
        case .received:
            Label("Received. Choose how to add the boards.", systemImage: "checkmark.circle")
            Button("Receive another") { restart(transfer) }
        case .failed(let error):
            Label(error.message, systemImage: "exclamationmark.triangle")
            Button("Try again") { restart(transfer) }
        case .connecting, .confirming, .waitingForAnswer, .sent, .declined:
            EmptyView()
        }
    }

    private func restart(_ transfer: NearbyTransfer) {
        transfer.stop()
        transfer.start()
    }
}

/// The six-digit code, in two groups of three.
private struct MatchingCode: View {
    let code: String

    var body: some View {
        Text(verbatim: "\(code.prefix(3)) \(code.suffix(3))")
            .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
            .accessibilityLabel(Text("Code \(code.map(String.init).joined(separator: " "))"))
    }
}

private enum NearbyDeviceIcon {
    static func name(for deviceName: String) -> String {
        let lowered = deviceName.lowercased()
        if lowered.contains("iphone") { return "iphone" }
        if lowered.contains("ipad") { return "ipad" }
        if lowered.contains("mac") { return "laptopcomputer" }
        return "display"
    }
}
