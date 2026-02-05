import SwiftUI
import UIKit

struct LandingView: View {
    @EnvironmentObject private var auth: PhotoAuthorizationService
    @State private var showLimitedPicker = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    UsageContentView(showTitle: true)
                }
                .padding(24)
            }

            Divider()

            VStack(spacing: 12) {
                if auth.isDenied {
                    Text("Photo access is denied. Enable access in Settings to continue.")
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Allow Photo Access") {
                        Task { await auth.request() }
                    }
                    .buttonStyle(.borderedProminent)
                }

                if auth.isLimited {
                    VStack(spacing: 8) {
                        Text("Limited access enabled")
                            .font(.headline)
                        Button("Manage Access") {
                            showLimitedPicker = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showLimitedPicker) {
            LimitedLibraryPickerPresenter(isPresented: $showLimitedPicker)
                .ignoresSafeArea()
        }
        .onChange(of: showLimitedPicker) { _, newValue in
            if !newValue { auth.refresh() }
        }
    }
}
