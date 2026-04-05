import Foundation

enum SelectionState: Equatable {
    case idle
    case startSelected(UUID)
}
