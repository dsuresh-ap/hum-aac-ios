// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import CoreGraphics
#if canImport(UIKit) && canImport(WebKit)
import UIKit
import WebKit
#endif

/// Draws SVG symbols (Mulberry) on iOS, where `UIImage` can't read SVG. macOS doesn't need this:
/// `NSImage` reads SVG directly (see `ImageProcessing.rasterizeSVG`).
///
/// Uses an off-screen WebKit view with JavaScript off, no stored website data, and a content policy
/// that blocks every outside load, so an SVG can't run code or reach the network.
@MainActor
enum SVGRenderer {
    /// A square picture of the SVG on white, or nil.
    static func render(_ svg: Data, points: CGFloat = 512) async -> CGImage? {
        #if canImport(UIKit) && canImport(WebKit)
        guard let raw = String(data: svg, encoding: .utf8), raw.contains("<svg") else { return nil }
        let text = withViewBox(raw)
        let view = takeView(points: points)
        defer { putBack(view) }
        let html = """
            <!doctype html><html><head>
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:">
            <meta name="viewport" content="width=\(Int(points)), initial-scale=1">
            <style>html,body{margin:0;padding:0;background:#fff;width:100%;height:100%;overflow:hidden}
            svg{display:block;width:100%;height:100%}</style>
            </head><body>\(text)</body></html>
            """
        let loader = Loader()
        view.navigationDelegate = loader
        defer { view.navigationDelegate = nil }
        guard await loader.load(html, in: view) else { return nil }
        let snapshot = WKSnapshotConfiguration()
        snapshot.rect = view.bounds
        guard let image = try? await view.takeSnapshot(configuration: snapshot) else { return nil }
        return image.cgImage
        #else
        return nil
        #endif
    }

    #if canImport(UIKit) && canImport(WebKit)
    /// Web views are slow to start (each one starts a web process), so a big import reuses a few.
    private static var idle: [WKWebView] = []

    private static func takeView(points: CGFloat) -> WKWebView {
        let frame = CGRect(x: 0, y: 0, width: points, height: points)
        if let view = idle.popLast() {
            view.frame = frame
            return view
        }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: frame, configuration: config)
        view.isOpaque = true
        view.backgroundColor = .white
        view.scrollView.contentInsetAdjustmentBehavior = .never
        return view
    }

    private static func putBack(_ view: WKWebView) {
        if idle.count < 4 { idle.append(view) }
    }
    #endif

    /// An SVG with only `width`/`height` doesn't scale to fill the page; give it a matching `viewBox`.
    nonisolated static func withViewBox(_ svg: String) -> String {
        guard let open = svg.range(of: #"<svg\b[^>]*>"#, options: .regularExpression) else { return svg }
        let tag = String(svg[open])
        guard !tag.contains("viewBox") else { return svg }
        func number(_ name: String) -> String? {
            guard let match = tag.range(of: name + #"\s*=\s*["']\s*([0-9.]+)"#, options: .regularExpression) else { return nil }
            return String(tag[match]).components(separatedBy: CharacterSet(charactersIn: "\"'")).dropFirst().first?
                .trimmingCharacters(in: .whitespaces)
        }
        guard let width = number("width"), let height = number("height") else { return svg }
        let fixed = tag.replacingOccurrences(of: "<svg", with: "<svg viewBox=\"0 0 \(width) \(height)\"", options: .anchored)
        return svg.replacingCharacters(in: open, with: fixed)
    }

    #if canImport(UIKit) && canImport(WebKit)
    /// Waits for the page to finish loading (or fail). Gives up after 10 seconds, so one bad picture
    /// can't stall a whole import.
    private final class Loader: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Bool, Never>?

        func load(_ html: String, in view: WKWebView) async -> Bool {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                view.loadHTMLString(html, baseURL: nil)
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(10))
                    self?.finish(false)
                }
            }
        }

        private func finish(_ ok: Bool) {
            continuation?.resume(returning: ok)
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(true) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(false) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(false) }
    }
    #endif
}

extension ImageProcessing {
    /// `tileImageData`, plus SVG on iOS (drawn by WebKit). Use this for downloaded symbols.
    @MainActor
    static func tileImageDataAllowingSVG(from data: Data) async -> Data? {
        if let ready = tileImageData(from: data) { return ready }
        // The snapshot is at screen scale (up to 3×): run it through the normal downscale.
        guard let image = await SVGRenderer.render(data), let full = jpegData(onWhite(image)) else { return nil }
        return tileImageData(from: full)
    }
}
