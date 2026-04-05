import AppKit
import SwiftUI

@Observable
class PhotoSorterViewModel {

    var directoryURL: URL?
    private var isAccessingSecurityScope = false
    private let directoryMonitor = DirectoryMonitor()
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

    var createAlbumFolders: Bool = false { didSet { rebuildAssignmentCaches() } }
    var albumFolderPrefix: String = "" { didSet { rebuildAssignmentCaches() } }
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

    private var namingConfiguration: AlbumNamingConfiguration {
        AlbumNamingConfiguration(
            separator: separator,
            zeroPadding: zeroPadding,
            startingAlbumNumber: startingAlbumNumber,
            albumFolderPrefix: albumFolderPrefix,
            createAlbumFolders: createAlbumFolders
        )
    }

    private var nextAlbumNumber: Int {
        AlbumSortingService.nextAlbumNumber(startingAlbumNumber: startingAlbumNumber, albumCount: albums.count)
    }

    var filenamePreview: String {
        AlbumSortingService.filenamePreview(
            config: namingConfiguration,
            albumCount: albums.count,
            photos: photos,
            albums: albums
        )
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

    func photosInAlbum(_ album: Album) -> [PhotoFile] {
        AlbumSortingService.photosInAlbum(photos, album: album)
    }

    func formattedName(albumNumber: Int, index: Int, ext: String) -> String {
        AlbumSortingService.formattedName(
            albumNumber: albumNumber,
            index: index,
            ext: ext,
            config: namingConfiguration,
            albumCount: albums.count,
            photos: photos,
            albums: albums
        )
    }

    func albumSubfolderName(forAlbumNumber albumNumber: Int) -> String {
        AlbumSortingService.albumSubfolderName(
            forAlbumNumber: albumNumber,
            config: namingConfiguration,
            albumCount: albums.count,
            photos: photos,
            albums: albums
        )
    }

    func newFilename(for photo: PhotoFile) -> String? {
        newFilenameByPhotoId[photo.id]
    }

    func displayRange(for album: Album) -> String {
        AlbumSortingService.displayRange(for: album, photos: photos)
    }

    func colorForAlbum(_ album: Album) -> Color {
        AlbumPalette.color(forAlbumNumber: album.number)
    }

    func albumListTitle(for album: Album) -> String {
        AlbumSortingService.albumListTitle(
            for: album,
            config: namingConfiguration,
            albumCount: albums.count,
            photos: photos,
            albums: albums
        )
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
        directoryMonitor.stop()

        directoryURL = url
        isAccessingSecurityScope = url.startAccessingSecurityScopedResource()
        albums = []
        selectionState = .idle
        photoPendingRename = nil
        isLoading = true

        Task {
            let result = await PhotoDirectoryScanner.loadImages(from: url)
            photos = result
            rebuildAssignmentCaches()
            hasUndoManifest = FileRenamer.hasManifest(in: url)
            isLoading = false
            startDirectoryMonitoring()
        }
    }

    private func startDirectoryMonitoring() {
        guard let url = directoryURL else { return }
        directoryMonitor.start(url: url) { [weak self] in
            Task { @MainActor in self?.debouncedReload() }
        }
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
            let newPhotos = await PhotoDirectoryScanner.loadImages(from: url)
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
            errorMessage = AlbumSortingService.RangeSelectionError.photoAlreadyInAlbum.rawValue
            showError = true
            return
        }
        switch selectionState {
        case .idle:
            selectionState = .startSelected(photo.id)
        case .startSelected(let startId):
            guard let startPhoto = photos.first(where: { $0.id == startId }) else {
                selectionState = .idle
                return
            }
            switch AlbumSortingService.tryAppendAlbumFromRange(
                startPhoto: startPhoto,
                endPhoto: photo,
                photos: photos,
                albumByPhotoId: albumByPhotoId,
                nextAlbumNumber: nextAlbumNumber
            ) {
            case .success(let album):
                albums.append(album)
                selectionState = .idle
                rebuildAssignmentCaches()
            case .failure(let error):
                errorMessage = error.rawValue
                showError = true
                selectionState = .idle
            }
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
        albums = AlbumSortingService.renumberedAlbums(albums, startingAlbumNumber: startingAlbumNumber)
        rebuildAssignmentCaches()
    }

    private func rebuildAssignmentCaches() {
        let caches = AlbumSortingService.assignmentCaches(
            photos: photos,
            albums: albums,
            config: namingConfiguration
        )
        albumByPhotoId = caches.albumByPhotoId
        newFilenameByPhotoId = caches.newFilenameByPhotoId
    }

    func buildOperations() -> [FileOperation] {
        guard let srcDir = directoryURL else { return [] }
        return AlbumSortingService.buildRenameOperations(
            photos: photos,
            albums: albums,
            config: namingConfiguration,
            sourceDirectory: srcDir,
            duplicateMode: duplicateMode,
            outputDirectoryURL: outputDirectoryURL
        )
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
            ops = try ManualRenameService.buildOperation(photo: photo, basenameInput: newBasename, in: dir)
            try ManualRenameService.validateDestinationsDoNotCollide(operations: ops, in: dir)
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

    deinit {
        directoryMonitor.stop()
        if let u = directoryURL, isAccessingSecurityScope { u.stopAccessingSecurityScopedResource() }
        if let u = outputDirectoryURL, isAccessingOutputScope { u.stopAccessingSecurityScopedResource() }
    }
}
