import SwiftUI
import UIKit
import Photos

struct ToDeleteView: View {
    @ObservedObject var viewModel: SwipeDeckViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isCommitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(orderedDeletionIds, id: \.self) { id in
                            deletionRow(assetId: id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                }

                Divider()

                Button {
                    Task { await commit() }
                } label: {
                    HStack {
                        if isCommitting { ProgressView() }
                        Text("Commit Deletion")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.deletionSet.isEmpty ? Color.gray.opacity(0.3) : Color.red)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding()
                }
                .disabled(viewModel.deletionSet.isEmpty || isCommitting)
            }
            .navigationTitle("To Delete")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var orderedDeletionIds: [String] {
        viewModel.assetIds.filter { viewModel.deletionSet.contains($0) }
    }

    private func commit() async {
        isCommitting = true
        let result = await viewModel.commitDeletion()
        isCommitting = false

        switch result {
        case .success:
            dismiss()
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func deletionRow(assetId: String) -> some View {
        let metadata = viewModel.metadataService.metadata(assetId: assetId)
        return HStack(spacing: 12) {
            ZStack {
                AssetThumbnailView(assetId: assetId,
                                   targetSize: CGSize(width: 200, height: 200),
                                   thumbnailService: viewModel.thumbnailService,
                                   fill: true,
                                   deliveryMode: .fastFormat)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if metadata?.mediaType == .video {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(rowTitle(metadata))
                    .font(.headline)
                Text(rowSubtitle(metadata))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.toggleDelete(assetId: assetId)
                }
            } label: {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.2), value: viewModel.deletionSet)
    }

    private func rowTitle(_ metadata: AssetMetadata?) -> String {
        guard let metadata else { return "Unknown Photo" }
        guard let date = metadata.creationDate else { return "Unknown Date" }
        return Self.dateFormatter.string(from: date)
    }

    private func rowSubtitle(_ metadata: AssetMetadata?) -> String {
        guard let metadata else { return "Details unavailable" }
        if metadata.mediaType == .video {
            return "Video"
        }
        if metadata.mediaSubtypes.contains(.photoLive) { return "Live Photo" }
        if metadata.mediaSubtypes.contains(.photoScreenshot) { return "Screenshot" }
        return "Photo"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
