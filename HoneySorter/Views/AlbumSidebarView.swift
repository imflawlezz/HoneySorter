import SwiftUI

struct AlbumSidebarView: View {
    @Bindable var viewModel: PhotoSorterViewModel

    var body: some View {
        List {
            namingSection
            outputSection

            if viewModel.albums.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Albums Yet", systemImage: "rectangle.stack")
                    } description: {
                        VStack(alignment: .center, spacing: 10) {
                            Text("Click two photos to set an album range.")
                            Text("Right‑click a thumbnail, then choose Rename.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else {
                Section("Albums (\(viewModel.albums.count))") {
                    ForEach(viewModel.albums) { album in
                        albumRow(album)
                    }
                }
                Section {
                    Button(role: .destructive) { viewModel.removeAllAlbums() } label: {
                        Label("Clear All Albums", systemImage: "trash")
                    }
                    .help("Remove all album assignments and start over.")
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var namingSection: some View {
        Section {
            HStack {
                Text("Start Album Index")
                Spacer()
                TextField("1", value: $viewModel.startingAlbumNumber, format: .number)
                    .frame(width: 50)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                Stepper("", value: $viewModel.startingAlbumNumber, in: 1...9999).labelsHidden()
            }
            .help("First album’s number (1 or higher). Increase to continue from a previous session.")

            Picker("Separator", selection: $viewModel.separator) {
                ForEach(Separator.allCases) { sep in
                    Text(sep.label).tag(sep)
                }
            }
            .help("Character placed between the album number and photo index in the filename.")

            Toggle("Zero Padding", isOn: $viewModel.zeroPadding)
                .help("Pad numbers with leading zeros for consistent sorting (e.g. 01_01 instead of 1_1).")

            HStack {
                Text("Preview")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(viewModel.filenamePreview)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Naming")
        }
    }

    @ViewBuilder
    private var outputSection: some View {
        Section {
            Toggle("Create Album Folders", isOn: $viewModel.createAlbumFolders)
                .help("Place each album's photos into a separate subfolder.")

            if viewModel.createAlbumFolders {
                HStack {
                    Text("Folder prefix")
                    Spacer()
                    TextField("Optional (e.g. Album_)", text: $viewModel.albumFolderPrefix)
                        .frame(minWidth: 120)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                }
                .help("Optional text before the album index in each subfolder name. Empty uses only the number. No extra character is inserted for you.")
            }

            Toggle("Copy to Separate Location", isOn: $viewModel.duplicateMode)
                .help("Copy files instead of renaming in place. Originals remain untouched.")

            if viewModel.duplicateMode {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Output")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(viewModel.outputDisplayPath)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    Spacer()
                    Button("Choose…") { viewModel.selectOutputDirectory() }
                        .controlSize(.small)
                }
                .help("Folder where renamed copies will be saved. Defaults to a 'Sorted' subfolder.")
            }
        } header: {
            Text("Output")
        }
    }

    @ViewBuilder
    private func albumRow(_ album: Album) -> some View {
        let color = viewModel.colorForAlbum(album)
        let count = viewModel.photosInAlbum(album).count

        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.albumListTitle(for: album))
                    .font(.headline)
                Text("\(count) photo\(count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
                Text(viewModel.displayRange(for: album))
                    .font(.caption2).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }

            Spacer()

            Button { viewModel.removeAlbum(album) } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove this album assignment")
        }
        .padding(.vertical, 2)
    }
}
