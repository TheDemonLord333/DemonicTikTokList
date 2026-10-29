//
//  ImageProcessing.swift
//  DemonicTikTokList
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Verkleinert Bilddaten speicherschonend über ImageIO.
nonisolated enum ImageProcessing {
    static let defaultMaxPixelSize = 512

    /// Prüft, ob die Daten ein lesbares Bild sind, und liefert ein verkleinertes JPEG.
    static func downsampledJPEG(from data: Data, maxPixelSize: Int = defaultMaxPixelSize, quality: Double = 0.85) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              CGImageSourceGetCount(source) > 0 else {
            return nil
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        let destinationOptions = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, destinationOptions)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    static func downsampledJPEGInBackground(from data: Data) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            ImageProcessing.downsampledJPEG(from: data)
        }.value
    }
}
