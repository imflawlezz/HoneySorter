import SwiftUI

struct PhotoGridView: View {
    @Bindable var viewModel: PhotoSorterViewModel

    private var cell: CGFloat { viewModel.gridThumbnailSize.cellSide }
    private var decodePixels: CGFloat { viewModel.gridThumbnailSize.thumbnailDecodeMaxPixelSize }

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: cell + 8), spacing: 8, alignment: .top),
                ],
                alignment: .center,
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
                            decodeMaxPixelSize: decodePixels
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Rename…") {
                            viewModel.photoPendingRename = photo
                        }
                        Divider()
                        Button("Move to Trash…", role: .destructive) {
                            Task { await viewModel.trashPhotos([photo]) }
                        }
                    }
                }
            }
            .padding()
        }
        .transaction { txn in
            txn.animation = nil
        }
        .scrollClipDisabled(false)
    }
}
