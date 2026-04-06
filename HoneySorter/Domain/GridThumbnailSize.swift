import SwiftUI

enum GridThumbnailSize: String, CaseIterable, Identifiable {
    case small, medium, large, extraLarge
    var id: String { rawValue }
    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }
    var cellSide: CGFloat {
        switch self {
        case .small: return 96
        case .medium: return 120
        case .large: return 152
        case .extraLarge: return 200
        }
    }

    var thumbnailDecodeMaxPixelSize: CGFloat {
        let raw = cellSide * 1.25
        return min(384, max(72, ceil(raw)))
    }
}
