import Foundation

struct AlbumNamingConfiguration: Equatable {
    var separator: Separator
    var zeroPadding: Bool
    var startingAlbumNumber: Int
    var albumFolderPrefix: String
    var createAlbumFolders: Bool
}
