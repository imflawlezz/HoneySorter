import Foundation

enum SelectionState: Equatable {
    case idle
    case editing(anchorPhotoId: UUID, albumId: UUID)
}
