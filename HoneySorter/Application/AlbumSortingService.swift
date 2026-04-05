import Foundation

enum AlbumSortingService {

    static func photosInAlbum(_ photos: [PhotoFile], album: Album) -> [PhotoFile] {
        photos.filter { album.contains($0) }.sorted { $0.sortIndex < $1.sortIndex }
    }

    static func maxAlbumDigits(startingAlbumNumber: Int, albumCount: Int) -> Int {
        let last = startingAlbumNumber + max(albumCount, 1) - 1
        return String(last).count
    }

    static func maxIndexDigits(photos: [PhotoFile], albums: [Album]) -> Int {
        let maxCount = albums.map { photosInAlbum(photos, album: $0).count }.max() ?? 1
        return String(maxCount).count
    }

    static func formattedName(
        albumNumber: Int,
        index: Int,
        ext: String,
        config: AlbumNamingConfiguration,
        albumCount: Int,
        photos: [PhotoFile],
        albums: [Album]
    ) -> String {
        let sep = config.separator.rawValue
        let maxA = max(maxAlbumDigits(startingAlbumNumber: config.startingAlbumNumber, albumCount: albumCount), 2)
        let maxI = max(maxIndexDigits(photos: photos, albums: albums), 2)
        let a = config.zeroPadding ? String(format: "%0\(maxA)d", albumNumber) : "\(albumNumber)"
        let i = config.zeroPadding ? String(format: "%0\(maxI)d", index) : "\(index)"
        return "\(a)\(sep)\(i).\(ext)"
    }

    static func albumSubfolderName(
        forAlbumNumber albumNumber: Int,
        config: AlbumNamingConfiguration,
        albumCount: Int,
        photos: [PhotoFile],
        albums: [Album]
    ) -> String {
        let maxA = max(maxAlbumDigits(startingAlbumNumber: config.startingAlbumNumber, albumCount: albumCount), 2)
        let a = config.zeroPadding ? String(format: "%0\(maxA)d", albumNumber) : "\(albumNumber)"
        let trimmed = config.albumFolderPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return a }
        return "\(trimmed)\(a)"
    }

    static func filenamePreview(config: AlbumNamingConfiguration, albumCount: Int, photos: [PhotoFile], albums: [Album]) -> String {
        let sep = config.separator.rawValue
        let maxA = max(maxAlbumDigits(startingAlbumNumber: config.startingAlbumNumber, albumCount: albumCount), 2)
        let maxI = max(maxIndexDigits(photos: photos, albums: albums), 2)
        let a = config.zeroPadding ? String(format: "%0\(maxA)d", config.startingAlbumNumber) : "\(config.startingAlbumNumber)"
        let i = config.zeroPadding ? String(format: "%0\(maxI)d", 1) : "1"
        var name = "\(a)\(sep)\(i).jpg"
        if config.createAlbumFolders {
            let folder = albumSubfolderName(
                forAlbumNumber: config.startingAlbumNumber,
                config: config,
                albumCount: albumCount,
                photos: photos,
                albums: albums
            )
            name = "\(folder)/\(name)"
        }
        return name
    }

    static func assignmentCaches(
        photos: [PhotoFile],
        albums: [Album],
        config: AlbumNamingConfiguration
    ) -> (albumByPhotoId: [UUID: Album], newFilenameByPhotoId: [UUID: String]) {
        var albumMap: [UUID: Album] = [:]
        var nameMap: [UUID: String] = [:]
        let count = albums.count
        for album in albums {
            let inAlbum = photosInAlbum(photos, album: album)
            for (idx, p) in inAlbum.enumerated() {
                albumMap[p.id] = album
                nameMap[p.id] = formattedName(
                    albumNumber: album.number,
                    index: idx + 1,
                    ext: p.fileExtension,
                    config: config,
                    albumCount: count,
                    photos: photos,
                    albums: albums
                )
            }
        }
        return (albumMap, nameMap)
    }

    static func renumberedAlbums(_ albums: [Album], startingAlbumNumber: Int) -> [Album] {
        let sorted = albums.sorted { $0.startSortIndex < $1.startSortIndex }
        return sorted.enumerated().map {
            Album(number: startingAlbumNumber + $0.offset, startSortIndex: $0.element.startSortIndex, endSortIndex: $0.element.endSortIndex)
        }
    }

    static func nextAlbumNumber(startingAlbumNumber: Int, albumCount: Int) -> Int {
        startingAlbumNumber + albumCount
    }

    enum RangeSelectionError: String, Error {
        case photoAlreadyInAlbum = "This photo is already part of an album. Remove that album first to reassign it."
        case rangeHasAssignedPhotos = "Some photos in this range are already assigned to another album."
    }

    static func tryAppendAlbumFromRange(
        startPhoto: PhotoFile,
        endPhoto: PhotoFile,
        photos: [PhotoFile],
        albumByPhotoId: [UUID: Album],
        nextAlbumNumber: Int
    ) -> Result<Album, RangeSelectionError> {
        let lo = min(startPhoto.sortIndex, endPhoto.sortIndex)
        let hi = max(startPhoto.sortIndex, endPhoto.sortIndex)
        let conflicts = photos
            .filter { $0.sortIndex >= lo && $0.sortIndex <= hi }
            .filter { albumByPhotoId[$0.id] != nil }
        if !conflicts.isEmpty {
            return .failure(.rangeHasAssignedPhotos)
        }
        return .success(Album(number: nextAlbumNumber, startSortIndex: lo, endSortIndex: hi))
    }

    static func buildRenameOperations(
        photos: [PhotoFile],
        albums: [Album],
        config: AlbumNamingConfiguration,
        sourceDirectory: URL,
        duplicateMode: Bool,
        outputDirectoryURL: URL?
    ) -> [FileOperation] {
        let baseDir: URL
        if duplicateMode {
            baseDir = outputDirectoryURL ?? sourceDirectory.appendingPathComponent("Sorted")
        } else {
            baseDir = sourceDirectory
        }

        let count = albums.count
        var ops: [FileOperation] = []
        for album in albums.sorted(by: { $0.number < $1.number }) {
            let albumPhotos = photosInAlbum(photos, album: album)
            for (order, photo) in albumPhotos.enumerated() {
                let name = formattedName(
                    albumNumber: album.number,
                    index: order + 1,
                    ext: photo.fileExtension,
                    config: config,
                    albumCount: count,
                    photos: photos,
                    albums: albums
                )
                var destDir = baseDir
                if config.createAlbumFolders {
                    let folder = albumSubfolderName(
                        forAlbumNumber: album.number,
                        config: config,
                        albumCount: count,
                        photos: photos,
                        albums: albums
                    )
                    destDir = baseDir.appendingPathComponent(folder)
                }
                ops.append(FileOperation(sourceURL: photo.url, destinationURL: destDir.appendingPathComponent(name)))
            }
        }
        return ops
    }

    static func displayRange(for album: Album, photos: [PhotoFile]) -> String {
        let ap = photosInAlbum(photos, album: album)
        guard let first = ap.first, let last = ap.last else { return "—" }
        if first.id == last.id { return first.originalFilename }
        return "\(first.originalFilename) — \(last.originalFilename)"
    }

    static func albumListTitle(for album: Album, config: AlbumNamingConfiguration, albumCount: Int, photos: [PhotoFile], albums: [Album]) -> String {
        if config.createAlbumFolders {
            return albumSubfolderName(
                forAlbumNumber: album.number,
                config: config,
                albumCount: albumCount,
                photos: photos,
                albums: albums
            )
        }
        return "\(album.number)"
    }
}
