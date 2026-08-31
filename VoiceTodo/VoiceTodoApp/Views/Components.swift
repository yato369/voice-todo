import SwiftUI

/// Formats seconds as mm:ss or h:mm:ss.
func formatDuration(_ interval: TimeInterval) -> String {
    let total = Int(interval)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%02d:%02d", minutes, seconds)
}

/// A reusable row for a to-do item. Used by both list and calendar views.
struct TodoRow: View {
    let item: TodoItem
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isCompleted ? Color.green : Color.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Text(item.createdAt, format: .dateTime.month().day().hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let reminder = item.reminderDate {
                        Label("\(reminder.formatted(.dateTime.hour().minute()))", systemImage: "bell")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if !item.imageFileNames.isEmpty {
                        Label("\(item.imageFileNames.count)", systemImage: "photo.on.rectangle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !item.links.isEmpty {
                        Label("\(item.links.count)", systemImage: "link")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            NavigationLink {
                TodoDetailView(item: item)
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

/// A dashed placeholder row shown under an empty list so the list remains a
/// valid drag-and-drop target. Not itself draggable.
struct EmptyListDropSlot: View {
    var body: some View {
        HStack {
            Spacer()
            Label("＋ 拖到这里添加", systemImage: "plus")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4]))
                .foregroundStyle(.quaternary)
        }
        .frame(maxWidth: .infinity)
    }
}
