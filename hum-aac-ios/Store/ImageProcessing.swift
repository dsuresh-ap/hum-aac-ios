// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
import CoreTransferable
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Prepares photos for tiles: downscale to at most 1024 px on the long edge, fix rotation, and store as
/// JPEG. JPEG (not HEIC) keeps `.hum` and `.obz` exports readable by every other tool.
nonisolated enum ImageProcessing {
    static let maxPixelSize = 1024

    /// Photos, symbols (PNG with transparency) and SVG symbols all end up as a JPEG on white.
    static func tileImageData(from data: Data) -> Data? {
        if let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,  // applies EXIF orientation
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return jpegData(onWhite(image))
        }
        // ImageIO doesn't read SVG (Mulberry symbols); the platform image classes can.
        return rasterizeSVG(data).flatMap { jpegData($0) }
    }

    /// For pictures from an imported file. A small, upright JPEG without location data (what Hum itself
    /// exports) is kept byte for byte, so round trips don't lose quality. Anything else (big photos,
    /// transparent PNGs, HEIC, SVG on macOS) is processed like a new photo. Nil when it can't be read
    /// here, e.g. SVG on iOS (see `ImportService.renderImportedSVGs`) or a file that isn't a picture.
    static func normalizedImportImage(_ data: Data) -> Data? {
        if let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
           CGImageSourceGetType(source) as String? == UTType.jpeg.identifier,
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            let width = properties[kCGImagePropertyPixelWidth] as? Int ?? .max
            let height = properties[kCGImagePropertyPixelHeight] as? Int ?? .max
            let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
            if max(width, height) <= maxPixelSize, orientation == 1, properties[kCGImagePropertyGPSDictionary] == nil {
                return data
            }
        }
        return tileImageData(from: data)
    }

    static func isSVG(_ data: Data) -> Bool {
        data.prefix(512).range(of: Data("<svg".utf8)) != nil
    }

    /// JPEG has no transparency: without this, a symbol's see-through background turns black.
    static func onWhite(_ image: CGImage) -> CGImage {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return image
        default: break
        }
        return draw(width: image.width, height: image.height) { context, rect in context.draw(image, in: rect) } ?? image
    }

    /// Renders SVG data on white, at most `maxPixelSize` on the long edge. Nil if it isn't an image.
    static func rasterizeSVG(_ data: Data) -> CGImage? {
        guard isSVG(data) else { return nil }
        #if canImport(UIKit)
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let size = image.size
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let size = image.size
        #endif
        let scale = Double(maxPixelSize) / max(size.width, size.height)
        let width = Int(size.width * scale), height = Int(size.height * scale)
        return draw(width: width, height: height) { context, rect in
            #if canImport(UIKit)
            UIGraphicsPushContext(context)
            // UIKit draws top-down; CGContext is bottom-up.
            context.translateBy(x: 0, y: rect.height)
            context.scaleBy(x: 1, y: -1)
            image.draw(in: rect)
            UIGraphicsPopContext()
            #elseif canImport(AppKit)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            image.draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
            #endif
        }
    }

    private static func draw(width: Int, height: Int, _ body: (CGContext, CGRect) -> Void) -> CGImage? {
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        body(context, rect)
        return context.makeImage()
    }

    static func jpegData(_ image: CGImage, quality: Double = 0.8) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        // No metadata is copied: no location or camera info leaves the device in exports.
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}

/// Any picture from a drop or the clipboard (photos, PNG symbols, SVG), as raw bytes for `tileImageData`.
nonisolated struct ImagePayload: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { ImagePayload(data: $0) }
    }
}
