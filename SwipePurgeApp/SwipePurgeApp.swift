import SwiftUI
import SwiftData

@main
struct SwipePurgeApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: AppState.self, DeletionQueueItem.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
