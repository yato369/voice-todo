import SwiftUI
import SwiftData

@main
struct VoiceTodoApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: TodoItem.self, TodoList.self)
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .modelContainer(container)
    }
}
