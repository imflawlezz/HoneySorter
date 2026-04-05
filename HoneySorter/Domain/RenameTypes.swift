import Foundation

nonisolated let supportedImageExtensions: Set<String> = [
    "jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "bmp", "webp", "gif",
]

struct FileOperation: Sendable {
    let sourceURL: URL
    let destinationURL: URL
}

struct ManifestEntry: Sendable {
    nonisolated let originalPath: String
    nonisolated let newPath: String

    private enum CodingKeys: String, CodingKey {
        case originalPath, newPath
    }
}

extension ManifestEntry: Codable {
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        originalPath = try c.decode(String.self, forKey: .originalPath)
        newPath = try c.decode(String.self, forKey: .newPath)
    }
    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(originalPath, forKey: .originalPath)
        try c.encode(newPath, forKey: .newPath)
    }
}

struct RenameManifest: Sendable {
    nonisolated let timestamp: Date
    nonisolated let sourceDirectory: String
    nonisolated let entries: [ManifestEntry]
    nonisolated let createdFolders: [String]

    private enum CodingKeys: String, CodingKey {
        case timestamp, sourceDirectory, entries, createdFolders
    }
}

extension RenameManifest: Codable {
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        sourceDirectory = try c.decode(String.self, forKey: .sourceDirectory)
        entries = try c.decode([ManifestEntry].self, forKey: .entries)
        createdFolders = try c.decode([String].self, forKey: .createdFolders)
    }
    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(sourceDirectory, forKey: .sourceDirectory)
        try c.encode(entries, forKey: .entries)
        try c.encode(createdFolders, forKey: .createdFolders)
    }
}

enum RenameError: LocalizedError {
    case sourceNotFound(String)
    case destinationExists(String)
    case renameFailed(from: String, to: String, underlying: Error)
    case copyFailed(from: String, to: String, underlying: Error)
    case folderCreationFailed(String, Error)
    case undoManifestNotFound
    case undoManifestCorrupted
    case noDirectory

    nonisolated var errorDescription: String? {
        switch self {
        case .sourceNotFound(let n): return "Source file not found: \(n)"
        case .destinationExists(let n): return "Destination already exists: \(n)"
        case .renameFailed(let f, let t, let e): return "Rename failed '\(f)' → '\(t)': \(e.localizedDescription)"
        case .copyFailed(let f, let t, let e): return "Copy failed '\(f)' → '\(t)': \(e.localizedDescription)"
        case .folderCreationFailed(let p, let e): return "Folder creation failed '\(p)': \(e.localizedDescription)"
        case .undoManifestNotFound: return "No previous operation found to revert."
        case .undoManifestCorrupted: return "The revert record is damaged."
        case .noDirectory: return "No folder selected."
        }
    }
}
