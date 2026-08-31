import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Drag & drop delegates (onDrag + onDrop, reliable inside List)
//
// NOTE on UTType matching: NSItemProvider(object: NSString) registers
// "public.utf8-plain-text", NOT "public.plain-text". Matching plainText
// alone silently rejects every drop. We therefore accept both types and
// validate unconditionally.

/// Drop target = a to-do row. Dropping here reorders within the list or
/// moves the dragged item into the target row's list at that position.
private struct TodoRowDropDelegate: DropDelegate {
    let target: TodoItem
    let perform: (_ draggedID: UUID, _ target: TodoItem) -> Void

    func validateDrop(info: DropInfo) -> Bool { true }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: dropTypes).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let string = object as? String,
                  let draggedID = UUID(uuidString: string) else { return }
            DispatchQueue.main.async {
                perform(draggedID, target)
            }
        }
        return true
    }
}

/// Drop target = a section header. Dropping here appends the dragged item
/// to that list (end position).
private struct ListHeaderDropDelegate: DropDelegate {
    let list: TodoList?
    let perform: (_ draggedID: UUID, _ list: TodoList?) -> Void

    func validateDrop(info: DropInfo) -> Bool { true }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: dropTypes).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let string = object as? String,
                  let draggedID = UUID(uuidString: string) else { return }
            DispatchQueue.main.async {
                perform(draggedID, list)
            }
        }
        return true
    }
}

/// Type identifiers accepted by our drop targets (see NOTE above).
private let dropTypes: [UTType] = [.plainText, .utf8PlainText]

struct TodoListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TodoItem.createdAt, order: .reverse) private var items: [TodoItem]
    @Query(sort: \TodoList.position) private var lists: [TodoList]
    @Query(sort: \Tag.createdAt) private var tags: [Tag]

    @State private var activeSheet: SheetType?
    @State private var listEditSheet: ListEditSheet?
    @State private var layout: ListLayout = .grouped
    @State private var filterListID: UUID?
    @State private var filterTagID: UUID?

    /// Self-managed edit mode (independent of the system EditButton env):
    /// when active, every row shows a red minus (delete) + a drag handle (≡).
    @State private var isEditing = false
    /// Lists whose sections are collapsed (items hidden, header kept).
    @State private var collapsedLists: Set<UUID> = []

    private var storage: StorageServiceProtocol { StorageService(context: modelContext) }

    /// Edit an existing list or create a sub-list under a parent.
    enum ListEditSheet: Identifiable {
        case edit(TodoList)
        case newChild(TodoList)
        var id: UUID {
            switch self {
            case .edit(let list): return list.id
            case .newChild(let parent): return parent.id
            }
        }
    }

    enum SheetType: Identifiable {
        case voice
        case text
        var id: Self { self }
    }

    enum ListLayout: String, CaseIterable {
        case grouped = "分组"
        case flat = "全部"
    }

    /// A rendered group = one list at some tree depth, plus its items.
    private struct ListGroup: Identifiable {
        let id: UUID
        let list: TodoList?       // nil for the unassigned fallback bucket
        let title: String
        let color: Color
        let icon: String
        let depth: Int
        let items: [TodoItem]
    }

    // MARK: - Sorting

    /// In-list manual order: completed at the end, then position, then newest.
    private func sortInList(_ a: TodoItem, _ b: TodoItem) -> Bool {
        if a.isCompleted != b.isCompleted { return !a.isCompleted }
        if a.position != b.position { return a.position < b.position }
        return a.createdAt > b.createdAt
    }

    private func sortFlat(_ a: TodoItem, _ b: TodoItem) -> Bool {
        if a.isCompleted != b.isCompleted { return !a.isCompleted }
        return a.createdAt > b.createdAt
    }

    private func itemsSorted(forList id: UUID?) -> [TodoItem] {
        items.filter { $0.list?.id == id }.sorted(by: sortInList)
    }

    // MARK: - Tree flattening (arbitrary depth)

    private var rootLists: [TodoList] {
        lists.filter { $0.parent == nil }.sorted { $0.position < $1.position }
    }

    private var flattenedLists: [(list: TodoList, depth: Int)] {
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

    private var groups: [ListGroup] {
        var out = flattenedLists.map { pair in
            ListGroup(
                id: pair.list.id,
                list: pair.list,
                title: pair.list.name,
                color: pair.list.color,
                icon: pair.list.iconName ?? "checklist",
                depth: pair.depth,
                items: itemsSorted(forList: pair.list.id)
            )
        }
        // Safety net: items without a list (pre-backfill).
        let unassigned = items.filter { $0.list == nil }.sorted(by: sortInList)
        if !unassigned.isEmpty {
            out.append(ListGroup(id: UUID(), list: nil, title: "未分类", color: .gray,
                                 icon: "circle", depth: 0, items: unassigned))
        }
        return out
    }

    private var filteredItems: [TodoItem] {
        var base = items
        if let filterListID { base = base.filter { $0.list?.id == filterListID } }
        if let filterTagID { base = base.filter { $0.tags.contains { $0.id == filterTagID } } }
        return base.sorted(by: sortFlat)
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
                    Button(isEditing ? "完成" : "编辑") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditing.toggle()
                        }
                    }
                }
                if layout == .flat {
                    ToolbarItem(placement: .topBarTrailing) { listFilterMenu }
                    ToolbarItem(placement: .topBarTrailing) { tagFilterMenu }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                actionButtons
            }
            .sheet(item: $activeSheet) { sheet in
                RecordView(mode: sheet == .voice ? .voice : .text)
            }
            .sheet(item: $listEditSheet) { sheet in
                switch sheet {
                case .edit(let list):
                    EditListSheet(list: list)
                case .newChild(let parent):
                    EditListSheet(list: nil, parentPreset: parent)
                }
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

    private var listFilterMenu: some View {
        Menu {
            Button {
                filterListID = nil
            } label: {
                Label("全部列表", systemImage: filterListID == nil ? "checkmark" : "line.3.horizontal")
            }
            Divider()
            ForEach(flattenedLists, id: \.list.id) { pair in
                Button {
                    filterListID = pair.list.id
                } label: {
                    Label(prefix(pair.depth) + pair.list.name,
                          systemImage: filterListID == pair.list.id ? "checkmark.circle" : "circle")
                }
            }
        } label: {
            Image(systemName: "folder")
        }
    }

    private var tagFilterMenu: some View {
        Menu {
            Button {
                filterTagID = nil
            } label: {
                Label("全部标签", systemImage: filterTagID == nil ? "checkmark" : "tag")
            }
            Divider()
            ForEach(tags) { tag in
                Button {
                    filterTagID = tag.id
                } label: {
                    Label(tag.name, systemImage: filterTagID == tag.id ? "checkmark" : "tag")
                }
            }
            if tags.isEmpty {
                Text("还没有标签")
            }
        } label: {
            Image(systemName: "tag")
        }
    }

    private func prefix(_ depth: Int) -> String {
        String(repeating: "　", count: depth)
    }

    // MARK: - Grouped list

    private var groupedList: some View {
        List {
            ForEach(groups) { group in
                Section {
                    if !collapsedLists.contains(group.id) {
                        ForEach(group.items) { item in
                            row(item, depth: group.depth)
                        }
                        .onDelete { offsets in delete(at: offsets, in: group) }
                    }
                } header: {
                    groupHeader(group)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                toggleCollapse(group.id)
                            }
                        }
                        .onDrop(of: dropTypes,
                                delegate: ListHeaderDropDelegate(list: group.list) { draggedID, list in
                            moveDraggedToList(draggedID, list)
                        })
                }
            }
        }
    }

    private func toggleCollapse(_ id: UUID) {
        if collapsedLists.contains(id) {
            collapsedLists.remove(id)
        } else {
            collapsedLists.insert(id)
        }
    }

    /// A single to-do row. In edit mode: red minus (delete) on the leading
    /// edge, a ≡ hint on the trailing edge. The whole row is draggable
    /// (long-press anywhere, e.g. the ≡): drop on any row to reorder or
    /// change list, drop on a section header to append to that list.
    /// Non-edit mode: swipe = delete + move.
    private func row(_ item: TodoItem, depth: Int) -> some View {
        HStack(spacing: 10) {
            if isEditing {
                Button(role: .destructive) {
                    deleteOne(item)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.red)
                }
                .buttonStyle(.borderless)
            }
            TodoRow(item: item) {
                toggle(item)
            }
            if isEditing {
                Image(systemName: "line.3.horizontal")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, depth > 0 ? CGFloat(depth) * 16 : 0)
        .onDrag { NSItemProvider(object: item.id.uuidString as NSString) }
        .onDrop(of: dropTypes,
                delegate: TodoRowDropDelegate(target: item) { draggedID, target in
            moveDragged(draggedID, onto: target)
        })
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleteOne(item)
            } label: {
                Label("删除", systemImage: "trash")
            }
            moveSwipeButton(for: item)
        }
    }

    private func groupHeader(_ group: ListGroup) -> some View {
        HStack(spacing: 6) {
            Image(systemName: collapsedLists.contains(group.id) ? "chevron.right" : "chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .frame(width: 14)
            if group.depth > 0 {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: CGFloat(group.depth) * 16, height: 1)
            }
            Circle().fill(group.color).frame(width: 10, height: 10)
            Image(systemName: group.icon)
            Text(group.title)
                .lineLimit(1)
            Spacer()
            Text("\(group.items.count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            if let list = group.list {
                Button {
                    listEditSheet = .edit(list)
                } label: {
                    Label("编辑名称 / 图标", systemImage: "pencil")
                }
                Button {
                    listEditSheet = .newChild(list)
                } label: {
                    Label("新建子列表", systemImage: "folder.badge.plus")
                }
            }
        }
    }

    // MARK: - Flat list

    private var flatList: some View {
        List {
            ForEach(filteredItems) { item in
                HStack(spacing: 10) {
                    if isEditing {
                        Button(role: .destructive) {
                            deleteOne(item)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    TodoRow(item: item) {
                        toggle(item)
                    }
                    if isEditing {
                        Image(systemName: "line.3.horizontal")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDrag { NSItemProvider(object: item.id.uuidString as NSString) }
                .onDrop(of: dropTypes,
                        delegate: TodoRowDropDelegate(target: item) { draggedID, target in
                    moveDragged(draggedID, onto: target)
                })
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { deleteOne(item) } label: {
                        Label("删除", systemImage: "trash")
                    }
                    moveSwipeButton(for: item)
                }
            }
            .onDelete(perform: deleteFlatItems)
        }
    }

    // MARK: - FAB

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button { activeSheet = .text } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .frame(width: 56, height: 56)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Circle())
                    .shadow(radius: 4, y: 2)
            }
            Button { activeSheet = .voice } label: {
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

    // MARK: - Actions

    private func toggle(_ item: TodoItem) {
        item.isCompleted.toggle()
        item.completedAt = item.isCompleted ? Date() : nil
        if item.isCompleted {
            NotificationService.shared.cancelReminder(id: item.id.uuidString)
        }
        try? storage.save()
    }

    private func deleteOne(_ item: TodoItem) {
        NotificationService.shared.cancelReminder(id: item.id.uuidString)
        try? storage.delete(item)
    }

    private func delete(at offsets: IndexSet, in group: ListGroup) {
        for index in offsets {
            deleteOne(group.items[index])
        }
    }

    private func deleteFlatItems(at offsets: IndexSet) {
        for index in offsets {
            deleteOne(filteredItems[index])
        }
    }

    /// Drag & drop onto a row: reorder within the same list, or move the
    /// dragged item into the target row's list at that position.
    private func moveDragged(_ draggedID: UUID, onto target: TodoItem) {
        guard let dragged = items.first(where: { $0.id == draggedID }),
              dragged.id != target.id else { return }
        let listID = target.list?.id
        var arr = itemsSorted(forList: listID)
        arr.removeAll { $0.id == dragged.id }
        let index = arr.firstIndex { $0.id == target.id } ?? arr.count
        arr.insert(dragged, at: index)
        dragged.list = target.list
        for (position, item) in arr.enumerated() {
            item.position = position
        }
        try? storage.save()
    }

    /// Drag & drop onto a section header: move the dragged item into that
    /// list, appended at the end.
    private func moveDraggedToList(_ draggedID: UUID, _ list: TodoList?) {
        guard let dragged = items.first(where: { $0.id == draggedID }) else { return }
        if let list {
            guard lists.contains(where: { $0.id == list.id }) else { return }
            assign(dragged, to: list)
        } else {
            dragged.list = nil
            try? storage.save()
        }
    }

    // MARK: - Moving between lists

    private func moveSwipeButton(for item: TodoItem) -> some View {
        Menu {
            ForEach(flattenedLists, id: \.list.id) { pair in
                Button {
                    assign(item, to: pair.list)
                } label: {
                    Text(prefix(pair.depth) + pair.list.name)
                }
            }
        } label: {
            Label("移动", systemImage: "folder")
        }
        .tint(.gray)
    }

    private func assign(_ item: TodoItem, to list: TodoList) {
        guard item.list?.id != list.id else { return }
        item.list = list
        item.position = itemsSorted(forList: list.id).count   // append at the end
        try? storage.save()
    }

    // MARK: - Default list (idempotent seeding)

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