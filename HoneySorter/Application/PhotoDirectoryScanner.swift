import Foundation

enum PhotoDirectoryScanner {

    nonisolated static func loadImages(from url: URL, ordering: PhotoOrdering = .filename) async -> [PhotoFile] {
        await Task.detached(priority: .userInitiated) {
            await Self.loadImagesInner(from: url, ordering: ordering)
        }.value
    }

    nonisolated private static func loadImagesInner(from url: URL, ordering: PhotoOrdering) async -> [PhotoFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .creationDateKey, .contentModificationDateKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }

        let images = contents.filter { supportedImageExtensions.contains($0.pathExtension.lowercased()) }

        let sorted: [URL]
        switch ordering {
        case .filename:
            sorted = images.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        case .creationDate:
            let pairs = await resourceDatesParallel(images, key: .creationDateKey)
            sorted = pairs.sorted {
                if $0.date != $1.date { return $0.date < $1.date }
                return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }.map(\.url)

        case .modificationDate:
            let pairs = await resourceDatesParallel(images, key: .contentModificationDateKey)
            sorted = pairs.sorted {
                if $0.date != $1.date { return $0.date < $1.date }
                return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }.map(\.url)
        }

        return sorted.enumerated().map { PhotoFile(url: $1, sortIndex: $0) }
    }

    private struct URLDatePair: Sendable {
        let url: URL
        let date: Date
    }

    nonisolated private static func resourceDatesParallel(_ urls: [URL], key: URLResourceKey) async -> [URLDatePair] {
        await withTaskGroup(of: URLDatePair.self, returning: [URLDatePair].self) { group in
            for u in urls {
                group.addTask {
                    let date: Date
                    switch key {
                    case .creationDateKey:
                        date = (try? u.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    case .contentModificationDateKey:
                        date = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    default:
                        date = .distantPast
                    }
                    return URLDatePair(url: u, date: date)
                }
            }
            var out: [URLDatePair] = []
            out.reserveCapacity(urls.count)
            for await pair in group {
                out.append(pair)
            }
            return out
        }
    }
}
