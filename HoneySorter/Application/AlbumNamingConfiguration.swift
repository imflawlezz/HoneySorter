import Foundation

struct AlbumNamingConfiguration: Equatable {
    var separator: Separator
    var zeroPadding: Bool
    var startingAlbumNumber: Int
    var photoIndexPrefix: String
    var albumFolderPrefix: String
    var createAlbumFolders: Bool
}
