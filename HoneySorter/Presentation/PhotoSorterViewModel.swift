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
    var photoIndexPrefix: String = "" { didSet { rebuildAssignmentCaches() } }

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

    var isFindingDuplicates = false
    var showDuplicateReview = false
    var duplicateResultMessage = ""
    var showNoDuplicates = false

    struct DuplicateReviewItem: Identifiable, Sendable {
        nonisolated let id = UUID()
        nonisolated let url: URL
        nonisolated let filename: String
        var isSelectedForTrash: Bool
    }

    struct DuplicateReviewGroup: Identifiable, Sendable {
        nonisolated let id = UUID()
        var items: [DuplicateReviewItem]
    }

    var duplicateReviewGroups: [DuplicateReviewGroup] = []
    var hasDuplicateTrashCandidates: Bool {
        duplicateReviewGroups.contains { $0.items.contains(where: { $0.isSelectedForTrash }) }
    }

    var showUnassignedOnly: Bool = false

    var gridThumbnailSize: GridThumbnailSize = .medium
    var photoOrdering: PhotoOrdering = .filename {
        didSet {
            guard photoOrdering != oldValue else { return }
            reloadWithCurrentOrdering()
        }
    }

    private var namingConfiguration: AlbumNamingConfiguration {
        AlbumNamingConfiguration(
            separator: separator,
            zeroPadding: zeroPadding,
            startingAlbumNumber: startingAlbumNumber,
            photoIndexPrefix: photoIndexPrefix,
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
    var unassignedCount: Int { max(0, photos.count - albumByPhotoId.count) }

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
        let (maxA, maxI) = AlbumSortingService.padWidths(
            config: namingConfiguration,
            albumCount: albums.count,
            albums: albums
        )
        return AlbumSortingService.formatFilename(
            albumNumber: albumNumber,
            index: index,
            ext: ext,
            config: namingConfiguration,
            maxAlbumPadWidth: maxA,
            maxIndexPadWidth: maxI
        )
    }

    func albumSubfolderName(forAlbumNumber albumNumber: Int) -> String {
        AlbumSortingService.albumSubfolderName(
            forAlbumNumber: albumNumber,
            config: namingConfiguration,
            albumCount: albums.count
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
            albumCount: albums.count
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
            let result = await PhotoDirectoryScanner.loadImages(from: url, ordering: photoOrdering)
            await MainActor.run {
                photos = result
                rebuildAssignmentCaches()
                hasUndoManifest = FileRenamer.hasManifest(in: url)
                isLoading = false
                startDirectoryMonitoring()
            }
        }
    }

    func rescanCurrentDirectory(preserveAlbumAssignments: Bool = false) async {
        guard let url = directoryURL else { return }
        let oldPhotos = photos
        let oldAlbums = albums
        await MainActor.run { isLoading = true }
        let result = await PhotoDirectoryScanner.loadImages(from: url, ordering: photoOrdering)
        await MainActor.run {
            photos = result
            if preserveAlbumAssignments {
                albums = AlbumSortingService.remapAlbumsAfterPhotoListChange(
                    previousPhotos: oldPhotos,
                    previousAlbums: oldAlbums,
                    nextPhotos: result,
                    startingAlbumNumber: startingAlbumNumber
                )
                pruneSelectionAfterPhotoChanges()
            } else {
                albums = []
                selectionState = .idle
            }
            photoPendingRename = nil
            rebuildAssignmentCaches()
            hasUndoManifest = FileRenamer.hasManifest(in: url)
            isLoading = false
        }
    }

    private func startDirectoryMonitoring() {
        guard let url = directoryURL else { return }
        directoryMonitor.start(url: url) { [weak self] in
            self?.debouncedReload()
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
        let oldPhotos = photos
        let oldAlbums = albums

        Task {
            let newPhotos = await PhotoDirectoryScanner.loadImages(from: url, ordering: photoOrdering)
            await MainActor.run {
                photos = newPhotos
                albums = AlbumSortingService.remapAlbumsAfterPhotoListChange(
                    previousPhotos: oldPhotos,
                    previousAlbums: oldAlbums,
                    nextPhotos: newPhotos,
                    startingAlbumNumber: startingAlbumNumber
                )
                pruneSelectionAfterPhotoChanges()
                rebuildAssignmentCaches()
                hasUndoManifest = FileRenamer.hasManifest(in: url)
            }
        }
    }

    private func reloadWithCurrentOrdering() {
        guard let url = directoryURL else { return }
        Task {
            await MainActor.run { isLoading = true }
            let newPhotos = await PhotoDirectoryScanner.loadImages(from: url, ordering: photoOrdering)
            await MainActor.run {
                albums = []
                selectionState = .idle
                photos = newPhotos
                rebuildAssignmentCaches()
                isLoading = false
            }
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

    private func pruneSelectionAfterPhotoChanges() {
        switch selectionState {
        case .idle:
            break
        case .startSelected(let id):
            if !photos.contains(where: { $0.id == id }) {
                selectionState = .idle
            }
        }
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
            await rescanCurrentDirectory()
            resultMessage = isCopy
                ? "Copied \(ops.count) file(s) successfully."
                : "Renamed \(ops.count) file(s) successfully."
            showComplete = true
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
            await rescanCurrentDirectory()
            resultMessage = "All files restored to their original names."
            showComplete = true
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
            await rescanCurrentDirectory(preserveAlbumAssignments: true)
            resultMessage = "Renamed to “\(ops[0].destinationURL.lastPathComponent)”."
            showComplete = true
            photoPendingRename = nil
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isRenaming = false
    }

    func trashPhotos(_ photos: [PhotoFile]) async {
        let urls = photos.map(\.url)
        isRenaming = true
        do {
            try await Task.detached(priority: .userInitiated) {
                _ = try FileTrashService.moveToTrash(urls: urls)
            }.value
            await rescanCurrentDirectory(preserveAlbumAssignments: true)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isRenaming = false
    }

    func scanForDuplicates() async {
        guard !isFindingDuplicates else { return }
        isFindingDuplicates = true
        defer { isFindingDuplicates = false }

        let urls = photos.map(\.url)
        let result = await DuplicatePhotoService.findExactDuplicates(urls: urls, maxConcurrentHashes: 4)
        applyDuplicateGroups(result.groups)
    }

    private func applyDuplicateGroups(_ groups: [[URL]]) {
        if groups.isEmpty {
            duplicateReviewGroups = []
            showDuplicateReview = false
            showNoDuplicates = true
            return
        }

        duplicateReviewGroups = groups.map { urls in
            var items: [DuplicateReviewItem] = urls.enumerated().map { idx, u in
                DuplicateReviewItem(
                    url: u,
                    filename: u.lastPathComponent,
                    isSelectedForTrash: idx != 0
                )
            }
            if items.allSatisfy({ $0.isSelectedForTrash }) {
                items[0].isSelectedForTrash = false
            }
            return DuplicateReviewGroup(items: items)
        }

        duplicateResultMessage = "Uncheck anything that isn’t a duplicate."
        showDuplicateReview = true
    }

    func trashSelectedDuplicates() async {
        let urls = duplicateReviewGroups.flatMap { $0.items.filter(\.isSelectedForTrash).map(\.url) }
        guard !urls.isEmpty else { return }
        isRenaming = true
        do {
            try await Task.detached(priority: .userInitiated) {
                _ = try FileTrashService.moveToTrash(urls: urls)
            }.value
            await rescanCurrentDirectory(preserveAlbumAssignments: true)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isRenaming = false
        duplicateReviewGroups = []
        showDuplicateReview = false
    }

    deinit {
        directoryMonitor.stop()
        if let u = directoryURL, isAccessingSecurityScope { u.stopAccessingSecurityScopedResource() }
        if let u = outputDirectoryURL, isAccessingOutputScope { u.stopAccessingSecurityScopedResource() }
    }
}
