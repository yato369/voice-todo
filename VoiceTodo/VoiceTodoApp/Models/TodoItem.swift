import Foundation
import SwiftData

/// Single source of truth: one record is both a to-do and a calendar item.
@Model
final class TodoItem {
    @Attribute(.unique) var id: UUID = UUID()
    var text: String
    var audioFileName: String?
    var createdAt: Date
    var isCompleted: Bool
    var completedAt: Date?
    var reminderDate: Date?

    /// The category list this to-do belongs to (nil pending default backfill).
    var list: TodoList?

    /// Manual sort order within its list (lower = higher up).
    var position: Int = 0

    /// Cross-cutting labels (优先级 / 来源, …). Many-to-many.
    @Relationship(inverse: \Tag.items) var tags: [Tag] = []

    init(
        text: String,
        audioFileName: String? = nil,
        createdAt: Date = Date(),
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        reminderDate: Date? = nil,
        position: Int = 0
    ) {
        self.text = text
        self.audioFileName = audioFileName
        self.createdAt = createdAt
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.reminderDate = reminderDate
        self.position = position
    }

    var calendarDate: Date {
        createdAt
    }
}
