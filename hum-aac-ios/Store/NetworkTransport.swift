// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Network
#if os(iOS)
import UIKit
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
        parameters.prohibitedInterfaceTypes = [.cellular]
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
                // Only devices on this local network or Wi-Fi link: never an address from the internet
                // (a device with a public IPv6 address could otherwise be reached from anywhere).
                guard let self, let listener, self.listener === listener,
                      Self.isLocal(connection.endpoint) else { return connection.cancel() }
                self.onEvent?(.incoming(NetworkChannel(connection, incoming: true)))
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

    /// The name other devices see: the kind of device and a number picked for this screen, like
    /// "iPad 472". Not the device's own name: a Mac's name is often its owner's, and everyone on the
    /// network can read it.
    private static func deviceName() -> String {
        #if os(iOS)
        let kind = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #else
        let kind = "Mac"
        #endif
        return "\(kind) \(Int.random(in: 100...999))"
    }

    /// Link-local, private (RFC 1918), unique-local IPv6 or loopback: addresses that can't come from the
    /// internet. Peer-to-peer Wi-Fi between Apple devices uses link-local IPv6.
    nonisolated static func isLocal(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address):
            let b = [UInt8](address.rawValue)
            guard b.count == 4 else { return false }
            return b[0] == 10 || b[0] == 127 || (b[0] == 172 && b[1] & 0xF0 == 16) || (b[0] == 192 && b[1] == 168)
                || (b[0] == 169 && b[1] == 254)
        case .ipv6(let address):
            if address.isLoopback || address.isLinkLocal { return true }
            if let mapped = address.asIPv4 { return isLocal(.hostPort(host: .ipv4(mapped), port: 0)) }
            let first = address.rawValue.first ?? 0
            return first & 0xFE == 0xFC  // fc00::/7
        default:
            return false
        }
    }

    /// VPN and other tunnels: their addresses can look local (10.x, fd00::) but the device at the other
    /// end can be anywhere, so the receiver doesn't take connections through them.
    nonisolated static func isTunnel(interfaceName name: String) -> Bool {
        ["utun", "ipsec", "ppp", "tun", "tap", "gif", "stf"].contains { name.hasPrefix($0) }
    }
}

/// A TCP connection to one device.
final class NetworkChannel: NearbyChannel {
    var onEvent: ((NearbyChannelEvent) -> Void)?
    private let connection: NWConnection
    /// A connection the listener accepted (checked for tunnels once it's ready).
    private let incoming: Bool
    private var isClosed = false

    init(_ connection: NWConnection, incoming: Bool = false) {
        self.connection = connection
        self.incoming = incoming
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch state {
                case .ready:
                    // The interface this connection actually uses comes first.
                    if self.incoming, let interface = self.connection.currentPath?.availableInterfaces.first,
                       NetworkTransport.isTunnel(interfaceName: interface.name) {
                        return self.finish()
                    }
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
