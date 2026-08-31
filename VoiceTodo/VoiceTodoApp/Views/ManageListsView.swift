import SwiftUI
import SwiftData

/// Manage category lists: create, rename, reorder, recolor, change icon,
/// set default, and delete (non-default lists migrate items to the default).
struct ManageListsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TodoList.position) private var lists: [TodoList]

    @State private var editingSheet: EditingSheet?

    private var storage: StorageServiceProtocol { StorageService(context: modelContext) }

    struct EditingSheet: Identifiable {
        let id = UUID()
        let list: TodoList?   // nil = create new
    }

    var body: some View {
        List {
            Section {
                ForEach(lists) { list in
                    HStack(spacing: 12) {
                        Image(systemName: list.iconName ?? "checklist")
                            .foregroundStyle(list.color)
                            .frame(width: 26)
                        TextField("列表名", text: binding(for: list))
                        if list.isDefault {
                            Text("默认")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contextMenu {
                        Button {
                            editingSheet = EditingSheet(list: list)
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        if !list.isDefault {
                            Button {
                                setDefault(list)
                            } label: {
                                Label("设为默认", systemImage: "star")
                            }
                        }
                    }
                }
                .onMove(perform: move)
                .onDelete(perform: delete)
            } header: {
                Text("下拉列表或左滑操作")
            }

            Section {
                Button {
                    editingSheet = EditingSheet(list: nil)
                } label: {
                    Label("新建列表", systemImage: "plus.circle.fill")
                }
            }

            Section {
                Text("新待办默认进入「默认」（收件箱）列表；删除列表时，其中的待办会移回默认列表。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("管理列表")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .sheet(item: $editingSheet) { sheet in
            EditListSheet(list: sheet.list)
        }
    }

    private func binding(for list: TodoList) -> Binding<String> {
        Binding(
            get: { list.name },
            set: {
                list.name = $0
                try? storage.save()
            }
        )
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = lists
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, list) in reordered.enumerated() {
            list.position = index
        }
        try? storage.save()
    }

    private func delete(at offsets: IndexSet) {
        let defaultList = lists.first { $0.isDefault }
        for index in offsets {
            let list = lists[index]
            guard !list.isDefault else { continue }
            // Migrate items back to the default list before deleting.
            if let defaultList {
                for item in list.items {
                    item.list = defaultList
                }
            }
            modelContext.delete(list)
        }
        try? storage.save()
    }

    private func setDefault(_ list: TodoList) {
        for other in lists {
            other.isDefault = (other.id == list.id)
        }
        try? storage.save()
    }
}

// MARK: - Create / edit sheet

private struct EditListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let list: TodoList?

    @State private var name: String = ""
    @State private var colorHex: String = TodoList.paletteHex[0]
    @State private var iconName: String = TodoList.iconOptions[0]

    private var isCreating: Bool { list == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("列表名", text: $name)
                }

                Section("颜色") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                        ForEach(TodoList.paletteHex, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(height: 40)
                                .overlay {
                                    if hex == colorHex {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.white)
                                            .font(.headline)
                                    }
                                }
                                .onTapGesture {
                                    colorHex = hex
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("图标") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                        ForEach(TodoList.iconOptions, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.title3)
                                .frame(width: 40, height: 40)
                                .background(icon == iconName ? Color.accentColor.opacity(0.15) : Color.clear)
                                .foregroundStyle(icon == iconName ? Color.accentColor : Color.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onTapGesture {
                                    iconName = icon
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(isCreating ? "新建列表" : "编辑列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let list {
                    name = list.name
                    colorHex = list.colorHex ?? TodoList.paletteHex[0]
                    iconName = list.iconName ?? TodoList.iconOptions[0]
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let list {
            list.name = trimmed
            list.colorHex = colorHex
            list.iconName = iconName
        } else {
            let all = (try? modelContext.fetch(FetchDescriptor<TodoList>())) ?? []
            let newList = TodoList(
                name: trimmed,
                position: all.count,
                colorHex: colorHex,
                iconName: iconName,
                isDefault: all.isEmpty
            )
            modelContext.insert(newList)
        }
        try? modelContext.save()
        dismiss()
    }
}