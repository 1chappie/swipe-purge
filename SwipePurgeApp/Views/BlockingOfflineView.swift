import SwiftUI

struct BlockingOfflineView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Internet Required")
                .font(.largeTitle.weight(.bold))
            Text("SwipePurge does not function offline. Please connect to the internet to continue.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            ProgressView()
                .progressViewStyle(.circular)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.05))
    }
}
