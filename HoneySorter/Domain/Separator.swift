import Foundation

enum Separator: String, CaseIterable, Identifiable {
    case underscore = "_"
    case dash = "-"
    case dot = "."
    var id: String { rawValue }
    var label: String {
        switch self {
        case .underscore: return "Underscore (_)"
        case .dash: return "Dash (-)"
        case .dot: return "Dot (.)"
        }
    }
}
