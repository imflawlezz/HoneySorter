import Foundation

struct Album: Identifiable, Sendable {
    nonisolated let id: UUID
    nonisolated let number: Int
    nonisolated let isReversed: Bool
    /// Indices into the `photos` array (sorted by `sortIndex`).
    /// Must be strictly increasing; reverse display is computed via `isReversed`.
    nonisolated let memberIndices: [Int]

    nonisolated init(
        id: UUID = UUID(),
        number: Int,
        isReversed: Bool,
        memberIndices: [Int]
    ) {
        self.id = id
        self.number = number
        self.isReversed = isReversed
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
