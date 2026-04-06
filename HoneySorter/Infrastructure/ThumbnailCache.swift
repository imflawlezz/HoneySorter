import AppKit
import CryptoKit
import ImageIO

private actor ThumbnailInflightDeduplicator {
    static let shared = ThumbnailInflightDeduplicator()
    private var tasks = [String: Task<NSImage?, Never>]()

    func value(for key: String, work: @Sendable @escaping () async -> NSImage?) async -> NSImage? {
        if let existing = tasks[key] { return await existing.value }
        let task = Task { await work() }
        tasks[key] = task
        let result = await task.value
        tasks[key] = nil
        return result
    }
}

enum ThumbnailCache {
    nonisolated(unsafe) private static let memory: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 600
        return c
    }()

    private static let thumbnailsDirectory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let bid = Bundle.main.bundleIdentifier ?? "HoneySorter"
        let dir = base.appendingPathComponent("\(bid)/Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func image(for url: URL, maxPixelSize: CGFloat) async -> NSImage? {
        let capped = min(maxPixelSize, 512)
        let keyString = cacheKeyString(url: url, maxPixelSize: capped)
        if let cached = memory.object(forKey: keyString as NSString) { return cached }

        let diskFile = diskURL(for: keyString)
        if FileManager.default.fileExists(atPath: diskFile.path) {
            let fromDisk = await Task.detached(priority: .utility) {
                Self.loadJPEGThumbnail(from: diskFile, cacheKey: keyString)
            }.value
            if let fromDisk { return fromDisk }
            try? FileManager.default.removeItem(at: diskFile)
        }

        return await ThumbnailInflightDeduplicator.shared.value(for: keyString) {
            await Task.detached(priority: .utility) {
                await ThumbnailDecodeLimiter.shared.runSync {
                    Self.decodeAndCache(url: url, maxPixelSize: capped, cacheKey: keyString, diskFile: diskFile)
                }
            }.value
        }
    }

    private static func cacheKeyString(url: URL, maxPixelSize: CGFloat) -> String {
        let capped = min(maxPixelSize, 512)
        if let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
           let mod = vals.contentModificationDate,
           let size = vals.fileSize
        {
            return "\(url.path)|\(Int(capped))|\(mod.timeIntervalSinceReferenceDate)|\(size)"
        }
        return "\(url.path)|\(Int(capped))"
    }

    private static func diskURL(for cacheKey: String) -> URL {
        let digest = SHA256.hash(data: Data(cacheKey.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined() + ".jpg"
        return thumbnailsDirectory.appendingPathComponent(name)
    }

    nonisolated private static func loadJPEGThumbnail(from file: URL, cacheKey: String) -> NSImage? {
        guard let data = try? Data(contentsOf: file),
              let image = NSImage(data: data)
        else { return nil }
        memory.setObject(image, forKey: cacheKey as NSString)
        return image
    }

    nonisolated private static func writeJPEGThumbnail(_ image: NSImage, to file: URL) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
        else { return }
        let tmp = file.appendingPathExtension("tmp")
        do {
            try data.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: file.path) {
                try? FileManager.default.removeItem(at: file)
            }
            try FileManager.default.moveItem(at: tmp, to: file)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    nonisolated private static func decodeAndCache(
        url: URL,
        maxPixelSize: CGFloat,
        cacheKey: String,
        diskFile: URL
    ) -> NSImage? {
        let nsKey = cacheKey as NSString
        if let cached = memory.object(forKey: nsKey) { return cached }

        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldAllowFloat: false,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            return nil
        }

        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        )
        memory.setObject(image, forKey: nsKey)
        writeJPEGThumbnail(image, to: diskFile)
        return image
    }
}
