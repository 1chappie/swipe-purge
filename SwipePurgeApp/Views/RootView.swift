import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var connectivity = ConnectivityService()
    @StateObject private var auth = PhotoAuthorizationService()

    var body: some View {
        Group {
            if !connectivity.isOnline {
                BlockingOfflineView()
            } else if auth.isAuthorized || auth.isLimited {
                SwipeDeckView(modelContext: modelContext)
                    .environmentObject(auth)
            } else {
                LandingView()
                    .environmentObject(auth)
            }
        }
        .onAppear { auth.refresh() }
    }
}
