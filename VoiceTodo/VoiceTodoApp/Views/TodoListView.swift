import SwiftUI
import SwiftData

/// Main to-do screen (Option A): a single, clean task stream.
///
/// Instead of expanding the whole folder tree as section walls (which buried
/// tasks under headers/counts/indents), the task list is ONE flat stream.
/// Folders/subfolders live as top chips — tap to navigate in, breadcrumb to
/// go back. Cross-folder moves are done by dragging a task onto a chip, or via
/// the left-swipe "移动" menu. All existing functionality is preserved.
struct TodoListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TodoItem.createdAt, order: .reverse) private var items: [TodoItem]
    @Query(sort: \TodoList.position) private var lists: [TodoList]
    @Query(sort: \Tag.createdAt) private var tags: [Tag]

    @State private var activeSheet: SheetType?
    @State private var listEditSheet: ListEditSheet?

    /// Current folder navigation: nil = "全部" (every task in one stream).
    @State private var currentListID: UUID?

    /// Cross-cutting tag filter (optional, from the toolbar tag menu).
    @State private var filterTagID: UUID?

    /// In-memory mirror of the currently shown tasks, in display order. Drag
    /// reorder mutates only this array and writes back to SwiftData once on
    /// drop, so the drag animation never fights live `@Query` updates (the
    /// root cause of the earlier "index path does not exist" crashes).
    @State private var displayItems: [TodoItem] = []

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

    /// The `vt-item:` prefix shared between `.draggable` and `.dropDestination`
    /// payloads so a task drag is type-matched to chip/row drop targets.
    private static let itemDragPrefix = "vt-item:"

    // MARK: - Sorting

    /// In-list manual order: completed at the end, then position, then newest.
    private func sortInList(_ a: TodoItem, _ b: TodoItem) -> Bool {
        if a.isCompleted != b.isCompleted { return !a.isCompleted }
        if a.position != b.position { return a.position < b.position }
        return a.createdAt > b.createdAt
    }

    /// "全部" stream: completed at the end, then newest first.
    private func sortFlat(_ a: TodoItem, _ b: TodoItem) -> Bool {
        if a.isCompleted != b.isCompleted { return !a.isCompleted }
        return a.createdAt > b.createdAt
    }

    // MARK: - Tree helpers

    private var rootLists: [TodoList] {
        lists.filter { $0.parent == nil }.sorted { $0.position < $1.position }
    }

    /// The currently selected list (nil when viewing "全部").
    private var current: TodoList? {
        lists.first { $0.id == currentListID }
    }

    /// Path from the root ancestor down to a list, inclusive.
    private func ancestry(of list: TodoList) -> [TodoList] {
        var path: [TodoList] = []
        var cursor: TodoList? = list
        while let c = cursor {
            path.append(c)
            cursor = c.parent
        }
        return path.reversed()
    }

    /// The root ancestor highlighted in the first chip row.
    private var selectedRootID: UUID? {
        if let c = current { return ancestry(of: c).first?.id ?? c.id }
        return nil
    }

    /// Total tasks under a folder, including all descendant subfolders
    /// (direct tasks + every child subtree) — a parent chip shows the whole
    /// branch's workload at a glance.
    private func totalItems(of list: TodoList) -> Int {
        list.items.count + list.children.reduce(0) { $0 + totalItems(of: $1) }
    }

    // MARK: - Shown tasks

    /// Every task in the current scope (folder or all), tag-filtered & sorted.
    private var visibleItems: [TodoItem] {
        var base: [TodoItem]
        if let current {
            base = current.items
        } else {
            base = Array(items)
        }
        if let filterTagID {
            base = base.filter { $0.tags.contains { $0.id == filterTagID } }
        }
        return current != nil ? base.sorted(by: sortInList) : base.sorted(by: sortFlat)
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
                        breadcrumbChips
                        childChipsRow
                        taskList
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
                ToolbarItem(placement: .topBarTrailing) { tagFilterMenu }
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
                refreshDisplayItems()
            }
            .onChange(of: items.count) { _ in refreshDisplayItems() }
            .onChange(of: currentListID) { _ in refreshDisplayItems() }
            .onChange(of: filterTagID) { _ in refreshDisplayItems() }
        }
    }

    // MARK: - Top chips (folder navigation)

    /// First row of chips: "全部" + root folders. Tap to navigate into a
    /// folder; every folder chip is also a drop target for task moves.
    private var breadcrumbChips: some View {
        let roots = rootLists
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(
                    title: "全部",
                    icon: "tray.full",
                    isSelected: currentListID == nil,
                    count: items.count,
                    list: nil
                ) { currentListID = nil; filterTagID = nil }
                ForEach(roots) { list in
                    chip(
                        title: list.name,
                        icon: list.iconName ?? "checklist",
                        color: list.color,
                        isSelected: selectedRootID == list.id,
                        count: totalItems(of: list),
                        list: list
                    ) { currentListID = list.id }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    /// When inside a folder that has children, show its subfolders as a second
    /// chip row plus a "返回上级" back chip (nested navigation by level).
    @ViewBuilder
    private var childChipsRow: some View {
        if let current, !current.children.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    backChip {
                        currentListID = current.parent?.id
                    }
                    ForEach(current.children.sorted { $0.position < $1.position }) { list in
                        chip(
                            title: list.name,
                            icon: list.iconName ?? "checklist",
                            color: list.color,
                            isSelected: currentListID == list.id,
                            count: totalItems(of: list),
                            list: list
                        ) { currentListID = list.id }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }
        }
    }

    /// A single navigation/filter chip. When `list` is non-nil it is also a
    /// drop target, letting you drag a task onto the chip to move it there.
    /// `count` (when > 0) renders a small task-count badge so you can see at a
    /// glance which folders still have tasks; empty ones show no badge.
    private func chip(title: String, icon: String, color: Color = Color.accentColor,
                      isSelected: Bool, count: Int? = nil, list: TodoList?,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(isSelected ? Color.white : color)
                Text(title)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(isSelected ? Color.white.opacity(0.28) : color.opacity(0.16)))
                        .foregroundStyle(isSelected ? Color.white : color)
                }
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? color : Color.clear)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .overlay {
                Capsule()
                    .stroke(isSelected ? .clear : Color.secondary.opacity(0.35), lineWidth: 1)
            }
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .dropDestination(for: String.self) { payloads, _ in
            guard let targetList = list, let id = Self.itemID(fromPayloads: payloads) else { return false }
            return move(itemID: id, to: targetList)
        }
    }

    private func backChip(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("上级", systemImage: "arrow.uturn.backward")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.secondary.opacity(0.12))
                .foregroundStyle(Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Task list (single stream)

    private var taskList: some View {
        List {
            if displayItems.isEmpty, let current {
                EmptyListDropSlot()
                    .dropDestination(for: String.self) { payloads, _ in
                        guard let id = Self.itemID(fromPayloads: payloads) else { return false }
                        return move(itemID: id, to: current)
                    }
            } else {
                ForEach(displayItems) { item in
                    TodoRow(item: item) { toggle(item) }
                        .draggable(Self.itemDragPrefix + item.id.uuidString)
                        .dropDestination(for: String.self) { payloads, _ in
                            guard let id = Self.itemID(fromPayloads: payloads) else { return false }
                            return reorder(itemID: id, before: item)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { deleteOne(item) } label: {
                                Label("删除", systemImage: "trash")
                            }
                            moveSwipeButton(for: item)
                        }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Drag & drop payload helpers

    private static func itemID(fromPayloads payloads: [String]) -> UUID? {
        guard let raw = payloads.first, raw.hasPrefix(Self.itemDragPrefix) else { return nil }
        return UUID(uuidString: String(raw.dropFirst(Self.itemDragPrefix.count)))
    }

    private func findItem(id: UUID) -> TodoItem? {
        items.first { $0.id == id }
    }

    /// Move a dragged task into a folder (cross-folder move). Appends to the
    /// target list. Uses a single write-back so the drop is consistent.
    private func move(itemID: UUID, to list: TodoList) -> Bool {
        guard let item = findItem(id: itemID), item.list?.id != list.id else { return true }
        item.list = list
        item.position = list.items.count
        try? storage.save()
        refreshDisplayItems()
        return true
    }

    /// Reorder (or same-list insert) a dragged task before a target task.
    /// Rebuilds the target list's order in memory, writes positions back once.
    private func reorder(itemID: UUID, before target: TodoItem) -> Bool {
        guard let dragged = findItem(id: itemID), dragged.id != target.id else { return true }
        guard let targetList = target.list else { return true }

        // If the dragged task was already in this list, remove it first so the
        // insert lands at the expected slot.
        var ordered = targetList.items.sorted(by: sortInList)
        if let from = ordered.firstIndex(where: { $0.id == dragged.id }) {
            ordered.remove(at: from)
        }
        dragged.list = targetList
        if let to = ordered.firstIndex(where: { $0.id == target.id }) {
            ordered.insert(dragged, at: to)
        } else {
            ordered.append(dragged)
        }
        for (index, item) in ordered.enumerated() {
            item.position = index
        }
        try? storage.save()
        refreshDisplayItems()
        return true
    }

    // MARK: - Display sync

    private func refreshDisplayItems() {
        displayItems = visibleItems
    }

    // MARK: - Flat tag filter menu

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
        refreshDisplayItems()
    }

    private func deleteOne(_ item: TodoItem) {
        NotificationService.shared.cancelReminder(id: item.id.uuidString)
        try? storage.delete(item)
        refreshDisplayItems()
    }

    private func prefix(_ depth: Int) -> String {
        String(repeating: "　", count: depth)
    }

    // MARK: - Moving between lists (left swipe)

    private func moveSwipeButton(for item: TodoItem) -> some View {
        Menu {
            ForEach(flattenedForMenu, id: \.list.id) { pair in
                Button {
                    move(itemID: item.id, to: pair.list)
                } label: {
                    Text(prefix(pair.depth) + pair.list.name)
                }
            }
        } label: {
            Label("移动", systemImage: "folder")
        }
        .tint(.gray)
    }

    /// All lists flattened with depth for the "移动" swipe menu indentation.
    private var flattenedForMenu: [(list: TodoList, depth: Int)] {
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