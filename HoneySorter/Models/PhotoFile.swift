import Foundation

struct PhotoFile: Identifiable, Sendable {
    nonisolated let id = UUID()
    nonisolated let url: URL
    nonisolated let originalFilename: String
    nonisolated let fileExtension: String
    nonisolated let sortIndex: Int

    nonisolated init(url: URL, sortIndex: Int) {
        self.url = url
        self.originalFilename = url.lastPathComponent
        self.fileExtension = url.pathExtension.lowercased()
        self.sortIndex = sortIndex
    }
}

struct Album: Identifiable, Sendable {
    nonisolated let id = UUID()
    nonisolated let number: Int
    nonisolated let startSortIndex: Int
    nonisolated let endSortIndex: Int

    nonisolated func contains(_ photo: PhotoFile) -> Bool {
        photo.sortIndex >= startSortIndex && photo.sortIndex <= endSortIndex
    }

    nonisolated var estimatedCount: Int {
        endSortIndex - startSortIndex + 1
    }
}
