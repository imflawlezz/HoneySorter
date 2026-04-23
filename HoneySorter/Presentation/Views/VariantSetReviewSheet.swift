import SwiftUI

struct VariantSetReviewSheet: View {
    @Bindable var viewModel: PhotoSorterViewModel

    private let thumbPixels: CGFloat = 160

    var body: some View {
        VStack(spacing: 12) {
            Text("Variant Sets")
                .font(.title2.weight(.semibold))

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach($viewModel.variantSetReviewGroups) { $group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Group (\(group.items.count))")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 220), spacing: 12, alignment: .top)],
                                alignment: .leading,
                                spacing: 12
                            ) {
                                ForEach($group.items) { $item in
                                    VariantSetReviewCell(item: $item, decodePixels: thumbPixels)
                                }
                            }
                        }
                        .padding(12)
                        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: 920, alignment: .center)
            }

            HStack {
                Text(viewModel.variantSetResultMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Button("Close") { viewModel.showVariantSetReview = false }
                    .keyboardShortcut(.cancelAction)
                Button {
                    viewModel.applyVariantSets()
                } label: {
                    Text("Apply")
                }
                .disabled(!viewModel.hasVariantSetCandidates)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 720, idealHeight: 520, maxHeight: 560)
    }
}

private struct VariantSetReviewCell: View {
    @Binding var item: PhotoSorterViewModel.VariantSetReviewItem
    let decodePixels: CGFloat

    @State private var image: NSImage?
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.low)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 180, maxHeight: 180)
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.quaternary)
                        .frame(width: 180, height: 180)
                }
            }
            .frame(width: 180, height: 180)
            .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Toggle("Include", isOn: $item.isIncluded)
                .toggleStyle(.checkbox)
                .font(.callout)

            Text(item.filename)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .onAppear { start() }
        .onDisappear { task?.cancel(); task = nil }
    }

    private func start() {
        guard image == nil else { return }
        task?.cancel()
        task = Task {
            let img = await ThumbnailCache.image(for: item.url, maxPixelSize: decodePixels)
            guard !Task.isCancelled else { return }
            await MainActor.run { image = img }
        }
    }
}

