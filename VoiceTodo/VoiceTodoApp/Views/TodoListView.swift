import SwiftUI
import SwiftData

struct TodoListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TodoItem.createdAt, order: .reverse) private var items: [TodoItem]
    @State private var activeSheet: SheetType?

    private var storage: StorageServiceProtocol { StorageService(context: modelContext) }

    enum SheetType: Identifiable {
        case voice
        case text

        var id: Self { self }
    }

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
                        systemImage: "checklist",
                        description: Text("点击右下角按钮，语音或文字输入创建待办。")
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
                actionButtons
            }
            .sheet(item: $activeSheet) { sheet in
                RecordView(mode: sheet == .voice ? .voice : .text)
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                activeSheet = .text
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .frame(width: 56, height: 56)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Circle())
                    .shadow(radius: 4, y: 2)
            }

            Button {
                activeSheet = .voice
            } label: {
                Image(systemName: "mic.fill")
                    .font(.title2)
                    .frame(width: 56, height: 56)
                    .background(Color.red)
                    .foregroundStyle(.white)
                    .clipShape(Circle())
                    .shadow(radius: 4, y: 2)
            }
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
