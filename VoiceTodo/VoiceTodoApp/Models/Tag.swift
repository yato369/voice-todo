import Foundation
import SwiftData
import SwiftUI

/// A cross-cutting label (优先级 / 来源, …). Overlap across lists,
/// complementary to the tree of TodoLists.
@Model
final class Tag {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String
    var colorHex: String?
    var createdAt: Date

    @Relationship(inverse: \TodoItem.tags)
    var items: [TodoItem] = []

    init(name: String, colorHex: String? = nil, createdAt: Date = Date()) {
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
    }

    var color: Color {
        guard let colorHex else { return .accentColor }
        return Color(hex: colorHex)
    }
}