import Foundation

struct Album: Identifiable, Sendable {
    nonisolated let id: UUID
    nonisolated let number: Int
    nonisolated let startSortIndex: Int
    nonisolated let endSortIndex: Int
    nonisolated let isReversed: Bool
    nonisolated let memberPaths: [String]?

    nonisolated init(
        id: UUID = UUID(),
        number: Int,
        startSortIndex: Int,
        endSortIndex: Int,
        isReversed: Bool,
        memberPaths: [String]? = nil
    ) {
        self.id = id
        self.number = number
        self.startSortIndex = startSortIndex
        self.endSortIndex = endSortIndex
        self.isReversed = isReversed
        self.memberPaths = memberPaths
    }

    nonisolated func contains(_ photo: PhotoFile) -> Bool {
        if let memberPaths {
            return Set(memberPaths).contains(photo.url.path)
        }
        return photo.sortIndex >= startSortIndex && photo.sortIndex <= endSortIndex
    }

    nonisolated var estimatedCount: Int {
        if let memberPaths { return memberPaths.count }
        return endSortIndex - startSortIndex + 1
    }
}
