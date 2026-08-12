import Foundation
import SwiftData

/// Single source of truth: one record is both a to-do and a calendar item.
@Model
final class TodoItem {
    var id: UUID = UUID()
    var text: String
    var audioFileName: String?
    var createdAt: Date
    var isCompleted: Bool
    var completedAt: Date?
    var reminderDate: Date?

    init(
        text: String,
        audioFileName: String? = nil,
        createdAt: Date = Date(),
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        reminderDate: Date? = nil
    ) {
        self.text = text
        self.audioFileName = audioFileName
        self.createdAt = createdAt
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.reminderDate = reminderDate
    }

    var calendarDate: Date {
        createdAt
    }
}
