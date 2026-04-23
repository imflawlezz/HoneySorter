import Foundation
import ImageIO

enum VariantSetStrictness: String, CaseIterable, Identifiable {
    case strict = "Strict"
    case balanced = "Balanced"
    case loose = "Loose"

    var id: String { rawValue }
}

enum VariantSetService {
    struct Result: Sendable {
        let groups: [[URL]]
    }

    nonisolated static func findVariantSets(
        urls: [URL],
        strictness: VariantSetStrictness,
        maxConcurrent: Int = 4
    ) async -> Result {
        let entries = await hashesParallel(urls: urls, maxConcurrent: maxConcurrent)
        if entries.count < 2 { return Result(groups: []) }

        var unused = entries.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
        var groups: [[URL]] = []
        let threshold: Int
        switch strictness {
        case .strict: threshold = 4
        case .balanced: threshold = 8
        case .loose: threshold = 14
        }

        while let first = unused.first {
            unused.removeFirst()
            var group: [URL] = [first.url]
            var remaining: [Entry] = []
            remaining.reserveCapacity(unused.count)

            for e in unused {
                if hammingMin(first.hashes, e.hashes) <= threshold {
                    group.append(e.url)
                } else {
                    remaining.append(e)
                }
            }

            if group.count >= 2 {
                groups.append(group)
            }
            unused = remaining
        }

        return Result(groups: groups)
    }

    private struct Entry: Sendable {
        let url: URL
        let hashes: [UInt64]
    }

    nonisolated private static func hashesParallel(urls: [URL], maxConcurrent: Int) async -> [Entry] {
        await withTaskGroup(of: Entry?.self, returning: [Entry].self) { group in
            let limiter = ConcurrencyLimiter(maxConcurrent: maxConcurrent)
            for u in urls {
                group.addTask {
                    await limiter.withPermit {
                        guard let h = hashes64(url: u) else { return nil }
                        return Entry(url: u, hashes: h)
                    }
                }
            }
            var out: [Entry] = []
            for await e in group {
                if let e { out.append(e) }
            }
            return out
        }
    }

    nonisolated private static func hashes64(url: URL) -> [UInt64]? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldAllowFloat: false,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 96,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            return nil
        }

        let crops: [CGRect] = [
            CGRect(x: 0, y: 0, width: 1, height: 1),
            CGRect(x: 0.08, y: 0.08, width: 0.84, height: 0.84),
            CGRect(x: 0.18, y: 0.18, width: 0.64, height: 0.64),
        ]
        let hashes = crops.compactMap { aHash64(image: image, normalizedCrop: $0) }
        return hashes.isEmpty ? nil : hashes
    }

    nonisolated private static func aHash64(image: CGImage, normalizedCrop: CGRect) -> UInt64? {
        let width = 8
        let height = 8
        let bytesPerRow = width
        var pixels = [UInt8](repeating: 0, count: width * height)

        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .low

        let iw = CGFloat(image.width)
        let ih = CGFloat(image.height)
        let crop = CGRect(
            x: normalizedCrop.origin.x * iw,
            y: normalizedCrop.origin.y * ih,
            width: normalizedCrop.size.width * iw,
            height: normalizedCrop.size.height * ih
        )

        guard let cropped = image.cropping(to: crop.integral), cropped.width > 0, cropped.height > 0 else {
            return nil
        }

        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))

        let sum = pixels.reduce(0) { $0 + Int($1) }
        let avg = sum / pixels.count

        var hash: UInt64 = 0
        for (i, p) in pixels.enumerated() {
            if Int(p) >= avg {
                hash |= (UInt64(1) &<< UInt64(i))
            }
        }
        return hash
    }

    nonisolated private static func hammingMin(_ a: [UInt64], _ b: [UInt64]) -> Int {
        var best = Int.max
        for x in a {
            for y in b {
                let d = (x ^ y).nonzeroBitCount
                if d < best { best = d }
            }
        }
        return best == Int.max ? 0 : best
    }
}

private actor ConcurrencyLimiter {
    private let maxConcurrent: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    func acquire() async {
        if active < maxConcurrent {
            active += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
        active += 1
    }

    func release() {
        active -= 1
        if let w = waiters.first {
            waiters.removeFirst()
            w.resume()
        }
    }

    func withPermit<T>(_ work: @Sendable () -> T) async -> T {
        await acquire()
        defer { release() }
        return work()
    }
}

