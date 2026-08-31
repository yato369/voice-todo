import SwiftUI
import SwiftData
import UIKit

// MARK: - UIKit UICollectionView drag & drop list
//
// SwiftUI `.onDrag`/`.onDrop` inside a `List` proved unreliable on-device,
// so the *grouped* view renders its rows through this UIKit component.
// `UICollectionView` has first-class, system-backed drag & drop that supports
// both in-section reordering and cross-section moves reliably.
//
// Model mutations (list reassignment + reorder persists) are delegated back to
// the SwiftUI container via the `onMove` closure. The diffable snapshot is
// rebuilt every time the parent re-renders (`updateUIView`).

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

    let sections: [Section]
    let onToggle: (TodoItem) -> Void
    let onDelete: (TodoItem) -> Void
    let onCollapse: (UUID) -> Void
    /// Move `item` into list `toListID` at visual index `toIndex`.
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
        cv.remembersLastFocusedIndexPath = true
        cv.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 100, right: 0)  // room for FABs
        cv.register(ItemCell.self, forCellWithReuseIdentifier: ItemCell.reuseID)
        cv.register(
            HeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: HeaderView.reuseID
        )
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

        func configure(with section: Section,
                       collapsed: Bool,
                       onCollapse: @escaping () -> Void) {
            let root = HeaderSwiftUI(section: section, collapsed: collapsed) { onCollapse() }
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
        let collapsed: Bool
        let onCollapse: () -> Void

        var body: some View {
            HStack(spacing: 6) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
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
            .animation(.easeInOut(duration: 0.2), value: collapsed)
        }
    }

    // MARK: - Coordinator (data source + drag/drop delegate)

    final class Coordinator: NSObject, UICollectionViewDataSource,
        UICollectionViewDelegate, UICollectionViewDragDelegate,
        UICollectionViewDropDelegate {

        var parent: DragDropListView

        init(parent: DragDropListView) {
            self.parent = parent
        }

        func apply(using cv: UICollectionView) {
            cv.reloadData()
        }

        // MARK: Data source

        func numberOfSections(in cv: UICollectionView) -> Int {
            parent.sections.count
        }

        func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            let sec = parent.sections[section]
            return sec.collapsed ? 0 : sec.items.count
        }

        func collectionView(
            _ cv: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            let cell = cv.dequeueReusableCell(withReuseIdentifier: ItemCell.reuseID, for: indexPath)
                as! ItemCell
            let sec = parent.sections[indexPath.section]
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
            let sec = parent.sections[indexPath.section]
            header.configure(with: sec, collapsed: sec.collapsed) { [weak self] in
                if let id = sec.listID {
                    self?.parent.onCollapse(id)
                }
            }
            return header
        }

        // MARK: Delegate

        func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            cv.deselectItem(at: indexPath, animated: true)
        }

        func collectionView(
            _ cv: UICollectionView,
            trailingSwipeActionsConfigurationForItemAt indexPath: IndexPath
        ) -> UISwipeActionsConfiguration? {
            let sec = parent.sections[indexPath.section]
            guard indexPath.item < sec.items.count else { return nil }
            let item = sec.items[indexPath.item]
            let del = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
                self?.parent.onDelete(item)
                completion(true)
            }
            return UISwipeActionsConfiguration(actions: [del])
        }

        // MARK: Drag

        func collectionView(
            _ cv: UICollectionView,
            itemsForBeginning session: UIDragSession,
            at indexPath: IndexPath
        ) -> [UIDragItem] {
            let sec = parent.sections[indexPath.section]
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
            guard let destination = coordinator.destinationIndexPath else { return }
            guard let item = coordinator.items.first else { return }
            let sourceItem = item.dragItem.localObject as? TodoItem
            let targetSection = parent.sections[destination.section]
            let toIndex = destination.item

            // Ask SwiftUI to persist the move.
            if let source = sourceItem {
                parent.onMove(source, targetSection.listID, toIndex)
                // Reload is driven by the parent re-rendering via updateUIView.
                coordinator.drop(item.dragItem, toItemAt: destination)
            } else {
                cv.reloadData()
            }
        }
    }
}