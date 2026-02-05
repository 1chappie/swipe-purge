import SwiftUI

struct CreditsUsageView: View {
    @ObservedObject var viewModel: SwipeDeckViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    UsageContentView(showTitle: false)

                    DisclosureGroup {
                        debugSection
                    } label: {
                        Text("Debug")
                            .font(.title3.weight(.semibold)).foregroundStyle(.white)
                    }
                    .font(.subheadline)
                }
                .padding(20)
            }
            .navigationTitle("Swipe Purge")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DebugLine(label: "Assets", value: "\(viewModel.assetIds.count)")
            DebugLine(label: "Current Index", value: currentIndexText)
            DebugLine(label: "Current Asset", value: viewModel.currentAssetId ?? "N/A")
            DebugLine(label: "Saved Cursor ID", value: viewModel.savedCursorAssetId ?? "N/A")
            DebugLine(label: "Saved Cursor Date", value: dateString(viewModel.savedCursorCreationDate))
            DebugLine(label: "Deletion Queue", value: "\(viewModel.deletionSet.count)")
            DebugLine(label: "Total Deleted", value: "\(viewModel.totalDeletedCount)")
            DebugLine(label: "Metadata Cache", value: "\(viewModel.metadataService.cacheCount)")
            DebugLine(label: "Location Cache", value: "\(viewModel.metadataService.locationCacheCount)")
            DebugLine(label: "Filename Cache", value: "\(viewModel.metadataService.fileNameCacheCount)")
            DebugLine(label: "Album Cache", value: "\(viewModel.albumTagService.cacheCount)")
            DebugLine(label: "Thumb Cache (mem)", value: "\(viewModel.thumbnailService.memoryCacheCount)")
            DebugLine(label: "Thumb Cache (disk)", value: "\(viewModel.thumbnailService.diskCacheCount())")

            if !viewModel.deletionSet.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Deletion IDs")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(viewModel.deletionSet.sorted(), id: \.self) { id in
                        Text(id)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var currentIndexText: String {
        let total = viewModel.assetIds.count
        let current = total == 0 ? 0 : min(viewModel.currentIndex + 1, total)
        return "\(current) / \(total)"
    }

    private func dateString(_ date: Date?) -> String {
        guard let date else { return "N/A" }
        return Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

struct UsageContentView: View {
    let showTitle: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showTitle {
                Text("Swipe Purge")
                    .font(.largeTitle.weight(.bold))
            }

            Text("Link to GitHub")
                .foregroundStyle(.blue)

            Text("How to Use")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                usageRow(icon: "arrow.left", icon2: "trash", text: "Swipe left to mark a photo for deletion.")
                usageRow(icon: "arrow.right", icon2: "checkmark", text: "Swipe right to keep a photo.")
                usageRow(icon: "checkmark.circle", text: "Commit Deletion in the \"To Delete\" panel.")
                usageRow(text: "Note: Deleted items will appear in the \"Recently Deleted\" folder of your Photo Library.")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private func usageRow(icon: String? = nil, icon2: String? = nil, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let icon, !icon.isEmpty {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 18)
            }
            if let icon2, !icon2.isEmpty {
                Image(systemName: icon2)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 18)
            }
            Text(text)
        }
    }
}

private struct DebugLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label + ":")
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.caption.monospaced())
        }
    }
}
