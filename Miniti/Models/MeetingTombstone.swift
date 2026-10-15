import Foundation
import SwiftData

/// A meeting this device deleted that the cloud still knows about (3.0.0). Written in the
/// same save as the delete, sent as `DELETE /api/sync/meetings/{id}` by the sync engine,
/// and removed once the server acknowledges. Meetings that were never uploaded leave no
/// tombstone. Adding an entity is a lightweight SwiftData migration.
@Model
final class MeetingTombstone {
    var id: UUID
    var deletedAt: Date
    /// The cloud revision this device last saw, sent as `base_revision`.
    var cloudRevision: Int

    init(id: UUID, deletedAt: Date = Date(), cloudRevision: Int) {
        self.id = id
        self.deletedAt = deletedAt
        self.cloudRevision = cloudRevision
    }
}
