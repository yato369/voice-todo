import SwiftUI
import SwiftData

struct ReminderEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: TodoItem

    @State private var date: Date

    private var storage: StorageServiceProtocol { StorageService(context: modelContext) }

    /// Default picker shows the current calendar date, so editing a reminder
    /// naturally keeps the calendar date and reminder time in sync.
    init(item: TodoItem) {
        self.item = item
        _date = State(initialValue: item.reminderDate ?? item.calendarDate)
    }

    var body: some View {
        Form {
            Section("提醒时间") {
                DatePicker("时间", selection: $date)
            }

            if item.reminderDate != nil {
                Section {
                    Button("移除提醒", role: .destructive) {
                        removeReminder()
                    }
                }
            }
        }
        .navigationTitle("设置提醒")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    saveReminder()
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    dismiss()
                }
            }
        }
    }

    private func saveReminder() {
        Task {
            _ = await NotificationService.shared.requestAuthorization()
        }
        item.reminderDate = date
        item.date = date
        try? storage.save()
        NotificationService.shared.scheduleReminder(
            id: item.id.uuidString,
            title: "待办提醒",
            body: item.text,
            at: date
        )
        dismiss()
    }

    private func removeReminder() {
        item.reminderDate = nil
        try? storage.save()
        NotificationService.shared.cancelReminder(id: item.id.uuidString)
        dismiss()
    }
}
