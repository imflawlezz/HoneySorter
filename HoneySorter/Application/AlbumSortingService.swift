import Foundation

enum AlbumSortingService {

    nonisolated static func photosInAlbum(_ photos: [PhotoFile], album: Album) -> [PhotoFile] {
        if let memberPaths = album.memberPaths {
            let set = Set(memberPaths)
            let picked = photos.filter { set.contains($0.url.path) }
            if album.isReversed { return Array(picked.reversed()) }
            return picked
        }
        let lo = album.startSortIndex
        let hi = album.endSortIndex
        guard lo >= 0, hi < photos.count, lo <= hi else { return [] }
        if album.isReversed {
            return Array(photos[lo...hi].reversed())
        }
        return Array(photos[lo...hi])
    }

    nonisolated static func maxAlbumDigits(startingAlbumNumber: Int, albumCount: Int) -> Int {
        let last = startingAlbumNumber + max(albumCount, 1) - 1
        return String(last).count
    }

    nonisolated static func maxIndexDigitsFromAlbums(_ albums: [Album]) -> Int {
        let maxPhotos = albums.map(\.estimatedCount).max() ?? 1
        return String(maxPhotos).count
    }

    nonisolated static func padWidths(config: AlbumNamingConfiguration, albumCount: Int, albums: [Album]) -> (maxA: Int, maxI: Int) {
        let maxA = max(maxAlbumDigits(startingAlbumNumber: config.startingAlbumNumber, albumCount: albumCount), 2)
        let maxI = max(maxIndexDigitsFromAlbums(albums), 2)
        return (maxA, maxI)
    }

    nonisolated static func formatFilename(
        albumNumber: Int,
        index: Int,
        ext: String,
        config: AlbumNamingConfiguration,
        maxAlbumPadWidth: Int,
        maxIndexPadWidth: Int
    ) -> String {
        let sep = config.separator.rawValue
        let a = config.zeroPadding ? String(format: "%0\(maxAlbumPadWidth)d", albumNumber) : "\(albumNumber)"
        let i = config.zeroPadding ? String(format: "%0\(maxIndexPadWidth)d", index) : "\(index)"
        let trimmedPrefix = config.photoIndexPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(a)\(sep)\(trimmedPrefix)\(i).\(ext)"
    }

    nonisolated static func albumSubfolderName(
        forAlbumNumber albumNumber: Int,
        config: AlbumNamingConfiguration,
        albumCount: Int
    ) -> String {
        let maxA = max(maxAlbumDigits(startingAlbumNumber: config.startingAlbumNumber, albumCount: albumCount), 2)
        let a = config.zeroPadding ? String(format: "%0\(maxA)d", albumNumber) : "\(albumNumber)"
        let trimmed = config.albumFolderPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return a }
        return "\(trimmed)\(a)"
    }

    nonisolated static func filenamePreview(config: AlbumNamingConfiguration, albumCount: Int, albums: [Album]) -> String {
        let (maxA, maxI) = padWidths(config: config, albumCount: albumCount, albums: albums)
        let sep = config.separator.rawValue
        let a = config.zeroPadding ? String(format: "%0\(maxA)d", config.startingAlbumNumber) : "\(config.startingAlbumNumber)"
        let i = config.zeroPadding ? String(format: "%0\(maxI)d", 1) : "1"
        let trimmedPrefix = config.photoIndexPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        var name = "\(a)\(sep)\(trimmedPrefix)\(i).jpg"
        if config.createAlbumFolders {
            let folder = albumSubfolderName(
                forAlbumNumber: config.startingAlbumNumber,
                config: config,
                albumCount: albumCount
            )
            name = "\(folder)/\(name)"
        }
        return name
    }

    nonisolated static func assignmentCaches(
        photos: [PhotoFile],
        albums: [Album],
        config: AlbumNamingConfiguration
    ) -> (albumByPhotoId: [UUID: Album], newFilenameByPhotoId: [UUID: String]) {
        var albumMap: [UUID: Album] = [:]
        var nameMap: [UUID: String] = [:]
        let count = albums.count
        let (maxA, maxI) = padWidths(config: config, albumCount: count, albums: albums)
        let pathToPhoto: [String: PhotoFile] = Dictionary(uniqueKeysWithValues: photos.map { ($0.url.path, $0) })

        for album in albums {
            let inAlbum: [PhotoFile]
            if let memberPaths = album.memberPaths {
                inAlbum = memberPaths.compactMap { pathToPhoto[$0] }
            } else {
                let lo = max(0, min(album.startSortIndex, photos.count - 1))
                let hi = max(0, min(album.endSortIndex, photos.count - 1))
                if lo <= hi {
                    inAlbum = album.isReversed ? Array(photos[lo...hi].reversed()) : Array(photos[lo...hi])
                } else {
                    inAlbum = []
                }
            }

            for (idx, p) in inAlbum.enumerated() {
                albumMap[p.id] = album
                nameMap[p.id] = formatFilename(
                    albumNumber: album.number,
                    index: idx + 1,
                    ext: p.fileExtension,
                    config: config,
                    maxAlbumPadWidth: maxA,
                    maxIndexPadWidth: maxI
                )
            }
        }
        return (albumMap, nameMap)
    }

    nonisolated static func renumberedAlbums(_ albums: [Album], startingAlbumNumber: Int) -> [Album] {
        let sorted = albums.sorted { $0.startSortIndex < $1.startSortIndex }
        return sorted.enumerated().map {
            Album(
                id: $0.element.id,
                number: startingAlbumNumber + $0.offset,
                startSortIndex: $0.element.startSortIndex,
                endSortIndex: $0.element.endSortIndex,
                isReversed: $0.element.isReversed,
                memberPaths: $0.element.memberPaths
            )
        }
    }

    nonisolated static func remapAlbumsAfterPhotoListChange(
        previousPhotos: [PhotoFile],
        previousAlbums: [Album],
        nextPhotos: [PhotoFile],
        startingAlbumNumber: Int
    ) -> [Album] {
        guard !previousAlbums.isEmpty, !nextPhotos.isEmpty else { return [] }

        let pathToSortIndex: [String: Int] = Dictionary(uniqueKeysWithValues: nextPhotos.map { ($0.url.path, $0.sortIndex) })

        var remapped: [Album] = []
        for album in previousAlbums.sorted(by: { $0.startSortIndex < $1.startSortIndex }) {
            if let memberPaths = album.memberPaths {
                let kept = memberPaths.filter { pathToSortIndex[$0] != nil }
                let indices = kept.compactMap { pathToSortIndex[$0] }
                guard !indices.isEmpty else { continue }
                let lo = indices.min() ?? 0
                let hi = indices.max() ?? lo
                remapped.append(
                    Album(
                        id: album.id,
                        number: album.number,
                        startSortIndex: lo,
                        endSortIndex: hi,
                        isReversed: album.isReversed,
                        memberPaths: kept
                    )
                )
                continue
            }
            let paths = Set(photosInAlbum(previousPhotos, album: album).map(\.url.path))
            let indices = paths.compactMap { pathToSortIndex[$0] }
            guard !indices.isEmpty else { continue }
            let uniqueSorted = Array(Set(indices)).sorted()
            guard let (lo, hi) = largestContiguousIndexRun(uniqueSorted) else { continue }
            guard lo >= 0, hi < nextPhotos.count, lo <= hi else { continue }

            remapped.append(
                Album(
                    id: album.id,
                    number: album.number,
                    startSortIndex: lo,
                    endSortIndex: hi,
                    isReversed: album.isReversed
                )
            )
        }

        return renumberedAlbums(remapped.sorted { $0.startSortIndex < $1.startSortIndex }, startingAlbumNumber: startingAlbumNumber)
    }

    nonisolated private static func largestContiguousIndexRun(_ sortedUnique: [Int]) -> (Int, Int)? {
        guard let first = sortedUnique.first else { return nil }
        var bestLo = first
        var bestHi = first
        var curLo = first
        var curHi = first

        for x in sortedUnique.dropFirst() {
            if x == curHi + 1 {
                curHi = x
            } else {
                if curHi - curLo > bestHi - bestLo {
                    bestLo = curLo
                    bestHi = curHi
                }
                curLo = x
                curHi = x
            }
        }
        if curHi - curLo > bestHi - bestLo {
            bestLo = curLo
            bestHi = curHi
        }
        return (bestLo, bestHi)
    }

    nonisolated static func contiguousIndexRuns(_ sortedUnique: [Int]) -> [(lo: Int, hi: Int)] {
        guard let first = sortedUnique.first else { return [] }
        var runs: [(lo: Int, hi: Int)] = []
        var curLo = first
        var curHi = first
        for x in sortedUnique.dropFirst() {
            if x == curHi + 1 {
                curHi = x
            } else {
                runs.append((curLo, curHi))
                curLo = x
                curHi = x
            }
        }
        runs.append((curLo, curHi))
        return runs
    }

    nonisolated static func nextAlbumNumber(startingAlbumNumber: Int, albumCount: Int) -> Int {
        startingAlbumNumber + albumCount
    }

    enum RangeSelectionError: String, Error {
        case photoAlreadyInAlbum = "This photo is already part of an album. Remove that album first to reassign it."
        case rangeHasAssignedPhotos = "Some photos in this range are already assigned to another album."
    }

    nonisolated static func tryAppendAlbumFromRange(
        startPhoto: PhotoFile,
        endPhoto: PhotoFile,
        photos: [PhotoFile],
        albumByPhotoId: [UUID: Album],
        nextAlbumNumber: Int
    ) -> Result<Album, RangeSelectionError> {
        let lo = min(startPhoto.sortIndex, endPhoto.sortIndex)
        let hi = max(startPhoto.sortIndex, endPhoto.sortIndex)
        let isReversed = startPhoto.sortIndex > endPhoto.sortIndex
        let conflicts = photos[lo...hi].contains { albumByPhotoId[$0.id] != nil }
        if conflicts {
            return .failure(.rangeHasAssignedPhotos)
        }
        return .success(Album(number: nextAlbumNumber, startSortIndex: lo, endSortIndex: hi, isReversed: isReversed))
    }

    nonisolated static func buildRenameOperations(
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
        let (maxA, maxI) = padWidths(config: config, albumCount: count, albums: albums)
        var ops: [FileOperation] = []
        for album in albums.sorted(by: { $0.number < $1.number }) {
            let albumPhotos = photosInAlbum(photos, album: album)
            for (order, photo) in albumPhotos.enumerated() {
                let name = formatFilename(
                    albumNumber: album.number,
                    index: order + 1,
                    ext: photo.fileExtension,
                    config: config,
                    maxAlbumPadWidth: maxA,
                    maxIndexPadWidth: maxI
                )
                var destDir = baseDir
                if config.createAlbumFolders {
                    let folder = albumSubfolderName(
                        forAlbumNumber: album.number,
                        config: config,
                        albumCount: count
                    )
                    destDir = baseDir.appendingPathComponent(folder)
                }
                ops.append(FileOperation(sourceURL: photo.url, destinationURL: destDir.appendingPathComponent(name)))
            }
        }
        return ops
    }

    nonisolated static func displayRange(for album: Album, photos: [PhotoFile]) -> String {
        let inAlbum = photosInAlbum(photos, album: album)
        guard let first = inAlbum.first else { return "—" }
        let last = inAlbum.last ?? first
        if first.id == last.id { return first.originalFilename }
        return "\(first.originalFilename) — \(last.originalFilename)"
    }

    nonisolated static func albumListTitle(for album: Album, config: AlbumNamingConfiguration, albumCount: Int) -> String {
        if config.createAlbumFolders {
            return albumSubfolderName(
                forAlbumNumber: album.number,
                config: config,
                albumCount: albumCount
            )
        }
        return "\(album.number)"
    }
}
