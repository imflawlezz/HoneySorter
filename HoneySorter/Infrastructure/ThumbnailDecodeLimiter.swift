import Foundation

actor ThumbnailDecodeLimiter {
    static let shared = ThumbnailDecodeLimiter()

    private let maxConcurrent = 8
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func runSync<T: Sendable>(_ work: @Sendable () -> T) async -> T {
        await acquire()
        defer { release() }
        return work()
    }

    private func acquire() async {
        if active < maxConcurrent {
            active += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
        active += 1
    }

    private func release() {
        active -= 1
        if let w = waiters.first {
            waiters.removeFirst()
            w.resume()
        }
    }
}
