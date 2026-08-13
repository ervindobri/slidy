import CoreGraphics
import Foundation
import ImageIO

/// Decodes files straight to a display-sized `CGImage`.
///
/// Full-resolution photos are far larger than any screen, so decoding at the
/// container's pixel size keeps a long strip of pages cheap to hold in memory.
enum ImageDecoder {

    /// Largest edge we ever decode to, regardless of container size.
    private static let ceiling: CGFloat = 4096

    static func decode(url: URL, maxPixelSize: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let target = max(64, min(maxPixelSize.rounded(), ceiling))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: target
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Serialises decoding across every page.
///
/// Skipping quickly through a folder starts a decode for each page it touches,
/// and each one holds a full display-sized bitmap while it runs — a dozen at
/// once is hundreds of megabytes of peak memory for images nobody is looking at
/// any more. Going through one actor keeps the peak to a single decode, and
/// anything whose page has already been skipped past is dropped instead of run.
actor ImageDecodeQueue {
    static let shared = ImageDecodeQueue()

    func decode(url: URL, maxPixelSize: CGFloat) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        return ImageDecoder.decode(url: url, maxPixelSize: maxPixelSize)
    }
}
