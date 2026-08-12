import SwiftUI
import SwiftData

/// Built-in calendar. Renders the same TodoItem data as the list view, so
/// both views are naturally consistent (single source of truth).
struct CalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TodoItem.createdAt, order: .reverse) private var items: [TodoItem]

    @State private var displayedMonth: Date = Calendar.current.startOfDay(for: Date())
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var storage: StorageServiceProtocol { StorageService(context: modelContext) }

    private var itemsOnSelectedDate: [TodoItem] {
        items
            .filter { calendar.isDate($0.createdAt, inSameDayAs: selectedDate) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                monthHeader
                weekdayHeader
                dayGrid

                Divider()

                List {
                    if itemsOnSelectedDate.isEmpty {
                        Text("当天没有待办")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(itemsOnSelectedDate) { item in
                            TodoRow(item: item) {
                                toggle(item)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                let item = itemsOnSelectedDate[index]
                                if let id = item.id {
                                    NotificationService.shared.cancelReminder(id: id.uuidString)
                                }
                                try? storage.delete(item)
                            }
                        }
                    }
                }
            }
            .navigationTitle("日历")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("今天") {
                        selectedDate = calendar.startOfDay(for: Date())
                        displayedMonth = calendar.startOfDay(for: Date())
                    }
                }
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(displayedMonth.formatted(.dateTime.year().month()))
                .font(.headline)
            Spacer()
            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding()
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { day in
                Text(day)
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
    }

    private var dayGrid: some View {
        let cells = monthCells()
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(cells, id: \.self) { date in
                DayCell(
                    date: date,
                    isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                    isToday: calendar.isDateInToday(date),
                    hasItems: !items(for: date).isEmpty
                )
                .onTapGesture {
                    selectedDate = date
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private func shiftMonth(_ offset: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: offset, to: displayedMonth) ?? displayedMonth
    }

    /// Returns dates for the visible grid, padded to complete weeks.
    private func monthCells() -> [Date] {
        guard
            let range = calendar.range(of: .day, in: .month, for: displayedMonth)
        else { return [] }

        let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))!
        let leadingBlanks = calendar.component(.weekday, from: firstOfMonth) - 1

        var cells: [Date] = []
        for _ in 0..<leadingBlanks {
            cells.append(Date.distantPast)
        }
        for day in 1...range.count {
            cells.append(calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth)!)
        }
        return cells
    }

    private func items(for date: Date) -> [TodoItem] {
        items.filter { calendar.isDate($0.createdAt, inSameDayAs: date) }
    }

    private func toggle(_ item: TodoItem) {
        item.isCompleted.toggle()
        item.completedAt = item.isCompleted ? Date() : nil
        if item.isCompleted, let id = item.id {
            NotificationService.shared.cancelReminder(id: id.uuidString)
        }
        try? storage.save()
    }
}

/// A single calendar day cell.
struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let hasItems: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor : Color.clear)

            VStack(spacing: 3) {
                if date == .distantPast {
                    Spacer()
                } else {
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.subheadline)
                        .fontWeight(isToday ? .bold : .regular)
                        .foregroundStyle(
                            isSelected ? Color.white :
                                isToday ? Color.accentColor : Color.primary
                        )
                    Circle()
                        .fill(isSelected ? Color.white : Color.accentColor.opacity(0.6))
                        .frame(width: 5, height: 5)
                        .opacity(hasItems ? 1 : 0)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
    }
}
