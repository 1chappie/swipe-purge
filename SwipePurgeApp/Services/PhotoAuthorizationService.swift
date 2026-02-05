import Foundation
import Photos
import Combine

@MainActor
final class PhotoAuthorizationService: ObservableObject {
    @Published private(set) var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    func refresh() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func request() async {
        let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        status = newStatus
    }

    var isAuthorized: Bool {
        status == .authorized
    }

    var isLimited: Bool {
        status == .limited
    }

    var isDenied: Bool {
        status == .denied || status == .restricted
    }
}
