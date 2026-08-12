import SwiftUI
import SwiftData

struct TodoListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TodoItem.createdAt, order: .reverse) private var items: [TodoItem]
    @State private var showRecorder = false

    private var storage: StorageServiceProtocol { StorageService(context: modelContext) }

    private var sortedItems: [TodoItem] {
        items.sorted { a, b in
            if a.isCompleted != b.isCompleted { return !a.isCompleted }
            return a.createdAt > b.createdAt
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(
                        "还没有待办",
                        systemImage: "mic.fill",
                        description: Text("点击右下角按钮，说一句话即可创建待办。")
                    )
                } else {
                    List {
                        ForEach(sortedItems) { item in
                            TodoRow(item: item) {
                                toggle(item)
                            }
                        }
                        .onDelete(perform: deleteItems)
                    }
                }
            }
            .navigationTitle("待办")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            .overlay(alignment: .bottomTrailing) {
                recordButton
            }
            .sheet(isPresented: $showRecorder) {
                RecordView()
            }
        }
    }

    private var recordButton: some View {
        Button {
            showRecorder = true
        } label: {
            Image(systemName: "mic.fill")
                .font(.title2)
                .frame(width: 56, height: 56)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Circle())
                .shadow(radius: 4, y: 2)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 12)
    }

    private func toggle(_ item: TodoItem) {
        item.isCompleted.toggle()
        item.completedAt = item.isCompleted ? Date() : nil
        if item.isCompleted {
            NotificationService.shared.cancelReminder(id: item.id.uuidString)
        }
        try? storage.save()
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            let item = sortedItems[index]
            NotificationService.shared.cancelReminder(id: item.id.uuidString)
            try? storage.delete(item)
        }
    }
}
