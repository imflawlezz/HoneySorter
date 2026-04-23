import AppKit
import SwiftUI

@Observable
class PhotoSorterViewModel {

    var directoryURL: URL?
    private var isAccessingSecurityScope = false
    private let directoryMonitor = DirectoryMonitor()
    private var reloadTask: Task<Void, Never>?

    var photos: [PhotoFile] = []
    private struct AssignmentIndex: Sendable {
        var indexByPath: [String: Int]
        var albumIdByIndex: [UUID?]

        init(photos: [PhotoFile]) {
            self.indexByPath = Dictionary(uniqueKeysWithValues: photos.map { ($0.url.path, $0.sortIndex) })
            self.albumIdByIndex = Array(repeating: nil, count: photos.count)
        }
    }

    private var assignmentIndex = AssignmentIndex(photos: [])
    private var albumsById: [UUID: Album] = [:]
    private var selectionUpdateTask: Task<Void, Never>?
    var isUpdatingSelection = false

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

    var separator: Separator = .underscore
    var zeroPadding: Bool = false
    var photoIndexPrefix: String = ""

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

    var isFindingVariantSets = false
    var showVariantSetStrictnessDialog = false
    var showVariantSetReview = false
    var variantSetResultMessage = ""
    var showNoVariantSets = false
    var pendingVariantSetStrictness: VariantSetStrictness = .balanced

    struct VariantSetReviewItem: Identifiable, Sendable {
        nonisolated let id = UUID()
        nonisolated let url: URL
        nonisolated let filename: String
        var isIncluded: Bool
    }

    struct VariantSetReviewGroup: Identifiable, Sendable {
        nonisolated let id = UUID()
        var items: [VariantSetReviewItem]
    }

    var variantSetReviewGroups: [VariantSetReviewGroup] = []
    var hasVariantSetCandidates: Bool {
        variantSetReviewGroups.contains { g in g.items.filter(\.isIncluded).count >= 2 }
    }

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
            return photos.filter { photo in
                let i = photo.sortIndex
                guard i >= 0, i < assignmentIndex.albumIdByIndex.count else { return true }
                return assignmentIndex.albumIdByIndex[i] == nil
            }
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
        case .editing(let anchorId, let albumId):
            let albumNumber = albums.first(where: { $0.id == albumId })?.number ?? nextAlbumNumber
            if let p = photos.first(where: { $0.id == anchorId }) {
                return "First photo: \(p.originalFilename) — now select the last photo for Album \(albumNumber). (Shift‑click adds/removes single photos.)"
            }
            return "Select the last photo for this album."
        }
    }

    var canRename: Bool { !albums.isEmpty && !isRenaming && !photos.isEmpty }
    var unassignedCount: Int { assignmentIndex.albumIdByIndex.reduce(0) { $0 + ($1 == nil ? 1 : 0) } }
    var isBusy: Bool {
        isLoading
            || isRenaming
            || isFindingDuplicates
            || isFindingVariantSets
            || isUpdatingSelection
    }

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
        let i = photo.sortIndex
        guard i >= 0, i < assignmentIndex.albumIdByIndex.count else { return nil }
        guard let albumId = assignmentIndex.albumIdByIndex[i] else { return nil }
        return albumsById[albumId]
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
        guard let album = albumForPhoto(photo) else { return nil }
        let i = photo.sortIndex
        guard let pos = album.memberIndices.binaryIndex(of: i) else { return nil }
        let order = album.isReversed ? (album.memberIndices.count - pos) : (pos + 1)
        return formattedName(albumNumber: album.number, index: order, ext: photo.fileExtension)
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
                rebuildAssignmentIndex()
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
            rebuildAssignmentIndex()
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
                rebuildAssignmentIndex()
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
                rebuildAssignmentIndex()
                isLoading = false
            }
        }
    }

    func handlePhotoClick(_ photo: PhotoFile, modifiers: NSEvent.ModifierFlags = []) {
        if modifiers.contains(.shift) {
            handleShiftClick(photo)
        } else {
            handleNormalClick(photo)
        }
    }

    private func handleNormalClick(_ photo: PhotoFile) {
        switch selectionState {
        case .idle:
            if let existing = albumForPhoto(photo) {
                selectionState = .editing(anchorPhotoId: photo.id, albumId: existing.id)
                return
            }
            let newAlbum = Album(
                number: nextAlbumNumber,
                isReversed: false,
                memberIndices: [photo.sortIndex]
            )
            albums.append(newAlbum)
            selectionState = .editing(anchorPhotoId: photo.id, albumId: newAlbum.id)
            rebuildAssignmentIndex()

        case .editing(let anchorId, let albumId):
            guard let anchorPhoto = photos.first(where: { $0.id == anchorId }) else {
                selectionState = .idle
                return
            }
            let lo = min(anchorPhoto.sortIndex, photo.sortIndex)
            let hi = max(anchorPhoto.sortIndex, photo.sortIndex)
            let isReversed = anchorPhoto.sortIndex > photo.sortIndex
            runSelectionUpdate {
                Self.computeAlbumsAfterExclusiveRange(
                    photos: self.photos,
                    albums: self.albums,
                    albumId: albumId,
                    startingAlbumNumber: self.startingAlbumNumber,
                    lo: lo,
                    hi: hi,
                    isReversed: isReversed
                )
            } apply: { newAlbums in
                self.albums = newAlbums
                self.selectionState = .idle
            }
        }
    }

    private func handleShiftClick(_ photo: PhotoFile) {
        switch selectionState {
        case .idle:
            // Shift-click with no active album behaves like a normal first click.
            handleNormalClick(photo)
        case .editing(_, let albumId):
            runSelectionUpdate {
                Self.computeAlbumsAfterExclusiveToggle(
                    photos: self.photos,
                    albums: self.albums,
                    albumId: albumId,
                    startingAlbumNumber: self.startingAlbumNumber,
                    toggledPhotoIndex: photo.sortIndex
                )
            } apply: { newAlbums in
                self.albums = newAlbums
            }
        }
    }

    private func runSelectionUpdate(
        compute: @escaping @Sendable () -> [Album],
        apply: @escaping ([Album]) -> Void
    ) {
        selectionUpdateTask?.cancel()
        isUpdatingSelection = true
        let computeCopy = compute
        selectionUpdateTask = Task.detached(priority: .userInitiated) { [weak self] in
            let newAlbums = computeCopy()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                apply(newAlbums)
                self.isUpdatingSelection = false
                self.rebuildAssignmentIndex()
            }
        }
    }

    nonisolated private static func computeAlbumsAfterExclusiveRange(
        photos: [PhotoFile],
        albums: [Album],
        albumId: UUID,
        startingAlbumNumber: Int,
        lo: Int,
        hi: Int,
        isReversed: Bool
    ) -> [Album] {
        guard lo >= 0, hi < photos.count, lo <= hi else {
            return AlbumSortingService.renumberedAlbums(albums, startingAlbumNumber: startingAlbumNumber)
        }

        let rangeIndices = Set(lo...hi)

        var kept: [Album] = []
        kept.reserveCapacity(albums.count)

        var targetNumber: Int?
        for album in albums {
            if album.id == albumId {
                targetNumber = album.number
                continue
            }
            if let updated = removingIndices(from: album, remove: rangeIndices) {
                kept.append(updated)
            }
        }

        let number = targetNumber ?? AlbumSortingService.nextAlbumNumber(startingAlbumNumber: startingAlbumNumber, albumCount: kept.count)
        let memberIndices = Array(lo...hi)
        kept.append(
            Album(
                id: albumId,
                number: number,
                isReversed: isReversed,
                memberIndices: memberIndices
            )
        )

        return AlbumSortingService.renumberedAlbums(kept, startingAlbumNumber: startingAlbumNumber)
    }

    nonisolated private static func computeAlbumsAfterExclusiveToggle(
        photos: [PhotoFile],
        albums: [Album],
        albumId: UUID,
        startingAlbumNumber: Int,
        toggledPhotoIndex: Int
    ) -> [Album] {
        guard let target = albums.first(where: { $0.id == albumId }) else {
            return AlbumSortingService.renumberedAlbums(albums, startingAlbumNumber: startingAlbumNumber)
        }

        let removeSet: Set<Int> = [toggledPhotoIndex]

        var updated: [Album] = []
        updated.reserveCapacity(albums.count)

        for album in albums where album.id != albumId {
            if let updatedAlbum = removingIndices(from: album, remove: removeSet) {
                updated.append(updatedAlbum)
            }
        }

        var memberIndices = target.memberIndices
        if let existingIdx = memberIndices.firstIndex(of: toggledPhotoIndex) {
            memberIndices.remove(at: existingIdx)
        } else {
            // Keep stable album order (global sortIndex order).
            let insertion = memberIndices.insertionIndex(of: toggledPhotoIndex)
            memberIndices.insert(toggledPhotoIndex, at: insertion)
        }

        guard !memberIndices.isEmpty else {
            return AlbumSortingService.renumberedAlbums(updated, startingAlbumNumber: startingAlbumNumber)
        }

        updated.append(
            Album(
                id: target.id,
                number: target.number,
                isReversed: false,
                memberIndices: memberIndices
            )
        )

        return AlbumSortingService.renumberedAlbums(updated, startingAlbumNumber: startingAlbumNumber)
    }

    nonisolated private static func removingIndices(from album: Album, remove indicesToRemove: Set<Int>) -> Album? {
        let remaining = album.memberIndices.filter { !indicesToRemove.contains($0) }
        guard !remaining.isEmpty else { return nil }
        let uniqueSorted = Array(Set(remaining)).sorted()
        return Album(
            id: album.id,
            number: album.number,
            isReversed: album.isReversed,
            memberIndices: uniqueSorted
        )
    }

    func cancelSelection() { selectionState = .idle }

    func removeAlbum(_ album: Album) {
        albums.removeAll { $0.id == album.id }
        renumberAlbums()
    }

    func removeAllAlbums() {
        albums.removeAll()
        selectionState = .idle
        rebuildAssignmentIndex()
    }

    private func renumberAlbums() {
        albums = AlbumSortingService.renumberedAlbums(albums, startingAlbumNumber: startingAlbumNumber)
        rebuildAssignmentIndex()
    }

    private func rebuildAssignmentIndex() {
        assignmentIndex = AssignmentIndex(photos: photos)
        albumsById = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0) })
        guard !photos.isEmpty else { return }
        for album in albums {
            for i in album.memberIndices where i >= 0 && i < assignmentIndex.albumIdByIndex.count {
                assignmentIndex.albumIdByIndex[i] = album.id
            }
        }
    }

    private func pruneSelectionAfterPhotoChanges() {
        switch selectionState {
        case .idle:
            break
        case .editing(let anchorId, _):
            if !photos.contains(where: { $0.id == anchorId }) {
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

    func scanForVariantSets(strictness: VariantSetStrictness) async {
        guard !isFindingVariantSets else { return }
        isFindingVariantSets = true
        defer { isFindingVariantSets = false }

        let urls = photos.map(\.url)
        let result = await VariantSetService.findVariantSets(urls: urls, strictness: strictness, maxConcurrent: 4)
        if result.groups.isEmpty {
            variantSetReviewGroups = []
            showVariantSetReview = false
            showNoVariantSets = true
            return
        }

        variantSetReviewGroups = result.groups.map { urls in
            let items = urls.map { u in
                VariantSetReviewItem(url: u, filename: u.lastPathComponent, isIncluded: true)
            }
            return VariantSetReviewGroup(items: items)
        }
        variantSetResultMessage = "Uncheck anything that shouldn’t be grouped."
        showVariantSetReview = true
    }

    func applyVariantSets() {
        let groups = variantSetReviewGroups
            .map { $0.items.filter(\.isIncluded).map(\.url) }
            .filter { $0.count >= 2 }

        guard !groups.isEmpty else { return }

        let pathToIndex: [String: Int] = Dictionary(uniqueKeysWithValues: photos.map { ($0.url.path, $0.sortIndex) })
        let normalizedGroups: [[URL]] = groups
            .map { urls in urls.filter { pathToIndex[$0.path] != nil } }
            .filter { $0.count >= 2 }

        guard !normalizedGroups.isEmpty else { return }

        let sortedGroups: [[URL]] = normalizedGroups.sorted { a, b in
            let aMin = a.compactMap { pathToIndex[$0.path] }.min() ?? Int.max
            let bMin = b.compactMap { pathToIndex[$0.path] }.min() ?? Int.max
            if aMin != bMin { return aMin < bMin }
            return (a.first?.lastPathComponent ?? "") < (b.first?.lastPathComponent ?? "")
        }

        let newAssignedIndices = Set(sortedGroups.flatMap { $0.compactMap { pathToIndex[$0.path] } })

        var keptExisting: [Album] = []
        keptExisting.reserveCapacity(albums.count)
        for album in albums {
            if let updated = Self.removingIndices(from: album, remove: newAssignedIndices) {
                keptExisting.append(updated)
            }
        }

        let baseNumber = startingAlbumNumber
        let newAlbums: [Album] = sortedGroups.enumerated().compactMap { (offset, urls) in
            let indices = urls.compactMap { pathToIndex[$0.path] }.sorted()
            guard !indices.isEmpty else { return nil }
            return Album(
                number: baseNumber + offset,
                isReversed: false,
                memberIndices: indices
            )
        }

        let combined = (keptExisting + newAlbums).sorted { $0.startSortIndex < $1.startSortIndex }
        albums = AlbumSortingService.renumberedAlbums(combined, startingAlbumNumber: startingAlbumNumber)
        selectionState = .idle
        rebuildAssignmentIndex()
        showVariantSetReview = false
        variantSetReviewGroups = []
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

private extension Array where Element == Int {
    func insertionIndex(of x: Int) -> Int {
        var lo = 0
        var hi = count
        while lo < hi {
            let mid = (lo + hi) / 2
            if self[mid] < x {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }

    func binaryContains(_ x: Int) -> Bool {
        var lo = 0
        var hi = count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let v = self[mid]
            if v == x { return true }
            if v < x {
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return false
    }

    func binaryIndex(of x: Int) -> Int? {
        var lo = 0
        var hi = count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let v = self[mid]
            if v == x { return mid }
            if v < x {
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return nil
    }
}
