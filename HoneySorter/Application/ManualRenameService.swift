import Foundation

enum ManualRenameService {
    enum ValidationError: LocalizedError {
        case emptyName
        case sameAsCurrent
        case invalidCharacters

        var errorDescription: String? {
            switch self {
            case .emptyName: return "Enter a filename."
            case .sameAsCurrent: return "The new name is the same as the current filename."
            case .invalidCharacters: return "Filenames cannot contain `/`, `:`, or control characters."
            }
        }
    }

    static func buildOperation(photo: PhotoFile, basenameInput: String, in dir: URL) throws -> [FileOperation] {
        let trimmed = basenameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError.emptyName }

        let last = (trimmed as NSString).lastPathComponent
        guard !last.isEmpty, last != ".", last != ".." else { throw ValidationError.emptyName }

        let base = (last as NSString).deletingPathExtension
        guard !base.isEmpty else { throw ValidationError.emptyName }

        try validateFilenameForFilesystem(base)

        let finalName: String
        if photo.fileExtension.isEmpty {
            finalName = base
        } else {
            finalName = "\(base).\(photo.fileExtension)"
        }

        let dest = dir.appendingPathComponent(finalName)
        guard dest.lastPathComponent != photo.originalFilename else {
            throw ValidationError.sameAsCurrent
        }

        try validateFilenameForFilesystem(finalName)

        return [FileOperation(sourceURL: photo.url, destinationURL: dest)]
    }

    static func validateDestinationsDoNotCollide(operations: [FileOperation], in dir: URL) throws {
        let fm = FileManager.default
        let sourcePaths = Set(operations.map(\.sourceURL.path))
        for op in operations {
            let path = op.destinationURL.path
            guard fm.fileExists(atPath: path) else { continue }
            if sourcePaths.contains(path) { continue }
            throw RenameError.destinationExists(op.destinationURL.lastPathComponent)
        }
    }

    private static func validateFilenameForFilesystem(_ name: String) throws {
        if name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            throw ValidationError.invalidCharacters
        }
        let blocked = CharacterSet(charactersIn: "/:\u{0000}")
        if name.unicodeScalars.contains(where: { blocked.contains($0) }) {
            throw ValidationError.invalidCharacters
        }
    }
}
