import Foundation

struct Album: Identifiable, Sendable {
    nonisolated let id: UUID
    nonisolated let number: Int
    nonisolated let isReversed: Bool
    nonisolated let preservesClickOrder: Bool
    nonisolated let memberIndices: [Int]

    nonisolated init(
        id: UUID = UUID(),
        number: Int,
        isReversed: Bool,
        preservesClickOrder: Bool = false,
        memberIndices: [Int]
    ) {
        self.id = id
        self.number = number
        self.isReversed = isReversed
        self.preservesClickOrder = preservesClickOrder
        self.memberIndices = memberIndices
    }

    nonisolated init(
        id: UUID = UUID(),
        number: Int,
        startSortIndex: Int,
        endSortIndex: Int,
        isReversed: Bool
    ) {
        let lo = min(startSortIndex, endSortIndex)
        let hi = max(startSortIndex, endSortIndex)
        self.init(
            id: id,
            number: number,
            isReversed: isReversed,
            preservesClickOrder: false,
            memberIndices: Array(lo...hi)
        )
    }

    nonisolated func contains(_ photo: PhotoFile) -> Bool {
        memberIndices.contains(photo.sortIndex)
    }

    nonisolated var startSortIndex: Int { memberIndices.first ?? 0 }
    nonisolated var endSortIndex: Int { memberIndices.last ?? 0 }

    nonisolated var estimatedCount: Int {
        memberIndices.count
    }
}
