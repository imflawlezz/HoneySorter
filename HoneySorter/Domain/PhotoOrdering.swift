import Foundation

enum PhotoOrdering: String, CaseIterable, Identifiable {
    case filename = "Filename"
    case creationDate = "Creation date"
    case modificationDate = "Modification date"

    var id: String { rawValue }
    var label: String { rawValue }
}

