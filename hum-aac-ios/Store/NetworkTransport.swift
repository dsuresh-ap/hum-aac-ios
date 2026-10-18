// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Network
#if os(iOS)
import UIKit
#else
import SystemConfiguration
#endif

/// `NearbyTransport` with the Network framework: Bonjour on the local network, plus Wi-Fi straight
/// between Apple devices when they share no network. Nothing goes through the internet or a server.
/// The bytes are encrypted by `NearbyLink`.
final class NetworkTransport: NearbyTransport {
    /// Also listed in Info.plist (NSBonjourServices).
    static let serviceType = "_hum-setup._tcp"

    var onEvent: ((NearbyTransportEvent) -> Void)?
    let localName = NetworkTransport.deviceName()

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var endpoints: [String: NWEndpoint] = [:]

    private static var parameters: NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 10
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }

    func advertise() {
        stop()
        let listener: NWListener
        do { listener = try NWListener(using: Self.parameters) } catch {
            onEvent?(.failed(.couldNotConnect))
            return
        }
        listener.service = NWListener.Service(name: localName, type: Self.serviceType)
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            MainActor.assumeIsolated {
                guard let self, let listener, self.listener === listener else { return }
                if case .failed = state { self.onEvent?(.failed(.couldNotConnect)) }
            }
        }
        listener.newConnectionHandler = { [weak self, weak listener] connection in
            MainActor.assumeIsolated {
                guard let self, let listener, self.listener === listener else { return connection.cancel() }
                self.onEvent?(.incoming(NetworkChannel(connection)))
            }
        }
        self.listener = listener
        listener.start(queue: .main)
    }

    func browse() {
        stop()
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: Self.parameters)
        browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
            MainActor.assumeIsolated {
                guard let self, let browser, self.browser === browser else { return }
                self.update(results)
            }
        }
        browser.stateUpdateHandler = { [weak self, weak browser] state in
            MainActor.assumeIsolated {
                guard let self, let browser, self.browser === browser else { return }
                if case .failed = state { self.onEvent?(.failed(.couldNotConnect)) }
            }
        }
        self.browser = browser
        browser.start(queue: .main)
    }

    func connect(to peer: NearbyPeer) -> NearbyChannel {
        let endpoint = endpoints[peer.id] ?? .service(name: peer.name, type: Self.serviceType, domain: "local.", interface: nil)
        return NetworkChannel(NWConnection(to: endpoint, using: Self.parameters))
    }

    func stop() {
        listener?.cancel()
        listener = nil
        browser?.cancel()
        browser = nil
        endpoints = [:]
    }

    /// One row per device (a device can be found on Wi-Fi and directly at once).
    private func update(_ results: Set<NWBrowser.Result>) {
        var found: [String: NWEndpoint] = [:]
        for result in results {
            guard case .service(let name, _, _, _) = result.endpoint, found[name] == nil else { continue }
            found[name] = result.endpoint
        }
        endpoints = found
        onEvent?(.peers(found.keys.map { NearbyPeer(id: $0, name: $0) }))
    }

    /// The name other devices see: the Mac's computer name, or "iPad"/"iPhone" (iOS only shares the model).
    private static func deviceName() -> String {
        #if os(iOS)
        var name = UIDevice.current.name
        #else
        var name = (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac"
        #endif
        if name.isEmpty { name = "Hum" }
        // Bonjour allows 63 bytes.
        while name.utf8.count > 63 { name.removeLast() }
        return name
    }
}

/// A TCP connection to one device.
final class NetworkChannel: NearbyChannel {
    var onEvent: ((NearbyChannelEvent) -> Void)?
    private let connection: NWConnection
    private var isClosed = false

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch state {
                case .ready:
                    self.onEvent?(.ready)
                    self.receive()
                // "Waiting" means it can't get through right now; give up rather than hang.
                case .waiting, .failed, .cancelled: self.finish()
                default: break
                }
            }
        }
        connection.start(queue: .main)
    }

    func send(_ data: Data, completion: @escaping (Bool) -> Void) {
        guard !isClosed else { return completion(false) }
        let completion = MainQueueOnly(completion)
        connection.send(content: data, completion: .contentProcessed { error in
            MainActor.assumeIsolated { completion.value(error == nil) }
        })
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        onEvent = nil
        connection.cancel()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, !self.isClosed else { return }
                if let data, !data.isEmpty { self.onEvent?(.received(data)) }
                if self.isClosed { return }
                if isComplete || error != nil { self.finish() } else { self.receive() }
            }
        }
    }

    private func finish() {
        guard !isClosed else { return }
        let onEvent = self.onEvent
        close()
        onEvent?(.closed)
    }
}

/// A closure made on the main actor that the Network framework hands back on the main queue.
private nonisolated struct MainQueueOnly<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
