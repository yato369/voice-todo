import Foundation
import SwiftData
import UIKit

/// File-backed storage for to-do photo attachments (Documents/Attachments).
/// Images are re-encoded as JPEG to normalize HEIC/screenshots.
enum ImageStore {
    static func directory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for name: String) -> URL {
        directory().appendingPathComponent(name)
    }

    /// Saves raw image data as a JPEG file; returns its file name.
    static func save(_ data: Data) -> String? {
        guard let image = UIImage(data: data),
              let jpeg = image.jpegData(compressionQuality: 0.8) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do {
            try jpeg.write(to: url(for: name))
            return name
        } catch {
            return nil
        }
    }

    static func delete(_ name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
    }
}

protocol StorageServiceProtocol {
    func fetchAll() throws -> [TodoItem]
    func insert(_ item: TodoItem) throws
    func delete(_ item: TodoItem) throws
    func save() throws
}

/// SwiftData persistence. Swappable so CloudKit can replace it later.
final class StorageService: StorageServiceProtocol {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() throws -> [TodoItem] {
        let descriptor = FetchDescriptor<TodoItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return try context.fetch(descriptor)
    }

    func insert(_ item: TodoItem) throws {
        context.insert(item)
        try context.save()
    }

    func delete(_ item: TodoItem) throws {
        context.delete(item)
        try context.save()
    }

    func save() throws {
        try context.save()
    }
}
