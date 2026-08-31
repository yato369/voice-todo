import Foundation
import SwiftData
import SwiftUI

/// A named category list that a to-do belongs to (like iOS Reminders lists).
/// Lists are fully user-managed; only one built-in default "Inbox" list ships.
@Model
final class TodoList {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String
    /// Manual ordering among lists (lower = shown first).
    var position: Int
    var colorHex: String?
    var iconName: String?
    var createdAt: Date
    var isDefault: Bool

    @Relationship(deleteRule: .nullify, inverse: \TodoItem.list)
    var items: [TodoItem] = []

    init(
        name: String,
        position: Int = 0,
        colorHex: String? = nil,
        iconName: String? = nil,
        createdAt: Date = Date(),
        isDefault: Bool = false
    ) {
        self.name = name
        self.position = position
        self.colorHex = colorHex
        self.iconName = iconName
        self.createdAt = createdAt
        self.isDefault = isDefault
    }

    var color: Color {
        guard let colorHex else { return .accentColor }
        return Color(hex: colorHex)
    }
}

// MARK: - Preset palette / icons

extension TodoList {
    /// Preset accent colors offered when creating/editing a list.
    static let paletteHex: [String] = [
        "E53935", "FB8C00", "FDD835", "43A047",
        "039BE5", "5E35B1", "8E24AA", "6D4C41"
    ]

    /// Preset SF Symbol icons offered when creating/editing a list.
    static let iconOptions: [String] = [
        "checklist", "book", "briefcase", "cart",
        "house", "bolt", "calendar", "star"
    ]
}

extension Color {
    /// Returns a color from "#RRGGBB" hex string, or falls back to accent.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}