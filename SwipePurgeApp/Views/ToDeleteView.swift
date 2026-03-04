import SwiftUI
import UIKit
import Photos

struct ToDeleteView: View {
    @ObservedObject var viewModel: SwipeDeckViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isCommitting = false
    @State private var errorMessage: String?
    @State private var latestFirst = true
    @State private var inspectedAssetId: String?

    var body: some View {
        ZStack(alignment: .top) {
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

                    commitButton
                }
                .navigationTitle("To Delete")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            latestFirst.toggle()
                        } label: {
                            Image(systemName: latestFirst ? "arrow.up" : "arrow.down")
                                .font(.headline.weight(.semibold))
                        }
                        .accessibilityLabel(latestFirst ? "Latest first" : "Oldest first")
                    }
                }
                .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
                    Button("OK", role: .cancel) { errorMessage = nil }
                } message: {
                    Text(errorMessage ?? "")
                }
            }
            .blur(radius: isCommitting ? 8 : 0)
            .disabled(isCommitting)

            dragHandle
                .padding(.top, 8)
                .allowsHitTesting(false)

            if isCommitting {
                ZStack {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.large)
                        .tint(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .fullScreenCover(isPresented: Binding(get: { inspectedAssetId != nil }, set: { if !$0 { inspectedAssetId = nil } })) {
            if let assetId = inspectedAssetId {
                InspectorView(assetId: assetId,
                              metadataService: viewModel.metadataService,
                              gifService: viewModel.gifService,
                              onDismiss: {
                                  self.inspectedAssetId = nil
                              })
                    .ignoresSafeArea()
            }
        }
    }

    private var dragHandle: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 44, height: 5)
    }

    private var orderedDeletionIds: [String] {
        let ids = viewModel.deletionQueue.map(\.assetId)
        return latestFirst ? Array(ids.reversed()) : ids
    }

    private var commitButton: some View {
        Button {
            Task { await commit() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "trash.fill")
                Text("Commit Deletion")
                    .font(.headline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                ZStack {
                    Capsule()
                        .fill(.ultraThinMaterial)
                    Capsule()
                        .fill(viewModel.deletionSet.isEmpty ? Color.white.opacity(0.06) : Color.red.opacity(0.18))
                }
            }
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(viewModel.deletionSet.isEmpty ? 0.08 : 0.18), lineWidth: 1)
            }
            .foregroundStyle(viewModel.deletionSet.isEmpty ? Color.secondary : .white)
            .shadow(color: viewModel.deletionSet.isEmpty ? .clear : Color.red.opacity(0.18), radius: 12, x: 0, y: 6)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .disabled(viewModel.deletionSet.isEmpty || isCommitting)
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
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.22)) {
                    inspectedAssetId = assetId
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
