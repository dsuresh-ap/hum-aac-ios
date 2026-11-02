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
/// that blocks every outside load. The SVG is shown as an `<img>`, never as part of the page: an SVG
/// drawn as an image runs nothing (no meta refresh) and loads nothing. On top of that, the view cancels
/// every navigation except to the blank page, so a picture can't reach the network.
@MainActor
enum SVGRenderer {
    /// How long to wait for a page to load.
    static let loadTimeout: Duration = .seconds(30)

    /// Navigations the web views cancelled (for tests).
    private(set) static var blockedNavigations: [URL] = []

    /// A square picture of the SVG on white, or nil.
    static func render(_ svg: Data, points: CGFloat = 512) async -> CGImage? {
        #if canImport(UIKit) && canImport(WebKit)
        guard let raw = String(data: svg, encoding: .utf8), raw.contains("<svg"), isSVGDocument(svg) else { return nil }
        let image = Data(withNamespace(withViewBox(raw)).utf8).base64EncodedString()
        // `object-fit: contain` scales the picture to fit and centers it, like an inline SVG's viewBox.
        let html = """
            <!doctype html><html><head>
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:">
            <meta name="viewport" content="width=\(Int(points)), initial-scale=1">
            <style>html,body{margin:0;padding:0;background:#fff;width:100%;height:100%;overflow:hidden}
            img{display:block;width:100%;height:100%;object-fit:contain}</style>
            </head><body><img alt="" src="data:image/svg+xml;base64,\(image)"></body></html>
            """
        return await snapshot(html, points: points)
        #else
        return nil
        #endif
    }

    #if canImport(UIKit) && canImport(WebKit)
    /// Loads `html` in a web view and takes a square picture of it.
    static func snapshot(_ html: String, points: CGFloat) async -> CGImage? {
        let view = takeView(points: points)
        defer { putBack(view) }
        let loader = Loader()
        view.navigationDelegate = loader
        guard await loader.load(html, in: view, timeout: loadTimeout) else { return nil }
        let snapshot = WKSnapshotConfiguration()
        snapshot.rect = view.bounds
        guard let image = try? await view.takeSnapshot(configuration: snapshot) else { return nil }
        return image.cgImage
    }

    /// Web views are slow to start (each one starts a web process), so a big import reuses a few.
    private static var idle: [WKWebView] = []
    /// Keeps cancelling navigations while a view waits in `idle` (`navigationDelegate` is weak).
    private static let idleGuard = Loader()

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

    /// A page can schedule a navigation for later (a meta refresh): stop it and clear the page, still
    /// under a delegate that cancels navigations.
    private static func putBack(_ view: WKWebView) {
        view.navigationDelegate = idleGuard
        view.stopLoading()
        view.loadHTMLString("", baseURL: nil)
        if idle.count < 4 { idle.append(view) }
    }
    #endif

    /// An SVG file is XML with an `svg` root. WebKit draws nothing for anything else shown as an image.
    nonisolated static func isSVGDocument(_ data: Data) -> Bool {
        final class Root: NSObject, XMLParserDelegate {
            var name: String?
            func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                        qualifiedName: String?, attributes: [String: String] = [:]) {
                if name == nil { name = elementName }
            }
        }
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        let root = Root()
        parser.delegate = root
        return parser.parse() && root.name == "svg"
    }

    /// An SVG shown as an image must say it's SVG; inline in a page it didn't have to.
    nonisolated static func withNamespace(_ svg: String) -> String {
        guard let open = svg.range(of: #"<svg\b[^>]*>"#, options: .regularExpression),
              !svg[open].contains("xmlns=") else { return svg }
        return svg.replacingCharacters(in: open, with: svg[open].replacingOccurrences(
            of: "<svg", with: "<svg xmlns=\"http://www.w3.org/2000/svg\"", options: .anchored))
    }

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
    /// Waits for the page to finish loading (or fail). Gives up after `timeout`, so a stuck web view
    /// can't stall a whole import. A picture that can't load fails at once; the wait is for the first
    /// web process, which can take a while on an older iPad or a busy device.
    ///
    /// Allows only navigations to the blank page (what `loadHTMLString` with no base URL loads) and
    /// cancels every other one.
    private final class Loader: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Bool, Never>?
        /// This page's load. A reused view may still be clearing its last page, which ends separately.
        private var navigation: WKNavigation?

        func load(_ html: String, in view: WKWebView, timeout: Duration) async -> Bool {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                navigation = view.loadHTMLString(html, baseURL: nil)
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: timeout)
                    self?.finish(false)
                }
            }
        }

        private func finish(_ ok: Bool) {
            continuation?.resume(returning: ok)
            continuation = nil
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            if url?.absoluteString == "about:blank", navigationAction.targetFrame?.isMainFrame == true {
                decisionHandler(.allow)
            } else {
                if let url { SVGRenderer.blockedNavigations.append(url) }
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if navigation === self.navigation { finish(true) }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if navigation === self.navigation { finish(false) }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if navigation === self.navigation { finish(false) }
        }
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
