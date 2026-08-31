import SwiftUI
import SwiftData

struct TodoListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TodoItem.createdAt, order: .reverse) private var items: [TodoItem]
    @Query(sort: \TodoList.position) private var lists: [TodoList]

    @State private var activeSheet: SheetType?
    @State private var layout: ListLayout = .grouped
    @State private var filterListID: UUID?

    private var storage: StorageServiceProtocol { StorageService(context: modelContext) }

    enum SheetType: Identifiable {
        case voice
        case text
        var id: Self { self }
    }

    enum ListLayout: String, CaseIterable {
        case grouped = "分组"
        case flat = "全部"
    }

    /// A rendered section for a category list in grouped mode.
    private struct SectionModel: Identifiable {
        let id: UUID
        let title: String
        let color: Color
        let icon: String
        let items: [TodoItem]
    }

    /// Sort: incomplete first, then newest first.
    private func sort(_ a: TodoItem, _ b: TodoItem) -> Bool {
        if a.isCompleted != b.isCompleted { return !a.isCompleted }
        return a.createdAt > b.createdAt
    }

    // MARK: - Section model

    private var sections: [SectionModel] {
        var result: [SectionModel] = lists.map { list in
            SectionModel(
                id: list.id,
                title: list.name,
                color: list.color,
                icon: list.iconName ?? "checklist",
                items: items.filter { $0.list?.id == list.id }.sorted(by: sort)
            )
        }

        // Safety net: items without a list (prior to default backfill).
        let unassigned = items.filter { $0.list == nil }.sorted(by: sort)
        if !unassigned.isEmpty {
            result.append(SectionModel(
                id: UUID(),
                title: "未分类",
                color: .gray,
                icon: "circle",
                items: unassigned
            ))
        }
        return result
    }

    private var filteredItems: [TodoItem] {
        let base = filterListID == nil ? items : items.filter { $0.list?.id == filterListID }
        return base.sorted(by: sort)
    }

    // MARK: - Body

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
                    VStack(spacing: 0) {
                        layoutPicker
                        if layout == .grouped {
                            groupedList
                        } else {
                            flatList
                        }
                    }
                }
            }
            .navigationTitle("待办")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        ManageListsView()
                    } label: {
                        Label("管理列表", systemImage: "folder")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
                if layout == .flat {
                    ToolbarItem(placement: .topBarTrailing) {
                        filterMenu
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                actionButtons
            }
            .sheet(item: $activeSheet) { sheet in
                RecordView(mode: sheet == .voice ? .voice : .text)
            }
            .onAppear {
                ensureDefaultList()
            }
        }
    }

    private var layoutPicker: some View {
        Picker("布局", selection: $layout) {
            ForEach(ListLayout.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var filterMenu: some View {
        Menu {
            Button {
                filterListID = nil
            } label: {
                Label("全部列表", systemImage: filterListID == nil ? "checkmark" : "line.3.horizontal")
            }
            Divider()
            ForEach(lists) { list in
                Button {
                    filterListID = list.id
                } label: {
                    Label(list.name, systemImage: filterListID == list.id ? "checkmark" : "circle")
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
    }

    // MARK: - Grouped list

    private var groupedList: some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.items) { item in
                        TodoRow(item: item) {
                            toggle(item)
                        }
                        .draggable(item.id.uuidString)
                        .contextMenu { moveMenu(for: item) }
                        .swipeActions(edge: .trailing) {
                            moveSwipeButton(for: item)
                        }
                    }
                    .onDelete { offsets in
                        delete(at: offsets, in: section)
                    }
                    .dropDestination(for: String.self) { payload, _ in
                        move(payload, to: section)
                    }
                } header: {
                    Label(section.title, systemImage: section.icon)
                        .foregroundStyle(section.color)
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    // MARK: - Flat list

    private var flatList: some View {
        List {
            ForEach(filteredItems) { item in
                TodoRow(item: item) {
                    toggle(item)
                }
                .contextMenu { moveMenu(for: item) }
                .swipeActions(edge: .trailing) {
                    moveSwipeButton(for: item)
                }
            }
            .onDelete(perform: deleteFlatItems)
        }
    }

    // MARK: - Actions

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

    private func delete(at offsets: IndexSet, in section: SectionModel) {
        for index in offsets {
            let item = section.items[index]
            NotificationService.shared.cancelReminder(id: item.id.uuidString)
            try? storage.delete(item)
        }
    }

    private func deleteFlatItems(at offsets: IndexSet) {
        for index in offsets {
            let item = filteredItems[index]
            NotificationService.shared.cancelReminder(id: item.id.uuidString)
            try? storage.delete(item)
        }
    }

    // MARK: - Moving items between lists

    private func moveMenu(for item: TodoItem) -> some View {
        Menu("移动到列表") {
            ForEach(lists) { list in
                Button {
                    item.list = list
                    try? storage.save()
                } label: {
                    if item.list?.id == list.id {
                        Label(list.name, systemImage: "checkmark")
                    } else {
                        Text(list.name)
                    }
                }
            }
        }
    }

    private func moveSwipeButton(for item: TodoItem) -> some View {
        Menu {
            ForEach(lists) { list in
                Button {
                    item.list = list
                    try? storage.save()
                } label: {
                    Text(list.name)
                }
            }
        } label: {
            Label("移动", systemImage: "folder")
        }
        .tint(.gray)
    }

    private func move(_ payload: [String], to section: SectionModel) {
        guard let idString = payload.first,
              let uuid = UUID(uuidString: idString),
              let dragged = items.first(where: { $0.id == uuid }),
              let target = lists.first(where: { $0.id == section.id }) else { return }
        guard dragged.list?.id != target.id else { return }
        dragged.list = target
        try? storage.save()
    }

    // MARK: - Default list (idempotent seeding)

    /// Creates the default "Inbox" list if absent, and backfills items
    /// that have no list yet. Safe to call repeatedly.
    private func ensureDefaultList() {
        let defaultList = lists.first { $0.isDefault }
        let listToUse: TodoList = defaultList ?? {
            let newList = TodoList(
                name: "收件箱",
                position: 0,
                colorHex: TodoList.paletteHex.first,
                iconName: "tray.fill",
                isDefault: true
            )
            modelContext.insert(newList)
            return newList
        }()

        let unassigned = items.filter { $0.list == nil }
        var changed = false
        for item in unassigned {
            item.list = listToUse
            changed = true
        }
        if defaultList == nil || changed {
            try? storage.save()
        }
    }
}