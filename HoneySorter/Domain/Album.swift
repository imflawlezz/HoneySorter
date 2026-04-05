import Foundation

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
