import SwiftUI
import PhotosUI

struct ImagePicker: View {
    @Binding var data: Data?
    @Environment(\.dismiss) private var dismiss
    @State private var selection: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $selection, matching: .images) {
            Text("Choose Image")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: selection) { _ in load() }
    }

    private func load() {
        guard let item = selection else { return }
        Task {
            if let d = try? await item.loadTransferable(type: Data.self) {
                await MainActor.run {
                    data = d
                    dismiss()
                }
            }
        }
    }
}
