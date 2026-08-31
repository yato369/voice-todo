import SwiftUI
import SwiftData
import UIKit

// MARK: - UIKit UICollectionView drag & drop list
//
// SwiftUI `.onDrag`/`.onDrop` inside a `List` proved unreliable on-device, so
// the *grouped* view renders its rows through this UIKit component.
//
// The data source is rebuilt straight from the SwiftData `ModelContext` on
// every `apply()` — the collection view never reads a stale SwiftUI snapshot.
// After a drop we mutate the model, persist, then immediately `apply()` so the
// on-screen order (and cross-list move) reflects the persisted state.

struct DragDropListView: UIViewRepresentable {
    /// One rendered section = one list at some depth.
    struct Section {
        let listID: UUID?
        let name: String
        let color: Color
        let icon: String
        let depth: Int
        let count: Int
        let collapsed: Bool
        let items: [TodoItem]
    }

    let modelContext: ModelContext
    let collapsed: Set<UUID>
    let onToggle: (TodoItem) -> Void
    let onDelete: (TodoItem) -> Void
    let onCollapse: (UUID) -> Void
    /// Move `item` into list `toListID` (nil = unassigned) at `toIndex`.
    let onMove: (_ item: TodoItem, _ toListID: UUID?, _ toIndex: Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewCompositionalLayout { _, env in
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(64)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(64)
            )
            let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 6
            section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0)
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(44)
                ),
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )
            section.boundarySupplementaryItems = [header]
            return section
        }
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.delegate = context.coordinator
        cv.dataSource = context.coordinator
        cv.dragDelegate = context.coordinator
        cv.dropDelegate = context.coordinator
        cv.dragInteractionEnabled = true
        cv.reorderingCadence = .immediate
        cv.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 100, right: 0)  // room for FABs
        cv.register(ItemCell.self, forCellWithReuseIdentifier: ItemCell.reuseID)
        cv.register(
            HeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: HeaderView.reuseID
        )
        context.coordinator.apply(using: cv)
        return cv
    }

    func updateUIView(_ uiView: UICollectionView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(using: uiView)
    }

    // MARK: - Hosting cell

    final class ItemCell: UICollectionViewCell {
        static let reuseID = "ItemCell"
        private var host: UIHostingController<AnyView>?

        func configure(with item: TodoItem, onToggle: @escaping () -> Void) {
            let root = TodoRow(item: item, onToggle: { onToggle() })
                .id(item.id)
            if let host {
                host.rootView = AnyView(root)
            } else {
                let h = UIHostingController(rootView: AnyView(root))
                h.view.translatesAutoresizingMaskIntoConstraints = false
                h.view.backgroundColor = .clear
                contentView.addSubview(h.view)
                NSLayoutConstraint.activate([
                    h.view.topAnchor.constraint(equalTo: contentView.topAnchor),
                    h.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                    h.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                    h.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
                ])
                host = h
            }
            // Keep the row's own SwiftUI controls interactive (toggle + detail
            // navigation). Drag & drop still works via the cell's long press.
        }
    }

    // MARK: - Hosting header

    final class HeaderView: UICollectionReusableView {
        static let reuseID = "HeaderView"
        private var host: UIHostingController<AnyView>?

        func configure(with section: Section, onCollapse: @escaping () -> Void) {
            let root = HeaderSwiftUI(section: section) { onCollapse() }
            if let host {
                host.rootView = AnyView(root)
            } else {
                let h = UIHostingController(rootView: AnyView(root))
                h.view.translatesAutoresizingMaskIntoConstraints = false
                h.view.backgroundColor = .clear
                addSubview(h.view)
                NSLayoutConstraint.activate([
                    h.view.topAnchor.constraint(equalTo: topAnchor),
                    h.view.bottomAnchor.constraint(equalTo: bottomAnchor),
                    h.view.leadingAnchor.constraint(equalTo: leadingAnchor),
                    h.view.trailingAnchor.constraint(equalTo: trailingAnchor)
                ])
                host = h
            }
        }
    }

    /// SwiftUI view for a section header (chevron + list dot/icon/name + count).
    struct HeaderSwiftUI: View {
        let section: Section
        let onCollapse: () -> Void

        var body: some View {
            HStack(spacing: 6) {
                Image(systemName: section.collapsed ? "chevron.right" : "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 14)
                if section.depth > 0 {
                    Color.clear.frame(width: CGFloat(section.depth) * 16, height: 1)
                }
                Circle().fill(section.color).frame(width: 10, height: 10)
                Image(systemName: section.icon)
                Text(section.name).lineLimit(1)
                Spacer()
                Text("\(section.count)").font(.caption2).foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture { onCollapse() }
            .animation(.easeInOut(duration: 0.2), value: section.collapsed)
        }
    }

    // MARK: - Coordinator (data source + drag/drop delegate)

    final class Coordinator: NSObject, UICollectionViewDataSource,
        UICollectionViewDelegate, UICollectionViewDragDelegate,
        UICollectionViewDropDelegate {

        var parent: DragDropListView
        var sections: [Section] = []

        init(parent: DragDropListView) {
            self.parent = parent
        }

        // MARK: Data reconstruction (source of truth = the persistent store)

        /// Rebuild section data straight from the model context.
        func apply(using cv: UICollectionView) {
            sections = rebuildSections()
            cv.reloadData()
        }

        private func rebuildSections() -> [Section] {
            let context = parent.modelContext
            let lists = (try? context.fetch(FetchDescriptor<TodoList>(
                sortBy: [SortDescriptor(\.position)]
            ))) ?? []
            let allItems = (try? context.fetch(FetchDescriptor<TodoItem>())) ?? []

            func sortInList(_ a: TodoItem, _ b: TodoItem) -> Bool {
                if a.isCompleted != b.isCompleted { return !a.isCompleted }
                if a.position != b.position { return a.position < b.position }
                return a.createdAt > b.createdAt
            }
            func itemsFor(_ id: UUID?) -> [TodoItem] {
                allItems.filter { $0.list?.id == id }.sorted(by: sortInList)
            }

            var flat: [(TodoList, Int)] = []
            func walk(_ roots: [TodoList], _ depth: Int) {
                for list in roots {
                    flat.append((list, depth))
                    walk(list.children.sorted { $0.position < $1.position }, depth + 1)
                }
            }
            walk(lists.filter { $0.parent == nil }.sorted { $0.position < $1.position }, 0)

            var out: [Section] = flat.map { (list, depth) in
                Section(
                    listID: list.id,
                    name: list.name,
                    color: list.color,
                    icon: list.iconName ?? "checklist",
                    depth: depth,
                    count: itemsFor(list.id).count,
                    collapsed: parent.collapsed.contains(list.id),
                    items: itemsFor(list.id)
                )
            }
            let unassigned = itemsFor(nil)
            if !unassigned.isEmpty {
                out.append(Section(listID: nil, name: "未分类", color: .gray,
                                   icon: "circle", depth: 0, count: unassigned.count,
                                   collapsed: false, items: unassigned))
            }
            return out
        }

        /// Flattened list names for the "move to..." swipe action.
        private func listChoices() -> [(UUID, String, Int)] {
            let context = parent.modelContext
            let lists = (try? context.fetch(FetchDescriptor<TodoList>(
                sortBy: [SortDescriptor(\.position)]
            ))) ?? []
            var flat: [(TodoList, Int)] = []
            func walk(_ roots: [TodoList], _ depth: Int) {
                for list in roots {
                    flat.append((list, depth))
                    walk(list.children.sorted { $0.position < $1.position }, depth + 1)
                }
            }
            walk(lists.filter { $0.parent == nil }.sorted { $0.position < $1.position }, 0)
            return flat.map { ($0.0.id, $0.1, $0.0.name) }
        }

        // MARK: Data source

        func numberOfSections(in cv: UICollectionView) -> Int {
            sections.count
        }

        func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            let sec = sections[section]
            return sec.collapsed ? 0 : sec.items.count
        }

        func collectionView(
            _ cv: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            let cell = cv.dequeueReusableCell(withReuseIdentifier: ItemCell.reuseID, for: indexPath)
                as! ItemCell
            let sec = sections[indexPath.section]
            let item = sec.items[indexPath.item]
            cell.configure(with: item) { [weak self] in
                self?.parent.onToggle(item)
            }
            return cell
        }

        func collectionView(
            _ cv: UICollectionView,
            viewForSupplementaryElementOfKind kind: String,
            at indexPath: IndexPath
        ) -> UICollectionReusableView {
            let header = cv.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: HeaderView.reuseID,
                for: indexPath
            ) as! HeaderView
            let sec = sections[indexPath.section]
            header.configure(with: sec) { [weak self] in
                if let id = sec.listID {
                    self?.parent.onCollapse(id)
                }
            }
            return header
        }

        // MARK: Delegate — swipe actions (delete + move)

        func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            cv.deselectItem(at: indexPath, animated: true)
        }

        func collectionView(
            _ cv: UICollectionView,
            trailingSwipeActionsConfigurationForItemAt indexPath: IndexPath
        ) -> UISwipeActionsConfiguration? {
            let sec = sections[indexPath.section]
            guard indexPath.item < sec.items.count else { return nil }
            let item = sec.items[indexPath.item]

            let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
                self?.parent.onDelete(item)
                completion(true)
            }

            let move = UIContextualAction(style: .normal, title: "移动") { [weak self] _, _, completion in
                self?.presentMoveOptions(for: item, on: cv)
                completion(true)
            }
            move.backgroundColor = .systemGray

            return UISwipeActionsConfiguration(actions: [delete, move])
        }

        private func presentMoveOptions(for item: TodoItem, on cv: UICollectionView) {
            let alert = UIAlertController(title: "移动到…", message: nil, preferredStyle: .actionSheet)
            alert.popoverPresentationController?.sourceView = cv
            for (id, depth, name) in listChoices() {
                let title = String(repeating: "　", count: depth) + name
                alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                    self?.parent.onMove(item, id, Int.max)
                })
            }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
            topViewController(on: cv)?.present(alert, animated: true)
        }

        private func topViewController(on cv: UICollectionView) -> UIViewController? {
            var vc = cv.window?.rootViewController
            while let presented = vc?.presentedViewController {
                vc = presented
            }
            return vc
        }

        // MARK: Drag

        func collectionView(
            _ cv: UICollectionView,
            itemsForBeginning session: UIDragSession,
            at indexPath: IndexPath
        ) -> [UIDragItem] {
            let sec = sections[indexPath.section]
            guard indexPath.item < sec.items.count else { return [] }
            let item = sec.items[indexPath.item]
            let provider = NSItemProvider(object: item.id.uuidString as NSString)
            let dragItem = UIDragItem(itemProvider: provider)
            dragItem.localObject = item
            return [dragItem]
        }

        // MARK: Drop

        func collectionView(
            _ cv: UICollectionView,
            dropSessionDidUpdate session: UIDropSession,
            withDestinationIndexPath proposalDestinationIndexPath: IndexPath?
        ) -> UICollectionViewDropProposal {
            return UICollectionViewDropProposal(
                operation: .move,
                intent: .insertAtDestinationIndexPath
            )
        }

        func collectionView(
            _ cv: UICollectionView,
            performDropWith coordinator: UICollectionViewDropCoordinator
        ) {
            guard let destination = coordinator.destinationIndexPath,
                  destination.section < sections.count else { return }
            guard let draggedItem = coordinator.items.first,
                  let source = draggedItem.dragItem.localObject as? TodoItem else {
                cv.reloadData()
                return
            }
            let targetListID = sections[destination.section].listID
            let toIndex = destination.item

            // 1. Persist the move through SwiftUI (updates model + saves).
            parent.onMove(source, targetListID, toIndex)

            // 2. Rebuild from the just-persisted model so the UI and storage
            //    are guaranteed in sync (no stale snapshot).
            apply(using: cv)

            // 3. Finalize the drop animation at the destination.
            coordinator.drop(draggedItem.dragItem, toItemAt: destination)
        }
    }
}