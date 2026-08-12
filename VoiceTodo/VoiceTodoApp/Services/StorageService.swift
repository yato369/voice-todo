import Foundation
import SwiftData

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
