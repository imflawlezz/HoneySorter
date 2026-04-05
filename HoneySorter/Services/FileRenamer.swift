import Foundation

nonisolated let supportedImageExtensions: Set<String> = [
    "jpg","jpeg","png","heic","heif","tiff","tif","bmp","webp","gif"
]

private nonisolated let kManifestFilename = "honey_sorter_undo.json"

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

enum FileRenamer {

    nonisolated static func executeCopy(operations: [FileOperation]) throws {
        let fm = FileManager.default
        for op in operations {
            guard fm.fileExists(atPath: op.sourceURL.path) else {
                throw RenameError.sourceNotFound(op.sourceURL.lastPathComponent)
            }
        }
        for op in operations {
            let destDir = op.destinationURL.deletingLastPathComponent()
            if !fm.fileExists(atPath: destDir.path) {
                do { try fm.createDirectory(at: destDir, withIntermediateDirectories: true) }
                catch { throw RenameError.folderCreationFailed(destDir.lastPathComponent, error) }
            }
            do { try fm.copyItem(at: op.sourceURL, to: op.destinationURL) }
            catch { throw RenameError.copyFailed(from: op.sourceURL.lastPathComponent, to: op.destinationURL.lastPathComponent, underlying: error) }
        }
    }

    nonisolated static func executeRename(in sourceDir: URL, operations: [FileOperation]) throws {
        let fm = FileManager.default

        for op in operations {
            guard fm.fileExists(atPath: op.sourceURL.path) else {
                throw RenameError.sourceNotFound(op.sourceURL.lastPathComponent)
            }
        }

        var createdFolders: [String] = []
        let uniqueDirs = Set(operations.map { $0.destinationURL.deletingLastPathComponent().path })
        for dirPath in uniqueDirs {
            let dirURL = URL(fileURLWithPath: dirPath)
            if dirURL != sourceDir && !fm.fileExists(atPath: dirPath) {
                do { try fm.createDirectory(at: dirURL, withIntermediateDirectories: true) }
                catch { throw RenameError.folderCreationFailed(dirURL.lastPathComponent, error) }
                let rel = dirPath.replacingOccurrences(of: sourceDir.path + "/", with: "")
                createdFolders.append(rel)
            }
        }

        let entries = operations.map { op in
            ManifestEntry(
                originalPath: op.sourceURL.lastPathComponent,
                newPath: op.destinationURL.path.replacingOccurrences(of: sourceDir.path + "/", with: "")
            )
        }
        let manifest = RenameManifest(timestamp: Date(), sourceDirectory: sourceDir.path, entries: entries, createdFolders: createdFolders)
        try saveManifest(manifest, in: sourceDir)

        var tempMap: [(tempURL: URL, finalURL: URL)] = []
        for op in operations {
            let ext = op.sourceURL.pathExtension
            let tempName = "honey_tmp_\(UUID().uuidString)" + (ext.isEmpty ? "" : ".\(ext)")
            let tempURL = sourceDir.appendingPathComponent(tempName)
            do { try fm.moveItem(at: op.sourceURL, to: tempURL) }
            catch { throw RenameError.renameFailed(from: op.sourceURL.lastPathComponent, to: tempName, underlying: error) }
            tempMap.append((tempURL: tempURL, finalURL: op.destinationURL))
        }

        for entry in tempMap {
            do { try fm.moveItem(at: entry.tempURL, to: entry.finalURL) }
            catch { throw RenameError.renameFailed(from: entry.tempURL.lastPathComponent, to: entry.finalURL.lastPathComponent, underlying: error) }
        }
    }

    nonisolated static func undoRename(in directory: URL) throws {
        let fm = FileManager.default
        let manifestURL = directory.appendingPathComponent(kManifestFilename)
        guard fm.fileExists(atPath: manifestURL.path) else { throw RenameError.undoManifestNotFound }

        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest: RenameManifest
        do { manifest = try decoder.decode(RenameManifest.self, from: data) }
        catch { throw RenameError.undoManifestCorrupted }

        let srcDir = URL(fileURLWithPath: manifest.sourceDirectory)

        var tempMap: [(tempURL: URL, originalURL: URL)] = []
        for entry in manifest.entries {
            let currentURL = srcDir.appendingPathComponent(entry.newPath)
            guard fm.fileExists(atPath: currentURL.path) else { throw RenameError.sourceNotFound(entry.newPath) }
            let ext = currentURL.pathExtension
            let tempName = "honey_tmp_\(UUID().uuidString)" + (ext.isEmpty ? "" : ".\(ext)")
            let tempURL = srcDir.appendingPathComponent(tempName)
            do { try fm.moveItem(at: currentURL, to: tempURL) }
            catch { throw RenameError.renameFailed(from: entry.newPath, to: tempName, underlying: error) }
            tempMap.append((tempURL: tempURL, originalURL: srcDir.appendingPathComponent(entry.originalPath)))
        }

        for entry in tempMap {
            do { try fm.moveItem(at: entry.tempURL, to: entry.originalURL) }
            catch { throw RenameError.renameFailed(from: entry.tempURL.lastPathComponent, to: entry.originalURL.lastPathComponent, underlying: error) }
        }

        for folder in manifest.createdFolders.reversed() {
            let folderURL = srcDir.appendingPathComponent(folder)
            if let contents = try? fm.contentsOfDirectory(atPath: folderURL.path), contents.isEmpty {
                try? fm.removeItem(at: folderURL)
            }
        }
        try? fm.removeItem(at: manifestURL)
    }

    nonisolated static func hasManifest(in directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(kManifestFilename).path)
    }

    private nonisolated static func saveManifest(_ manifest: RenameManifest, in directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        try encoder.encode(manifest).write(to: directory.appendingPathComponent(kManifestFilename))
    }
}
