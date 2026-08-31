import SwiftUI
import SwiftData

/// Manage category lists: create (incl. sub-lists), rename, recolor, change
/// icon, set default, and delete (deleting a list cascades to its subtree and
/// its items — plus descendants' items — migrate to the default list).
struct ManageListsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TodoList.position) private var lists: [TodoList]

    @State private var editingSheet: EditingSheet?

    private var storage: StorageServiceProtocol { StorageService(context: modelContext) }

    struct EditingSheet: Identifiable {
        let id = UUID()
        let list: TodoList?         // nil = create new
        var parentPreset: TodoList? // preselected parent when creating a sub-list
    }

    // MARK: - Tree flattening

    private var rootLists: [TodoList] {
        lists.filter { $0.parent == nil }.sorted { $0.position < $1.position }
    }

    /// Every list rendered with its nesting depth, for indented display.
    private var flattened: [(list: TodoList, depth: Int)] {
        var out: [(TodoList, Int)] = []
        func walk(_ roots: [TodoList], _ depth: Int) {
            for list in roots {
                out.append((list, depth))
                walk(list.children.sorted { $0.position < $1.position }, depth + 1)
            }
        }
        walk(rootLists, 0)
        return out
    }

    var body: some View {
        List {
            Section {
                let rows = flattened
                ForEach(rows.indices, id: \.self) { index in
                    let entry = rows[index]
                    HStack(spacing: 12) {
                        if entry.depth > 0 {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: CGFloat(entry.depth) * 16, height: 1)
                        }
                        Image(systemName: entry.list.iconName ?? "checklist")
                            .foregroundStyle(entry.list.color)
                            .frame(width: 26)
                        TextField("列表名", text: binding(for: entry.list))
                        if entry.list.isDefault {
                            Text("默认")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            editingSheet = EditingSheet(list: entry.list, parentPreset: nil)
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.borderless)
                    }
                    .contextMenu {
                        Button {
                            editingSheet = EditingSheet(list: entry.list)
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        Button {
                            editingSheet = EditingSheet(list: nil, parentPreset: entry.list)
                        } label: {
                            Label("在此列表下新建子列表", systemImage: "folder.badge.plus")
                        }
                        if !entry.list.isDefault {
                            Button {
                                setDefault(entry.list)
                            } label: {
                                Label("设为默认", systemImage: "star")
                            }
                        }
                    }
                }
                .onDelete(perform: delete)
            } header: {
                Text("左滑删除；长按可编辑或新建子列表")
            }

            Section {
                Button {
                    editingSheet = EditingSheet(list: nil)
                } label: {
                    Label("新建列表", systemImage: "plus.circle.fill")
                }
            }

            Section {
                Text("列表可任意嵌套（二级、三级…分层归类）；新待办默认进入「默认」（收件箱）列表；删除列表时，其子列表与该列表内的待办会移回默认列表。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("管理列表")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingSheet) { sheet in
            EditListSheet(list: sheet.list, parentPreset: sheet.parentPreset)
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

    private func delete(at offsets: IndexSet) {
        let defaultList = lists.first { $0.isDefault }
        let rows = flattened
        for index in offsets {
            guard rows.indices.contains(index) else { continue }
            let entry = rows[index]
            guard !entry.list.isDefault else { continue }
            // Collect the whole subtree (list + all descendants) for migration.
            var subtree: [TodoList] = []
            func collect(_ l: TodoList) {
                subtree.append(l)
                for child in l.children { collect(child) }
            }
            collect(entry.list)
            if let defaultList {
                for node in subtree {
                    for item in node.items {
                        item.list = defaultList
                    }
                }
            }
            modelContext.delete(entry.list)   // cascade removes descendants
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

/// Create / edit a list: name, parent (nesting), color, icon.
/// Also presented from TodoListView (long-press a section header).
struct EditListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TodoList.position) private var lists: [TodoList]

    let list: TodoList?
    var parentPreset: TodoList?

    @State private var name: String = ""
    @State private var colorHex: String = TodoList.paletteHex[0]
    @State private var iconName: String = TodoList.iconOptions[0]
    @State private var parentID: UUID?

    private var isCreating: Bool { list == nil }

    /// Candidates for the "parent" picker: the flattened tree, excluding the
    /// list being edited and its own descendants (to avoid cycles).
    private var parentOptions: [(list: TodoList, depth: Int)] {
        var excluded: Set<UUID> = []
        if let list {
            excluded.insert(list.id)
            func collectChildren(_ l: TodoList) {
                for child in l.children {
                    excluded.insert(child.id)
                    collectChildren(child)
                }
            }
            collectChildren(list)
        }
        var out: [(TodoList, Int)] = []
        func walk(_ roots: [TodoList], _ depth: Int) {
            for l in roots.sorted(by: { $0.position < $1.position }) {
                guard !excluded.contains(l.id) else { continue }
                out.append((l, depth))
                walk(l.children, depth + 1)
            }
        }
        walk(lists.filter { $0.parent == nil }, 0)
        return out
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("列表名", text: $name)
                }

                Section("父列表") {
                    Picker("父列表", selection: $parentID) {
                        Text("（无 — 顶层列表）").tag(UUID?.none)
                        ForEach(parentOptions, id: \.list.id) { entry in
                            Text(String(repeating: "　", count: entry.depth) + entry.list.name)
                                .tag(Optional(entry.list.id))
                        }
                    }
                    Text("选择父列表后，新列表会成为其子列表，用于二级/三级分类。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                    parentID = list.parent?.id
                } else if let parentPreset {
                    parentID = parentPreset.id
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let parent = parentID.flatMap { id in lists.first { $0.id == id } }
        if let list {
            list.name = trimmed
            list.colorHex = colorHex
            list.iconName = iconName
            list.parent = parent
            list.position = parent?.children.count ?? lists.filter { $0.parent == nil }.count
        } else {
            let newList = TodoList(
                name: trimmed,
                position: parent?.children.count ?? lists.filter { $0.parent == nil }.count,
                colorHex: colorHex,
                iconName: iconName,
                isDefault: lists.isEmpty,
                parent: parent
            )
            modelContext.insert(newList)
        }
        try? modelContext.save()
        dismiss()
    }
}