import SwiftUI
import AppKit

enum GridThumbnailSize: String, CaseIterable, Identifiable {
    case small, medium, large, extraLarge
    var id: String { rawValue }
    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }
    var cellSide: CGFloat {
        switch self {
        case .small: return 96
        case .medium: return 120
        case .large: return 152
        case .extraLarge: return 200
        }
    }
    var thumbnailPixelSize: CGFloat { cellSide * 2 }
}

enum SelectionState: Equatable {
    case idle
    case startSelected(UUID)
}

enum Separator: String, CaseIterable, Identifiable {
    case underscore = "_"
    case dash = "-"
    case dot = "."
    var id: String { rawValue }
    var label: String {
        switch self {
        case .underscore: return "Underscore (_)"
        case .dash: return "Dash (-)"
        case .dot: return "Dot (.)"
        }
    }
}

private enum ManualRenameValidationError: LocalizedError {
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

@Observable
class PhotoSorterViewModel {

    var directoryURL: URL?
    private var isAccessingSecurityScope = false
    private var monitorSource: DispatchSourceFileSystemObject?
    private var reloadTask: Task<Void, Never>?

    var photos: [PhotoFile] = []
    private(set) var albumByPhotoId: [UUID: Album] = [:]
    private(set) var newFilenameByPhotoId: [UUID: String] = [:]

    var albums: [Album] = []
    var startingAlbumNumber: Int = 1 {
        didSet {
            let clamped = max(1, min(9999, startingAlbumNumber))
            if clamped != startingAlbumNumber {
                startingAlbumNumber = clamped
                return
            }
            renumberAlbums()
        }
    }

    var selectionState: SelectionState = .idle

    var separator: Separator = .underscore { didSet { rebuildAssignmentCaches() } }
    var zeroPadding: Bool = false { didSet { rebuildAssignmentCaches() } }

    var createAlbumFolders: Bool = false
    var albumFolderPrefix: String = ""
    var duplicateMode: Bool = false
    var outputDirectoryURL: URL?
    private var isAccessingOutputScope = false

    var isLoading = false
    var isRenaming = false
    var showError = false
    var errorMessage = ""
    var showConfirmation = false
    var showComplete = false
    var resultMessage = ""
    var hasUndoManifest = false
    var showUndoConfirmation = false

    var photoPendingRename: PhotoFile?

    var showUnassignedOnly: Bool = false

    var gridThumbnailSize: GridThumbnailSize = .medium

    private var nextAlbumNumber: Int { startingAlbumNumber + albums.count }

    private var maxAlbumDigits: Int {
        let last = startingAlbumNumber + max(albums.count, 1) - 1
        return String(last).count
    }

    private var maxIndexDigits: Int {
        let maxCount = albums.map { photosInAlbum($0).count }.max() ?? 1
        return String(maxCount).count
    }

    var filenamePreview: String {
        let sep = separator.rawValue
        let a = zeroPadding ? String(format: "%0\(max(maxAlbumDigits, 2))d", startingAlbumNumber) : "\(startingAlbumNumber)"
        let i = zeroPadding ? String(format: "%0\(max(maxIndexDigits, 2))d", 1) : "1"
        var name = "\(a)\(sep)\(i).jpg"
        if createAlbumFolders {
            let folder = albumSubfolderName(forAlbumNumber: startingAlbumNumber)
            name = "\(folder)/\(name)"
        }
        return name
    }

    var photosForGrid: [PhotoFile] {
        if showUnassignedOnly {
            return photos.filter { albumByPhotoId[$0.id] == nil }
        }
        return photos
    }

    var statusMessage: String {
        if isLoading { return "Scanning folder…" }
        if isRenaming { return "Processing files…" }
        if photos.isEmpty { return "Select a folder to load photos." }
        switch selectionState {
        case .idle:
            let n = unassignedCount
            if n == 0 && !albums.isEmpty {
                return "All \(photos.count - n) photos assigned across \(albums.count) album(s). Ready to apply."
            }
            return "Select the first photo for Album \(nextAlbumNumber). \(n) unassigned."
        case .startSelected(let id):
            if let p = photos.first(where: { $0.id == id }) {
                return "First photo: \(p.originalFilename) — now select the last photo for Album \(nextAlbumNumber)."
            }
            return "Select the last photo for this album."
        }
    }

    var canRename: Bool { !albums.isEmpty && !isRenaming && !photos.isEmpty }
    var unassignedCount: Int { photos.filter { albumForPhoto($0) == nil }.count }

    var effectiveOutputDirectory: URL? {
        if duplicateMode {
            return outputDirectoryURL ?? directoryURL?.appendingPathComponent("Sorted")
        }
        return directoryURL
    }

    var outputDisplayPath: String {
        if let url = outputDirectoryURL { return url.lastPathComponent }
        return "Sorted/"
    }

    func albumForPhoto(_ photo: PhotoFile) -> Album? {
        albumByPhotoId[photo.id]
    }

    func albumSubfolderName(forAlbumNumber albumNumber: Int) -> String {
        let a = zeroPadding ? String(format: "%0\(max(maxAlbumDigits, 2))d", albumNumber) : "\(albumNumber)"
        let trimmed = albumFolderPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return a }
        return "\(trimmed)\(a)"
    }

    func photosInAlbum(_ album: Album) -> [PhotoFile] {
        photos.filter { album.contains($0) }.sorted { $0.sortIndex < $1.sortIndex }
    }

    func orderInAlbum(for photo: PhotoFile, in album: Album) -> Int {
        (photosInAlbum(album).firstIndex(where: { $0.id == photo.id }) ?? 0) + 1
    }

    func formattedName(albumNumber: Int, index: Int, ext: String) -> String {
        let sep = separator.rawValue
        let a = zeroPadding ? String(format: "%0\(max(maxAlbumDigits, 2))d", albumNumber) : "\(albumNumber)"
        let i = zeroPadding ? String(format: "%0\(max(maxIndexDigits, 2))d", index) : "\(index)"
        return "\(a)\(sep)\(i).\(ext)"
    }

    func newFilename(for photo: PhotoFile) -> String? {
        newFilenameByPhotoId[photo.id]
    }

    func displayRange(for album: Album) -> String {
        let ap = photosInAlbum(album)
        guard let first = ap.first, let last = ap.last else { return "—" }
        if first.id == last.id { return first.originalFilename }
        return "\(first.originalFilename) — \(last.originalFilename)"
    }

    static let albumColors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .mint, .cyan, .yellow]

    func colorForAlbum(_ album: Album) -> Color {
        let idx = max(0, album.number - 1)
        return Self.albumColors[idx % Self.albumColors.count]
    }

    func albumListTitle(for album: Album) -> String {
        if createAlbumFolders {
            return albumSubfolderName(forAlbumNumber: album.number)
        }
        return "\(album.number)"
    }

    func openDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose the folder containing photos to organize"
        panel.prompt = "Select"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadDirectory(url)
    }

    func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose where to save renamed copies"
        panel.prompt = "Select"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let prev = outputDirectoryURL, isAccessingOutputScope {
            prev.stopAccessingSecurityScopedResource()
        }
        outputDirectoryURL = url
        isAccessingOutputScope = url.startAccessingSecurityScopedResource()
    }

    func loadDirectory(_ url: URL) {
        if let prev = directoryURL, isAccessingSecurityScope {
            prev.stopAccessingSecurityScopedResource()
        }
        stopDirectoryMonitoring()

        directoryURL = url
        isAccessingSecurityScope = url.startAccessingSecurityScopedResource()
        albums = []
        selectionState = .idle
        photoPendingRename = nil
        isLoading = true

        Task {
            let result = await scanDirectory(url)
            photos = result
            rebuildAssignmentCaches()
            hasUndoManifest = FileRenamer.hasManifest(in: url)
            isLoading = false
            startDirectoryMonitoring()
        }
    }

    private nonisolated func scanDirectory(_ url: URL) async -> [PhotoFile] {
        let exts = supportedImageExtensions
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        let sorted = contents
            .filter { exts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        return sorted.enumerated().map { PhotoFile(url: $1, sortIndex: $0) }
    }

    private func startDirectoryMonitoring() {
        guard let url = directoryURL else { return }
        let fd = open(url.path(percentEncoded: false), O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename], queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.debouncedReload() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        monitorSource = source
    }

    private func stopDirectoryMonitoring() {
        monitorSource?.cancel()
        monitorSource = nil
    }

    private func debouncedReload() {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            reloadCurrentDirectory()
        }
    }

    private func reloadCurrentDirectory() {
        guard let url = directoryURL else { return }
        let previousCount = photos.count

        Task {
            let newPhotos = await scanDirectory(url)
            if newPhotos.count != previousCount {
                albums = []
                selectionState = .idle
            }
            photos = newPhotos
            rebuildAssignmentCaches()
            hasUndoManifest = FileRenamer.hasManifest(in: url)
        }
    }

    func selectPhoto(_ photo: PhotoFile) {
        if albumForPhoto(photo) != nil {
            errorMessage = "This photo is already part of an album. Remove that album first to reassign it."
            showError = true
            return
        }
        switch selectionState {
        case .idle:
            selectionState = .startSelected(photo.id)
        case .startSelected(let startId):
            guard let startPhoto = photos.first(where: { $0.id == startId }) else {
                selectionState = .idle; return
            }
            let lo = min(startPhoto.sortIndex, photo.sortIndex)
            let hi = max(startPhoto.sortIndex, photo.sortIndex)
            let conflicts = photos.filter { $0.sortIndex >= lo && $0.sortIndex <= hi }.filter { albumForPhoto($0) != nil }
            if !conflicts.isEmpty {
                errorMessage = "Some photos in this range are already assigned to another album."
                showError = true
                selectionState = .idle
                return
            }
            albums.append(Album(number: nextAlbumNumber, startSortIndex: lo, endSortIndex: hi))
            selectionState = .idle
            rebuildAssignmentCaches()
        }
    }

    func cancelSelection() { selectionState = .idle }

    func removeAlbum(_ album: Album) {
        albums.removeAll { $0.id == album.id }
        renumberAlbums()
    }

    func removeAllAlbums() {
        albums.removeAll()
        selectionState = .idle
        rebuildAssignmentCaches()
    }

    private func renumberAlbums() {
        albums.sort { $0.startSortIndex < $1.startSortIndex }
        albums = albums.enumerated().map {
            Album(number: startingAlbumNumber + $0.offset, startSortIndex: $0.element.startSortIndex, endSortIndex: $0.element.endSortIndex)
        }
        rebuildAssignmentCaches()
    }

    private func rebuildAssignmentCaches() {
        var albumMap: [UUID: Album] = [:]
        var nameMap: [UUID: String] = [:]
        for album in albums {
            let inAlbum = photos.filter { album.contains($0) }.sorted { $0.sortIndex < $1.sortIndex }
            for (idx, p) in inAlbum.enumerated() {
                albumMap[p.id] = album
                nameMap[p.id] = formattedName(albumNumber: album.number, index: idx + 1, ext: p.fileExtension)
            }
        }
        albumByPhotoId = albumMap
        newFilenameByPhotoId = nameMap
    }

    func buildOperations() -> [FileOperation] {
        guard let srcDir = directoryURL else { return [] }
        let baseDir: URL
        if duplicateMode {
            baseDir = outputDirectoryURL ?? srcDir.appendingPathComponent("Sorted")
        } else {
            baseDir = srcDir
        }

        var ops: [FileOperation] = []
        for album in albums.sorted(by: { $0.number < $1.number }) {
            let albumPhotos = photosInAlbum(album)
            for (order, photo) in albumPhotos.enumerated() {
                let name = formattedName(albumNumber: album.number, index: order + 1, ext: photo.fileExtension)
                var destDir = baseDir
                if createAlbumFolders {
                    let folder = albumSubfolderName(forAlbumNumber: album.number)
                    destDir = baseDir.appendingPathComponent(folder)
                }
                ops.append(FileOperation(sourceURL: photo.url, destinationURL: destDir.appendingPathComponent(name)))
            }
        }
        return ops
    }

    func executeRename() async {
        guard let srcDir = directoryURL else { return }
        isRenaming = true
        let ops = buildOperations()
        let isCopy = duplicateMode

        do {
            try await Task.detached {
                if isCopy {
                    try FileRenamer.executeCopy(operations: ops)
                } else {
                    try FileRenamer.executeRename(in: srcDir, operations: ops)
                }
            }.value
            resultMessage = isCopy
                ? "Copied \(ops.count) file(s) successfully."
                : "Renamed \(ops.count) file(s) successfully."
            showComplete = true
            loadDirectory(srcDir)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isRenaming = false
    }

    func executeUndo() async {
        guard let dir = directoryURL else { return }
        isRenaming = true
        do {
            try await Task.detached { try FileRenamer.undoRename(in: dir) }.value
            resultMessage = "All files restored to their original names."
            showComplete = true
            loadDirectory(dir)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isRenaming = false
    }

    func applyQuickRename(photo: PhotoFile, newBasename: String) async {
        guard let dir = directoryURL else { return }

        let ops: [FileOperation]
        do {
            ops = try buildRenameOperation(photo: photo, basenameInput: newBasename, in: dir)
            try validateManualRenameDestinations(ops: ops, in: dir)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            return
        }

        guard !ops.isEmpty else { return }

        isRenaming = true
        do {
            try await Task.detached {
                try FileRenamer.executeRename(in: dir, operations: ops)
            }.value
            resultMessage = "Renamed to “\(ops[0].destinationURL.lastPathComponent)”."
            showComplete = true
            photoPendingRename = nil
            loadDirectory(dir)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isRenaming = false
    }

    private func buildRenameOperation(photo: PhotoFile, basenameInput: String, in dir: URL) throws -> [FileOperation] {
        let trimmed = basenameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ManualRenameValidationError.emptyName }

        let last = (trimmed as NSString).lastPathComponent
        guard !last.isEmpty, last != ".", last != ".." else { throw ManualRenameValidationError.emptyName }

        let base = (last as NSString).deletingPathExtension
        guard !base.isEmpty else { throw ManualRenameValidationError.emptyName }

        try Self.validateFilenameForFilesystem(base)

        let finalName: String
        if photo.fileExtension.isEmpty {
            finalName = base
        } else {
            finalName = "\(base).\(photo.fileExtension)"
        }

        let dest = dir.appendingPathComponent(finalName)
        guard dest.lastPathComponent != photo.originalFilename else {
            throw ManualRenameValidationError.sameAsCurrent
        }

        try Self.validateFilenameForFilesystem(finalName)

        return [FileOperation(sourceURL: photo.url, destinationURL: dest)]
    }

    private static func validateFilenameForFilesystem(_ name: String) throws {
        if name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            throw ManualRenameValidationError.invalidCharacters
        }
        let blocked = CharacterSet(charactersIn: "/:\u{0000}")
        if name.unicodeScalars.contains(where: { blocked.contains($0) }) {
            throw ManualRenameValidationError.invalidCharacters
        }
    }

    private func validateManualRenameDestinations(ops: [FileOperation], in dir: URL) throws {
        let fm = FileManager.default
        let sourcePaths = Set(ops.map(\.sourceURL.path))
        for op in ops {
            let path = op.destinationURL.path
            guard fm.fileExists(atPath: path) else { continue }
            if sourcePaths.contains(path) { continue }
            throw RenameError.destinationExists(op.destinationURL.lastPathComponent)
        }
    }

    deinit {
        stopDirectoryMonitoring()
        if let u = directoryURL, isAccessingSecurityScope { u.stopAccessingSecurityScopedResource() }
        if let u = outputDirectoryURL, isAccessingOutputScope { u.stopAccessingSecurityScopedResource() }
    }
}
