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
