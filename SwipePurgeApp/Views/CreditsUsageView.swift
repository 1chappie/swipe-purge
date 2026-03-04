import SwiftUI

private let swipePurgeGitHubURL = URL(string: "https://github.com/1chappie/swipe-purge")!

struct CreditsUsageView: View {
    @ObservedObject var viewModel: SwipeDeckViewModel
    @ObservedObject var albumShortcutStore: AlbumShortcutStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerSection

                    NavigationLink {
                        HowToUseSettingsView()
                    } label: {
                        settingsCard(minHeight: settingsRowHeight) {
                            submenuRow("How To Use")
                        }
                    }
                    .buttonStyle(.plain)
                    .tint(.white)

                    NavigationLink {
                        AlbumShortcutSettingsView(store: albumShortcutStore)
                    } label: {
                        settingsCard(minHeight: settingsRowHeight) {
                            submenuRow("\"Add to Album\" Shortcuts")
                        }
                    }
                    .buttonStyle(.plain)
                    .tint(.white)

                    settingsCard(minHeight: settingsRowHeight) {
                        Toggle(isOn: includeHiddenBinding) {
                            sectionLabel("Include Hidden")
                        }
                        .tint(Color.white.opacity(0.32))
                    }

                    settingsCard(minHeight: settingsRowHeight) {
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
            .onAppear {
                albumShortcutStore.refreshAlbums()
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


    private var settingsRowHeight: CGFloat { 36 }

    private var includeHiddenBinding: Binding<Bool> {
        Binding(
            get: { albumShortcutStore.includeHidden },
            set: { albumShortcutStore.setIncludeHidden($0) }
        )
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
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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


private struct HowToUseSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                UsageContentView(showTitle: false, showGitHubLink: false, showHowToTitle: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
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
            .padding(20)
        }
        .navigationTitle("How To Use")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AlbumShortcutSettingsView: View {
    @ObservedObject var store: AlbumShortcutStore

    private let reorderAnimation = Animation.spring(response: 0.28, dampingFraction: 0.88)

    private var availableChoices: [AlbumShortcutChoice] {
        store.availableAlbums.filter { choice in
            !store.shortcuts.contains(where: { $0.albumId == choice.albumId })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summaryCard
                selectedShortcutsCard
                availableAlbumsCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle("\"Add to Album\" Shortcuts")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            store.refreshAlbums()
        }
    }

    private var summaryCard: some View {
        shortcutCard {
            (
                Text("You can quickly add an item to an Album by tapping the ")
                + Text(Image(systemName: "ellipsis"))
                + Text(" at the bottom of the main swiping area. However, you must first choose which albums you'd like to have shortcuts for by adding them to the list below.")
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var selectedShortcutsCard: some View {
        shortcutCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Text("Selected Albums")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)

                    Spacer(minLength: 8)

                    Text("\(store.shortcuts.count)/\(store.maxShortcuts)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.78))
                }

                if store.shortcuts.isEmpty {
                    Text("No shortcuts yet. Add albums below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(store.shortcuts) { shortcut in
                            shortcutRow(shortcut)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .scale(scale: 0.94).combined(with: .opacity)
                                ))
                        }
                    }
                    .animation(reorderAnimation, value: store.shortcuts.map(\.albumId))
                }
            }
        }
    }

    private var availableAlbumsCard: some View {
        shortcutCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Available Albums")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)

                if availableChoices.isEmpty {
                    Text("No additional albums available.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(availableChoices) { choice in
                            availableAlbumRow(choice)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .scale(scale: 0.94).combined(with: .opacity)
                                ))
                        }
                    }
                    .animation(reorderAnimation, value: store.shortcuts.map(\.albumId))
                }
            }
        }
    }

    private func shortcutRow(_ shortcut: AlbumShortcut) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 20, height: 20)
                .padding(6)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule()
                                .fill(Color.white.opacity(0.04))
                        }
                }
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
                .draggable(shortcut.albumId)

            Text(shortcut.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 12)

            shortcutIconButton(systemImage: "trash", tint: Color.red.opacity(0.16)) {
                withAnimation(reorderAnimation) {
                    store.removeShortcut(albumId: shortcut.albumId)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.03))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .dropDestination(for: String.self) { droppedAlbumIDs, _ in
            guard let droppedAlbumID = droppedAlbumIDs.first else { return false }
            withAnimation(reorderAnimation) {
                store.moveShortcut(albumId: droppedAlbumID, to: shortcut.albumId)
            }
            return true
        }
    }

    private func availableAlbumRow(_ choice: AlbumShortcutChoice) -> some View {
        HStack(spacing: 12) {
            Text(choice.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 12)

            shortcutIconButton(systemImage: "plus", isEnabled: !store.hasReachedLimit, tint: Color.green.opacity(0.14)) {
                withAnimation(reorderAnimation) {
                    store.addShortcut(albumId: choice.albumId)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.03))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func shortcutCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func shortcutIconButton(
        systemImage: String,
        isEnabled: Bool = true,
        tint: Color = Color.white.opacity(0.08),
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(isEnabled ? Color.white : Color.white.opacity(0.35))
                .frame(width: 30, height: 30)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Circle()
                                .fill(tint)
                        }
                }
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
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
