import AppKit
import SwiftUI

struct PhotoThumbnailView: View {
    let photo: PhotoFile
    let album: Album?
    let albumColor: Color?
    let isStartSelected: Bool
    let newName: String?
    let cellSide: CGFloat
    let thumbnailPixelSize: CGFloat

    @State private var loadedImage: NSImage?
    @State private var loadTask: Task<Void, Never>?

    private var rimColor: Color {
        if isStartSelected { return Color.accentColor }
        if album != nil { return albumColor ?? .accentColor }
        return .clear
    }

    private var rimWidth: CGFloat {
        if isStartSelected { return 3 }
        if album != nil { return 2 }
        return 0
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if let loadedImage {
                    Image(nsImage: loadedImage)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: cellSide, maxHeight: cellSide)
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.quaternary)
                        .frame(width: cellSide, height: cellSide)
                }

                if let albumColor {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(albumColor.opacity(0.2))
                        .frame(width: cellSide, height: cellSide)

                    if let album {
                        VStack {
                            HStack {
                                Spacer()
                                Text("\(album.number)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(albumColor, in: RoundedRectangle(cornerRadius: 4))
                            }
                            Spacer()
                        }
                        .frame(width: cellSide, height: cellSide)
                        .padding(4)
                    }
                }

                if rimWidth > 0 {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(rimColor, lineWidth: rimWidth)
                }
            }
            .frame(width: cellSide, height: cellSide)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(spacing: 1) {
                Text(photo.originalFilename)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let newName {
                    Text("→ \(newName)")
                        .font(.caption2)
                        .foregroundStyle(albumColor ?? .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .frame(width: cellSide + 8)
        .contentShape(Rectangle())
        .onAppear { startLoad() }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
        .onChange(of: thumbnailPixelSize) { _, _ in
            loadedImage = nil
            startLoad()
        }
    }

    private func startLoad() {
        guard loadedImage == nil else { return }
        loadTask?.cancel()
        loadTask = Task {
            let image = await ThumbnailCache.image(for: photo.url, maxPixelSize: thumbnailPixelSize)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                loadedImage = image
            }
        }
    }
}
