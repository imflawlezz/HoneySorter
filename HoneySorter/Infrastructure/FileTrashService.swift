import Foundation

enum FileTrashService {
    nonisolated static func moveToTrash(urls: [URL]) throws -> Int {
        let fm = FileManager.default
        var trashed = 0
        for u in urls {
            var resultingItemURL: NSURL?
            do {
                try fm.trashItem(at: u, resultingItemURL: &resultingItemURL)
                trashed += 1
            } catch {
                throw error
            }
        }
        return trashed
    }
}

