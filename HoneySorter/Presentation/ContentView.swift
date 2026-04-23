import AppKit
import SwiftUI

struct ContentView: View {
    @State private var viewModel = PhotoSorterViewModel()

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationSplitView {
            AlbumSidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 560)
        } detail: {
            ZStack {
                if viewModel.photos.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    PhotoGridView(viewModel: viewModel)
                }
                RenameProgressView(isRenaming: viewModel.isRenaming)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if case .editing = viewModel.selectionState {
                    Button("Cancel") { viewModel.cancelSelection() }
                        .keyboardShortcut(.escape, modifiers: [])
                        .help("Cancel the current album selection")
                }
            }

            ToolbarItem(placement: .principal) {
                FolderPathToolbarBubble(
                    pathDisplay: directoryPathToolbarLabel,
                    pathIsPlaceholder: viewModel.directoryURL == nil,
                    onChooseFolder: { viewModel.openDirectory() }
                )
            }

            ToolbarItemGroup(placement: .automatic) {
                Menu {
                    ForEach(PhotoOrdering.allCases) { ordering in
                        Button {
                            viewModel.photoOrdering = ordering
                        } label: {
                            HStack {
                                Text(ordering.label)
                                Spacer(minLength: 12)
                                if viewModel.photoOrdering == ordering {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(viewModel.photoOrdering.label)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .help("How photos are ordered in the grid (changing this resets album selections).")

                Picker(selection: $viewModel.gridThumbnailSize) {
                    ForEach(GridThumbnailSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                } label: {
                    Label("Thumbnail size", systemImage: "photo.on.rectangle.angled")
                }
                .pickerStyle(.menu)
                .help("Grid cell size")

                Toggle(isOn: $viewModel.showUnassignedOnly) {
                    Label("Unassigned only", systemImage: "line.3.horizontal.decrease.circle")
                }
                .toggleStyle(.button)
                .help("Show only photos not in an album")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.scanForDuplicates() }
                } label: {
                    if viewModel.isFindingDuplicates {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "document.on.trash")
                    }
                }
                .disabled(viewModel.photos.isEmpty || viewModel.isFindingDuplicates)
                .help("Find duplicate photos")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.showVariantSetStrictnessDialog = true
                } label: {
                    if viewModel.isFindingVariantSets {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "sparkles.2")
                    }
                }
                .disabled(viewModel.photos.isEmpty || viewModel.isFindingVariantSets)
                .help("Group variant sets into albums")
            }

            ToolbarItem(placement: .primaryAction) {
                if viewModel.hasUndoManifest && !viewModel.duplicateMode {
                    Button { viewModel.showUndoConfirmation = true } label: {
                        Label("Revert", systemImage: "arrow.uturn.backward")
                    }
                    .help("Undo the most recent rename and restore original filenames")
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button { viewModel.showConfirmation = true } label: {
                    Image(systemName: viewModel.duplicateMode ? "document.on.trash.fill" : "checkmark.circle.fill")
                        .font(.body.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                }
                .disabled(!viewModel.canRename)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help(viewModel.duplicateMode
                    ? "Copy and rename all assigned photos to the output location"
                    : "Rename all assigned photos in place"
                )
                .accessibilityLabel(viewModel.duplicateMode ? "Copy All" : "Rename All")
            }
        }
        .overlay(alignment: .bottom) { statusBar }
        .background(WindowTitleUpdater())
        .sheet(item: $viewModel.photoPendingRename) { photo in
            SingleFileRenameSheet(photo: photo, viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showDuplicateReview) {
            DuplicateReviewSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showVariantSetReview) {
            VariantSetReviewSheet(viewModel: viewModel)
        }
        .alert("No duplicates found", isPresented: $viewModel.showNoDuplicates) {
            Button("OK", role: .cancel) {}
        }
        .alert("No variant sets found", isPresented: $viewModel.showNoVariantSets) {
            Button("OK", role: .cancel) {}
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .confirmationDialog("Variant set strictness", isPresented: $viewModel.showVariantSetStrictnessDialog, titleVisibility: .visible) {
            ForEach(VariantSetStrictness.allCases) { s in
                Button(s.rawValue) {
                    Task { await viewModel.scanForVariantSets(strictness: s) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            viewModel.duplicateMode ? "Confirm Copy" : "Confirm Rename",
            isPresented: $viewModel.showConfirmation
        ) {
            Button(viewModel.duplicateMode ? "Copy" : "Rename", role: .destructive) {
                Task { await viewModel.executeRename() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let count = viewModel.albums.flatMap { viewModel.photosInAlbum($0) }.count
            if viewModel.duplicateMode {
                Text("\(count) file(s) will be copied to \(viewModel.outputDisplayPath) across \(viewModel.albums.count) album(s). Originals will not be modified.")
            } else {
                Text("\(count) file(s) across \(viewModel.albums.count) album(s) will be renamed. A revert record will be saved automatically.")
            }
        }
        .alert("Revert Changes", isPresented: $viewModel.showUndoConfirmation) {
            Button("Revert", role: .destructive) { Task { await viewModel.executeUndo() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All renamed files will be restored to their original names.")
        }
        .alert("Done", isPresented: $viewModel.showComplete) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.resultMessage)
        }
    }

    private var directoryPathToolbarLabel: String {
        viewModel.directoryURL?.path(percentEncoded: false) ?? "No folder selected"
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No Folder Selected")
                .font(.title2.weight(.medium))
            Text("Choose a folder to load and organize your photos into albums.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { viewModel.openDirectory() } label: {
                Label("Select Folder", systemImage: "folder")
                    .padding(.horizontal, 8)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .padding(40)
    }

    private var statusBar: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
            Text(viewModel.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
            if viewModel.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .padding(.leading, 6)
            }
            Spacer()
            if !viewModel.photos.isEmpty {
                if viewModel.showUnassignedOnly {
                    Text("\(viewModel.photosForGrid.count) of \(viewModel.photos.count) shown")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("\(viewModel.photos.count) photos")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var statusIcon: String {
        if viewModel.isRenaming { return "arrow.triangle.2.circlepath" }
        if viewModel.isLoading { return "hourglass" }
        switch viewModel.selectionState {
        case .idle:
            return viewModel.canRename && viewModel.unassignedCount == 0 ? "checkmark.circle" : "hand.point.up"
        case .editing:
            return "hand.point.right"
        }
    }

    private var statusColor: Color {
        if viewModel.isRenaming { return .orange }
        switch viewModel.selectionState {
        case .idle:
            return viewModel.canRename && viewModel.unassignedCount == 0 ? .green : .secondary
        case .editing:
            return .accentColor
        }
    }
}

private struct FolderPathToolbarBubble: View {
    var pathDisplay: String
    var pathIsPlaceholder: Bool
    var onChooseFolder: () -> Void

    private let textFont = Font.system(size: 13, weight: .regular)

    var body: some View {
        Button(action: onChooseFolder) {
            HStack(alignment: .center, spacing: 8) {
                Text(pathDisplay)
                    .font(textFont)
                    .foregroundStyle(pathIsPlaceholder
                        ? Color(nsColor: .tertiaryLabelColor)
                        : Color(nsColor: .labelColor))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.leading)
                    .frame(minWidth: 200, maxWidth: 480, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                Image(systemName: "folder")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .frame(width: 26, height: 24)
                    .accessibilityHidden(true)
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .fill(Color.black.opacity(0.12))
                    }
            }
            .overlay {
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
            }
            .shadow(color: Color.black.opacity(0.12), radius: 0, y: 0.5)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Choose a folder containing photos to organize (⌘O)")
        .keyboardShortcut("o", modifiers: .command)
        .accessibilityLabel("Choose folder")
        .accessibilityValue(pathDisplay)
    }
}

private struct WindowTitleUpdater: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let apply: () -> Void = {
            guard let w = nsView.window else { return }
            w.title = "HoneySorter"
            w.subtitle = ""
        }
        if nsView.window != nil {
            apply()
            DispatchQueue.main.async(execute: apply)
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }
}
