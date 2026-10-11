// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Prepares photos for tiles: downscale to at most 1024 px on the long edge, fix rotation, and store as
/// JPEG. JPEG (not HEIC) keeps `.hum` and `.obz` exports readable by every other tool.
nonisolated enum ImageProcessing {
    static let maxPixelSize = 1024

    static func tileImageData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,  // applies EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return jpegData(image)
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
