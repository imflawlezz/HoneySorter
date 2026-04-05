import SwiftUI

struct SingleFileRenameSheet: View {
    let photo: PhotoFile
    @Bindable var viewModel: PhotoSorterViewModel

    @State private var basename = ""
    @State private var didSeed = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Name", text: $basename)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .focused($nameFocused)
                .onSubmit {
                    Task { await viewModel.applyQuickRename(photo: photo, newBasename: basename) }
                }
                .onAppear {
                    guard !didSeed else { return }
                    didSeed = true
                    basename = (photo.originalFilename as NSString).deletingPathExtension
                    DispatchQueue.main.async {
                        nameFocused = true
                    }
                }

            HStack {
                Spacer()
                Button("Cancel") {
                    viewModel.photoPendingRename = nil
                }
                .keyboardShortcut(.escape, modifiers: [])
                Button("Rename") {
                    Task { await viewModel.applyQuickRename(photo: photo, newBasename: basename) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isRenaming)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
