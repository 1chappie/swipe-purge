import SwiftUI

private let swipePurgeGitHubURL = URL(string: "https://github.com/1chappie/swipe-purge")!

struct CreditsUsageView: View {
    @ObservedObject var viewModel: SwipeDeckViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerSection

                    settingsCard(minHeight: 56) {
                        DisclosureGroup {
                            UsageContentView(showTitle: false, showGitHubLink: false, showHowToTitle: false)
                                .padding(.top, 8)
                        } label: {
                            sectionLabel("How To Use")
                        }
                        .tint(.white)
                    }

                    NavigationLink {
                        PlaceholderSettingsView(title: "\"Add to Album\" Shortcuts",
                                                message: "Shortcuts coming soon.")
                    } label: {
                        settingsCard(minHeight: 56) {
                            submenuRow("\"Add to Album\" Shortcuts")
                        }
                    }
                    .buttonStyle(.plain)
                    .tint(.white)

                    settingsCard(minHeight: 56) {
                        DisclosureGroup {
                            debugSection
                                .padding(.top, 8)
                        } label: {
                            sectionLabel("Stats and Debug")
                        }
                        .tint(.white)
                    }
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

    private var headerSection: some View {
        HStack(spacing: 12) {
            Text(appVersionText)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))

            Link(destination: swipePurgeGitHubURL) {
                Text("GitHub")
                    .underline()
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build, build != version {
            return "Version \(version) (\(build))"
        }
        return "Version \(version)"
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

    private func settingsCard<Content: View>(minHeight: CGFloat = 0, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
                .frame(minHeight: minHeight, alignment: .center)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.05))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
    }

    private func submenuRow(_ text: String) -> some View {
        HStack(spacing: 12) {
            sectionLabel(text)
            Spacer(minLength: 12)
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
        }
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
    let showGitHubLink: Bool
    let showHowToTitle: Bool

    init(showTitle: Bool, showGitHubLink: Bool = true, showHowToTitle: Bool = true) {
        self.showTitle = showTitle
        self.showGitHubLink = showGitHubLink
        self.showHowToTitle = showHowToTitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showTitle {
                Text("Swipe Purge")
                    .font(.largeTitle.weight(.bold))
            }

            if showGitHubLink {
                Link(destination: swipePurgeGitHubURL) {
                    Text("GitHub")
                        .underline()
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            if showHowToTitle {
                Text("How to Use")
                    .font(.title3.weight(.semibold))
            }

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

private struct PlaceholderSettingsView: View {
    let title: String
    let message: String

    var body: some View {
        ScrollView {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
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
