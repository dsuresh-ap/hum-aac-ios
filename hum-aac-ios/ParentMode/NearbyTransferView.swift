// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Share & sync → Send to a nearby device. Lists devices that have their Receive screen open.
struct NearbySendView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var transfer = NearbyTransfer(role: .send, transport: NetworkTransport())
    @State private var preparing = true
    @State private var prepareError: String?
    /// The board to send on its own, or nil for all boards.
    @State private var onlyBoardID: UUID?

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
        // Every visit starts clean: no old status, code or device.
        .onAppear { transfer.restart() }
        .onDisappear { transfer.stop() }
        // A code or question on the other screen can't wait while Hum is in the background.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { transfer.leave() }
        }
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
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.borderless)  // its own button, not the whole row
            }
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
            CodeEntry(prompt: "Type the code shown on “\(peer.name)”.", note: "Nothing is sent until the code matches.",
                      actionTitle: "Send", actionImage: "paperplane", wrong: transfer.codeWasWrong) { transfer.confirm(code: $0) }
                .id(transfer.attempt)  // an empty field for every try
            Button("Cancel", role: .cancel) { transfer.cancel() }
        case .waitingForAnswer(let peer, let code):
            VStack(alignment: .leading, spacing: 8) {
                Text("Type this code on “\(peer.name)” to let it accept:")
                MatchingCode(code: code)
                Text("Waiting for “\(peer.name)” to accept.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button("Cancel", role: .cancel) { transfer.cancel() }
        case .transferring(let fraction):
            ProgressView(value: fraction) { Text("Sending…") }
            Button("Cancel", role: .cancel) { transfer.cancel() }
        case .sent:
            Label("Sent. On the other device, choose how to add the boards.", systemImage: "checkmark.circle")
        case .declined:
            ending(String(localized: "Decline was tapped on the other device."), systemImage: "xmark.circle")
        case .failed(let error):
            ending(error.message, systemImage: "exclamationmark.triangle")
        case .idle, .looking, .pairing, .asking, .received:
            EmptyView()
        }
    }

    /// What happened, what to do next, and a way forward: the other device has stopped listening.
    @ViewBuilder private func ending(_ message: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(message, systemImage: systemImage)
            Text("To try again, on the other device tap “Receive again” or open “Receive from a nearby device”. Then pick that device in the list below.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        Button("Try again", systemImage: "arrow.clockwise") { transfer.restart() }
            .accessibilityIdentifier("nearbyTryAgain")
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
        do {
            let data = try await ImportService(model: model).exportPackage(boardID: boardID)
            // The parent changed their mind while this was being made: the newer one wins.
            guard !Task.isCancelled else { return }
            defer { preparing = false }
            try transfer.setFile(data, name: ImportService.exportFileName(boardName: name))
        } catch is CancellationError {
            return
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

    /// Stops being findable when Hum isn't in front. Only plain waiting starts again by itself; a code or
    /// a question on screen is cancelled, and a transfer under way carries on.
    private func pause() {
        guard let transfer else { return }
        switch transfer.state {
        case .looking:
            transfer.stop()
            paused = true
        case .pairing, .asking:
            transfer.leave()
        default:
            break
        }
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
                Text("A device wants to send you boards. On that device, type this code:")
                MatchingCode(code: code)
                Text("Type the code only on your own device, the one where you just tapped this device in the list.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button("Cancel", role: .cancel) { transfer.cancel() }
        case .asking(let offer):
            Text("“\(offer.senderName)” wants to send “\(offer.fileName)” (\(Int64(offer.byteCount).formatted(.byteCount(style: .file)))).")
            // The sender's code, so a stranger's device can't push boards in.
            CodeEntry(prompt: "Type the code shown on “\(offer.senderName)”.",
                      note: "Accept only if you're sending this from your own device right now.",
                      actionTitle: "Accept", actionImage: "checkmark", wrong: transfer.codeWasWrong) { transfer.accept(code: $0) }
                .id(transfer.attempt)  // an empty field for every try
                .accessibilityIdentifier("acceptNearby")
            Button("Decline", systemImage: "xmark", role: .destructive) { transfer.decline() }
        case .transferring(let fraction):
            ProgressView(value: fraction) { Text("Receiving…") }
            Button("Cancel", role: .cancel) { transfer.cancel() }
        case .received:
            Label("Received. Choose how to add the boards.", systemImage: "checkmark.circle")
            Button("Receive another") { transfer.restart() }
        case .failed(let error):
            // Not listening any more: say why, and one clear way to start again.
            Label(error.message, systemImage: "exclamationmark.triangle")
            Button {
                transfer.restart()
            } label: {
                Label("Receive again", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("receiveAgain")
        case .connecting, .confirming, .waitingForAnswer, .sent, .declined:
            EmptyView()
        }
    }
}

/// Where the parent types the six-digit code shown on the other device. It goes as soon as six digits
/// are in; a wrong code clears the field.
private struct CodeEntry: View {
    let prompt: LocalizedStringKey
    let note: LocalizedStringKey
    let actionTitle: LocalizedStringKey
    let actionImage: String
    let wrong: Bool
    let submit: (String) -> Bool
    @State private var typed = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(prompt)
            TextField("Code", text: $typed)
                .font(.system(.title, design: .monospaced))
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .onSubmit(go)
                .onChange(of: typed) { _, code in
                    if nearbyCodeDigits(code).count == 6 { go() }
                }
                .accessibilityIdentifier("nearbyCode")
            if wrong {
                Text("That code doesn't match. Check the code on the other device and type it again.")
                    .foregroundStyle(.red)
            }
            Text(note)
                .font(.footnote).foregroundStyle(.secondary)
        }
        Button(actionTitle, systemImage: actionImage, action: go)
            .disabled(nearbyCodeDigits(typed).count != 6)
    }

    private func go() {
        if !submit(typed) { typed = "" }
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
