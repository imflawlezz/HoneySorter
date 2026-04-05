import SwiftUI

enum AlbumPalette {
    static let colors: [Color] = [
        .blue, .green, .orange, .purple, .pink, .teal, .indigo, .mint, .cyan, .yellow,
    ]

    static func color(forAlbumNumber number: Int) -> Color {
        let idx = max(0, number - 1)
        return colors[idx % colors.count]
    }
}
