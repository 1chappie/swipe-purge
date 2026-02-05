import Foundation
import SwiftData

@Model
final class AppState {
    @Attribute(.unique) var id: String
    var cursorAssetId: String?
    var cursorCreationDate: Date?
    var updatedAt: Date
    var totalDeletedCount: Int?

    init(id: String = "singleton",
         cursorAssetId: String? = nil,
         cursorCreationDate: Date? = nil,
         updatedAt: Date = Date(),
         totalDeletedCount: Int? = nil) {
        self.id = id
        self.cursorAssetId = cursorAssetId
        self.cursorCreationDate = cursorCreationDate
        self.updatedAt = updatedAt
        self.totalDeletedCount = totalDeletedCount
    }
}

@Model
final class DeletionQueueItem {
    @Attribute(.unique) var assetId: String
    var addedAt: Date

    init(assetId: String, addedAt: Date = Date()) {
        self.assetId = assetId
        self.addedAt = addedAt
    }
}
