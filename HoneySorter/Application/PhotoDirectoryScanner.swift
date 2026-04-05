import Foundation

enum PhotoDirectoryScanner {
    nonisolated static func loadImages(from url: URL) async -> [PhotoFile] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        let sorted = contents
            .filter { supportedImageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        return sorted.enumerated().map { PhotoFile(url: $1, sortIndex: $0) }
    }
}
