import SwiftUI

struct RenameProgressView: View {
    let isRenaming: Bool

    var body: some View {
        if isRenaming {
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text("Processing…")
                    .font(.headline)
                Text("Please do not close the app or modify files in the folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(40)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 20)
        }
    }
}
