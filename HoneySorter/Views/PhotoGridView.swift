import SwiftUI

struct PhotoGridView: View {
    @Bindable var viewModel: PhotoSorterViewModel

    private var cell: CGFloat { viewModel.gridThumbnailSize.cellSide }
    private var pixel: CGFloat { viewModel.gridThumbnailSize.thumbnailPixelSize }

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: cell + 8, maximum: cell + 16), spacing: 8)],
                spacing: 12
            ) {
                ForEach(viewModel.photosForGrid) { photo in
                    let album = viewModel.albumForPhoto(photo)
                    let isStart: Bool = {
                        if case .startSelected(let id) = viewModel.selectionState { return id == photo.id }
                        return false
                    }()

                    Button {
                        viewModel.selectPhoto(photo)
                    } label: {
                        PhotoThumbnailView(
                            photo: photo,
                            album: album,
                            albumColor: album.map { viewModel.colorForAlbum($0) },
                            isStartSelected: isStart,
                            newName: viewModel.newFilename(for: photo),
                            cellSide: cell,
                            thumbnailPixelSize: pixel
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Rename…") {
                            viewModel.photoPendingRename = photo
                        }
                    }
                }
            }
            .padding()
        }
    }
}
