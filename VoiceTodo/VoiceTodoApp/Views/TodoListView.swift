import SwiftUI
import SwiftData

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

    /// Lists whose sections are collapsed (items hidden, header kept).
    @State private var collapsedLists: Set<UUID> = []

    /// The flattened grouped list rendered by the UI. The List is driven by
    /// this array of plain rows (NOT live `@Query` data) so drag reorder only
    /// mutates this array and never fights the move animation with model/
    /// query updates — this is what eliminates the "index path does not exist"
    /// / "invalid number of items in section" crashes.
    @State private var displayRows: [GRow] = []

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

    /// Stable id used for the "未分类" header row and its collapse state.
    private static let unassignedHeaderID =
        UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE")!

    /// A row in the flattened grouped list: a non-movable list header, a
    /// movable task, or an empty-list drop slot. Rendering them all in ONE
    /// collection lets the native `onMove` reorder tasks inside a list AND
    /// across lists (dropping an item under a different header reassigns it
    /// to that list). The empty slot is an extra, non-movable row shown under
    /// an empty (uncollapsed) list so it remains a valid drop target.
    private enum GRow: Identifiable {
        case header(id: UUID, listID: UUID?, name: String, color: Color,
                    icon: String, depth: Int, count: Int)
        case item(TodoItem)
        case emptySlot(id: UUID)

        var id: String {
            switch self {
            case .header(let id, _, _, _, _, _, _): return "h-\(id.uuidString)"
            case .item(let item): return "i-\(item.id.uuidString)"
            case .emptySlot(let id): return "e-\(id.uuidString)"
            }
        }
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

    /// Flattened, in order: each list's header (non-movable), then either:
    /// - if collapsed: stop (no children, the whole subtree is hidden)
    /// - if expanded: list's tasks (or empty slot if 0 tasks), then recursively
    ///   include this list's children (subfolders), recursively expanded.
    ///
    /// Folding a list hides its entire subtree (all descendant lists + their
    /// items), matching the file-explorer tree behavior.
    ///
    /// An empty (expanded) list gets an extra `emptySlot` row so it remains a
    /// valid drop target when dragging into it (since the list expects at least
    /// one row to receive the drop).
    private var groupedRows: [GRow] {
        func addSubtree(roots: [(TodoList, Int)], to rows: inout [GRow]) {
            for (list, depth) in roots {
                let sectionItems = itemsSorted(forList: list.id)
                rows.append(.header(id: list.id, listID: list.id,
                                    name: list.name, color: list.color,
                                    icon: list.iconName ?? "checklist",
                                    depth: depth, count: sectionItems.count))
                if collapsedLists.contains(list.id) {
                    continue // stop: entire subtree is hidden
                }
                if sectionItems.isEmpty {
                    rows.append(.emptySlot(id: list.id))
                } else {
                    rows.append(contentsOf: sectionItems.map { .item($0) })
                }
                let childRoots = list.children.sorted { $0.position < $1.position }
                    .map { ($0, depth + 1) }
                addSubtree(roots: childRoots, to: &rows)
            }
        }

        var rows: [GRow] = []
        let rootChildren = rootLists.map { ($0, 0) }
        addSubtree(roots: rootChildren, to: &rows)

        // Unassigned items (list == nil)
        let unassigned = items.filter { $0.list == nil }.sorted(by: sortInList)
        if !unassigned.isEmpty {
            rows.append(.header(id: Self.unassignedHeaderID, listID: nil,
                                name: "未分类", color: .gray, icon: "circle",
                                depth: 0, count: unassigned.count))
            if !collapsedLists.contains(Self.unassignedHeaderID) {
                if unassigned.isEmpty {
                    rows.append(.emptySlot(id: Self.unassignedHeaderID))
                } else {
                    rows.append(contentsOf: unassigned.map { .item($0) })
                }
            }
        }
        return rows
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
                refreshDisplayRows()
            }
            .onChange(of: items.count) { _ in
                refreshDisplayRows()
            }
            .onChange(of: lists.count) { _ in
                refreshDisplayRows()
            }
            .onChange(of: collapsedLists) { _ in
                refreshDisplayRows()
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

    // MARK: - Grouped list (explicit drag & drop)

    /// Grouped tasks rendered as ONE flattened `List`. Dragging is done with
    /// SwiftUI's explicit `.draggable` / `.dropDestination` pair (NOT `onMove`):
    ///
    /// - Each task row is **draggable** (long-press to lift) and is also a
    ///   drop target (dropping BEFORE that row inserts the dragged task there).
    /// - Each task header and each empty-list placeholder is a drop target that
    ///   **appends** the dragged task to that list.
    ///
    /// Because the empty placeholder is an explicit `.dropDestination` (instead
    /// of relying on `onMove`'s insertion-boundary rules between movable rows),
    /// you can drop a task into an EMPTY list too. The placeholder is purely a
    /// receiver and never itself draggable.
    private var groupedList: some View {
        List {
            ForEach(displayRows) { row in
                switch row {
                case .header(let id, let listID, let name, let color, let icon, let depth, let count):
                    GroupedHeaderView(
                        name: name, color: color, icon: icon,
                        depth: depth, count: count,
                        isCollapsed: collapsedLists.contains(id),
                        onToggle: { toggleCollapse(id) }
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    .dropDestination(for: String.self) { payloads, _ in
                        append(dragged: payloads, to: listID)
                    }
                case .item(let item):
                    TodoRow(item: item) { toggle(item) }
                        .draggable(Self.dragMarker + item.id.uuidString)
                        .dropDestination(for: String.self) { payloads, _ in
                            insertBefore(dragged: payloads, target: item)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { deleteOne(item) } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                case .emptySlot(let listID):
                    // Explicit drop target so an EMPTY list can still receive a
                    // dropped task. Never draggable itself.
                    EmptyListDropSlot()
                        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                        .dropDestination(for: String.self) { payloads, _ in
                            append(dragged: payloads, to: listID)
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Drag & drop helpers

    /// Prefix that distinguishes our drag payload from arbitrary text.
    private static let dragMarker = "vt-item:"

    /// Pull the dragged item out of the payloads delivered to a drop target.
    private func draggedItem(_ payloads: [String]) -> TodoItem? {
        guard let first = payloads.first,
              first.hasPrefix(Self.dragMarker),
              let id = UUID(uuidString: String(first.dropFirst(Self.dragMarker.count)))
        else { return nil }
        return items.first { $0.id == id }
    }

    /// Drop a task onto a list header / empty placeholder → append to `listID`.
    private func append(dragged payloads: [String], to listID: UUID?) -> Bool {
        guard let item = draggedItem(payloads) else { return false }
        guard let list = lists.first(where: { $0.id == listID }) else { return false }
        guard item.list?.id != listID else { return false }   // already here → no-op

        item.list = list
        item.position = itemsSorted(forList: listID).count    // append at the end
        try? storage.save()
        refreshDisplayRows()
        return true
    }

    /// Drop a task onto a task row → insert it BEFORE that row's item.
    private func insertBefore(dragged payloads: [String], target: TodoItem) -> Bool {
        guard let item = draggedItem(payloads) else { return false }
        guard item.id != target.id else { return true }       // dropped on itself → ignore

        let targetListID = target.list?.id
        guard let list = lists.first(where: { $0.id == targetListID }) else { return false }
        item.list = list

        // Rebuild this list's order with the dragged item inserted before target.
        var ordered = itemsSorted(forList: targetListID).filter { $0.id != item.id }
        if let idx = ordered.firstIndex(where: { $0.id == target.id }) {
            ordered.insert(item, at: idx)
        } else {
            ordered.append(item)
        }
        for (idx, it) in ordered.enumerated() { it.position = idx }

        try? storage.save()
        refreshDisplayRows()
        return true
    }

    /// A tappable list header with a collapse chevron and item count.
    private struct GroupedHeaderView: View {
        let name: String
        let color: Color
        let icon: String
        let depth: Int
        let count: Int
        let isCollapsed: Bool
        let onToggle: () -> Void

        var body: some View {
            HStack(spacing: 8) {
                Button(action: onToggle) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.footnote)
                Text(name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, CGFloat(depth) * 16)
            .contentShape(Rectangle())
        }
    }

    /// Toggle a list's open/closed state. The state cascades to the list's
    /// DIRECT children (each level only manages the next level), so expanding
    /// a folder also reveals its subfolders and collapsing folds the whole
    /// subtree — matching the file-explorer disclosure model. Deep descendants
    /// stay managed by their own arrows.
    private func toggleCollapse(_ id: UUID) {
        var affected: Set<UUID> = [id]
        if let list = lists.first(where: { $0.id == id }) {
            for child in list.children {
                affected.insert(child.id)
            }
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            if collapsedLists.contains(id) {
                collapsedLists.subtract(affected)
            } else {
                collapsedLists.formUnion(affected)
            }
        }
    }

    // MARK: - Display row sync (rebuild from live data, no drag conflict)

    /// Rebuild `displayRows` from the current `@Query` data. Called when the
    /// underlying data changes (create/delete/toggle/move) and on appear. The
    /// drag path avoids this by mutating only `displayRows` in place.
    private func refreshDisplayRows() {
        displayRows = groupedRows
    }

    // MARK: - Flat list

    private var flatList: some View {
        List {
            ForEach(filteredItems) { item in
                TodoRow(item: item) {
                    toggle(item)
                }
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

    private func deleteFlatItems(at offsets: IndexSet) {
        for index in offsets {
            deleteOne(filteredItems[index])
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