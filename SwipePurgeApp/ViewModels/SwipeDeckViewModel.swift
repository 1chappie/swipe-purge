import Foundation
import Photos
import SwiftData
import SwiftUI
import Combine

@MainActor
final class SwipeDeckViewModel: ObservableObject {
    enum SwipeAction {
        case keep
        case delete
        case unmarkDelete
    }

    struct UndoAction {
        let assetId: String
        let action: SwipeAction
    }

    @Published private(set) var assetIds: [String] = []
    @Published private(set) var monthSections: [MonthSection] = []
    @Published private(set) var deletionSet: Set<String> = []
    @Published var currentIndex: Int = 0
    @Published var isLoading: Bool = true
    @Published var errorMessage: String?
    @Published var commitToastMessage: String?
    @Published private var refreshToken = UUID()

    private var idToIndex: [String: Int] = [:]
    private var undoStack: [UndoAction] = []
    private let modelContext: ModelContext
    private var appState: AppState?

    let thumbnailService = ThumbnailService()
    let albumTagService = AlbumTagService()
    let metadataService = MetadataService()
    let gifService = GIFService()
    private let deletionService = DeletionService()
    private let assetRepository = AssetRepository()

    private let prefetchWindow = 20
    private let prefetchSize = CGSize(width: 900, height: 900)

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    var currentAssetId: String? {
        guard assetIds.indices.contains(currentIndex) else { return nil }
        return assetIds[currentIndex]
    }

    var savedCursorAssetId: String? { appState?.cursorAssetId }
    var savedCursorCreationDate: Date? { appState?.cursorCreationDate }
    var totalDeletedCount: Int { appState?.totalDeletedCount ?? 0 }

    func load() async {
        isLoading = true
        errorMessage = nil
        let result = await Task.detached(priority: .userInitiated) { () async -> ([String], [MonthSection], [String: Int]) in
            let ids = await MainActor.run {
                AssetRepository().fetchAllAssetIdsChronological()
            }
            let sections = await MainActor.run {
                AssetRepository().buildMonthSections(assetIds: ids)
            }
            let indexMap = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
            return (ids, sections, indexMap)
        }.value

        assetIds = result.0
        monthSections = result.1
        idToIndex = result.2
        undoStack.removeAll()

        deletionSet = loadDeletionSet()
        appState = fetchOrCreateAppState()
        resolveCursor()
        prefetch()

        isLoading = false
    }

    func refreshLibrary() async {
        await load()
    }

    func swipeLeft() {
        guard let id = currentAssetId else { return }
        markDelete(assetId: id)
        undoStack.append(UndoAction(assetId: id, action: .delete))
        advance()
    }

    func swipeRight() {
        guard let id = currentAssetId else { return }
        if deletionSet.contains(id) {
            unmarkDelete(assetId: id)
            undoStack.append(UndoAction(assetId: id, action: .unmarkDelete))
        } else {
            undoStack.append(UndoAction(assetId: id, action: .keep))
        }
        advance()
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        if last.action == .delete {
            unmarkDelete(assetId: last.assetId)
        } else if last.action == .unmarkDelete {
            markDelete(assetId: last.assetId)
        }
        if let idx = idToIndex[last.assetId] {
            currentIndex = idx
            persistCursor(assetId: last.assetId)
            prefetch()
        }
    }

    func jump(to assetId: String) {
        guard let idx = idToIndex[assetId] else { return }
        currentIndex = idx
        persistCursor(assetId: assetId)
        prefetch()
    }

    func toggleDelete(assetId: String) {
        if deletionSet.contains(assetId) {
            unmarkDelete(assetId: assetId)
        } else {
            markDelete(assetId: assetId)
        }
    }

    func commitDeletion() async -> Result<Void, Error> {
        let deletedCount = deletionSet.count
        let ids = Array(deletionSet)
        do {
            try await deletionService.commitDeletion(assetIds: ids)
            clearDeletionQueue()
            if deletedCount > 0 {
                let current = appState?.totalDeletedCount ?? 0
                appState?.totalDeletedCount = current + deletedCount
                try? modelContext.save()
            }
            await refreshLibrary()
            commitToastMessage = "Deletion committed"
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func toggleFavorite(assetId: String) async {
        do {
            try await metadataService.toggleFavorite(assetId: assetId)
            refreshToken = UUID()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func advance() {
        if currentIndex < assetIds.count - 1 {
            currentIndex += 1
        }
        persistCursor(assetId: currentAssetId)
        prefetch()
    }

    private func prefetch() {
        guard !assetIds.isEmpty else { return }
        let start = currentIndex
        let end = min(currentIndex + prefetchWindow, assetIds.count - 1)
        if start <= end {
            let ids = Array(assetIds[start...end])
            thumbnailService.startPrefetch(assetIds: ids, targetSize: prefetchSize, contentMode: .aspectFit, deliveryMode: .highQualityFormat)
            albumTagService.prefetch(assetIds: ids)
        }
    }

    private func fetchOrCreateAppState() -> AppState {
        let descriptor = FetchDescriptor<AppState>(predicate: #Predicate { $0.id == "singleton" })
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        let newState = AppState()
        modelContext.insert(newState)
        try? modelContext.save()
        return newState
    }

    private func persistCursor(assetId: String?) {
        guard let appState else { return }
        appState.cursorAssetId = assetId
        if let assetId {
            appState.cursorCreationDate = metadataService.creationDate(assetId: assetId)
        } else {
            appState.cursorCreationDate = nil
        }
        appState.updatedAt = Date()
        try? modelContext.save()
    }

    private func resolveCursor() {
        guard !assetIds.isEmpty else {
            currentIndex = 0
            return
        }

        if let id = appState?.cursorAssetId, let idx = idToIndex[id] {
            currentIndex = idx
            return
        }

        if let cursorDate = appState?.cursorCreationDate {
            var foundIndex: Int?
            for (index, id) in assetIds.enumerated() {
                if let date = metadataService.creationDate(assetId: id), date >= cursorDate {
                    foundIndex = index
                    break
                }
            }
            if let foundIndex {
                currentIndex = foundIndex
            } else {
                currentIndex = max(assetIds.count - 1, 0)
            }
        } else {
            currentIndex = 0
        }

        persistCursor(assetId: currentAssetId)
    }

    private func loadDeletionSet() -> Set<String> {
        let descriptor = FetchDescriptor<DeletionQueueItem>()
        let items = (try? modelContext.fetch(descriptor)) ?? []
        return Set(items.map { $0.assetId })
    }

    private func markDelete(assetId: String) {
        guard !deletionSet.contains(assetId) else { return }
        deletionSet.insert(assetId)
        let item = DeletionQueueItem(assetId: assetId)
        modelContext.insert(item)
        try? modelContext.save()
    }

    private func unmarkDelete(assetId: String) {
        guard deletionSet.contains(assetId) else { return }
        deletionSet.remove(assetId)

        let descriptor = FetchDescriptor<DeletionQueueItem>(predicate: #Predicate { $0.assetId == assetId })
        if let item = try? modelContext.fetch(descriptor).first {
            modelContext.delete(item)
            try? modelContext.save()
        }
    }

    private func clearDeletionQueue() {
        let descriptor = FetchDescriptor<DeletionQueueItem>()
        if let items = try? modelContext.fetch(descriptor) {
            for item in items { modelContext.delete(item) }
            try? modelContext.save()
        }
        deletionSet.removeAll()
    }
}
