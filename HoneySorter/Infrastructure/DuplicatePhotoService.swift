import CryptoKit
import Foundation

enum DuplicatePhotoService {
    struct Result: Sendable {
        let groups: [[URL]]

        var duplicateFileCount: Int {
            groups.reduce(0) { $0 + max(0, $1.count - 1) }
        }

        var urlsToTrash: [URL] {
            groups.flatMap { Array($0.dropFirst()) }
        }
    }

    nonisolated static func findExactDuplicates(urls: [URL], maxConcurrentHashes: Int = 4) async -> Result {
        let sizes = await fileSizesParallel(urls: urls, maxConcurrent: maxConcurrentHashes)
        let bySize = Dictionary(grouping: sizes.compactMap { $0 }, by: \.size)
        let candidateURLs = bySize.values
            .filter { $0.count >= 2 }
            .flatMap { $0.map(\.url) }

        if candidateURLs.isEmpty { return Result(groups: []) }

        let hashes = await sha256Parallel(urls: candidateURLs, maxConcurrent: maxConcurrentHashes)
        let byHash = Dictionary(grouping: hashes, by: \.hashHex)
        let groups: [[URL]] = byHash.values
            .filter { $0.count >= 2 }
            .map { entries in
                entries.map(\.url).sorted { $0.lastPathComponent < $1.lastPathComponent }
            }
            .sorted { $0.first?.lastPathComponent ?? "" < $1.first?.lastPathComponent ?? "" }

        return Result(groups: groups)
    }

    private struct URLSize: Sendable {
        let url: URL
        let size: Int
    }

    private struct URLHash: Sendable {
        let url: URL
        let hashHex: String
    }

    nonisolated private static func fileSizesParallel(urls: [URL], maxConcurrent: Int) async -> [URLSize?] {
        await withTaskGroup(of: URLSize?.self, returning: [URLSize?].self) { group in
            let limiter = ConcurrencyLimiter(maxConcurrent: maxConcurrent)

            for u in urls {
                group.addTask {
                    await limiter.withPermit {
                        let size = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                        return URLSize(url: u, size: size)
                    }
                }
            }

            var out: [URLSize?] = []
            out.reserveCapacity(urls.count)
            for await r in group { out.append(r) }
            return out
        }
    }

    nonisolated private static func sha256Parallel(urls: [URL], maxConcurrent: Int) async -> [URLHash] {
        await withTaskGroup(of: URLHash?.self, returning: [URLHash].self) { group in
            let limiter = ConcurrencyLimiter(maxConcurrent: maxConcurrent)

            for u in urls {
                group.addTask {
                    await limiter.withPermit {
                        guard let hex = sha256HexStream(url: u) else { return nil }
                        return URLHash(url: u, hashHex: hex)
                    }
                }
            }

            var out: [URLHash] = []
            for await r in group {
                if let r { out.append(r) }
            }
            return out
        }
    }

    nonisolated private static func sha256HexStream(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = try? handle.read(upToCount: 1024 * 1024)
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
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
