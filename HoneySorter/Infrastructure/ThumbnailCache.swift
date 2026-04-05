import AppKit
import ImageIO

enum ThumbnailCache {
    private static let memory = NSCache<NSString, NSImage>()

    static func image(for url: URL, maxPixelSize: CGFloat) async -> NSImage? {
        let key = cacheKey(url: url, maxPixelSize: maxPixelSize)
        if let cached = memory.object(forKey: key) { return cached }
        let cgImage: CGImage? = await Task.detached(priority: .utility) {
            Self.createThumbnail(for: url, maxSize: maxPixelSize)
        }.value
        guard let cgImage else { return nil }
        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        )
        memory.setObject(image, forKey: key)
        return image
    }

    private static func cacheKey(url: URL, maxPixelSize: CGFloat) -> NSString {
        "\(url.path)|\(Int(maxPixelSize))" as NSString
    }

    nonisolated private static func createThumbnail(for url: URL, maxSize: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
