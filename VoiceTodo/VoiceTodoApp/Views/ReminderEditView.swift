import SwiftUI
import SwiftData

struct ReminderEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: TodoItem

    @State private var date: Date = Date().addingTimeInterval(60 * 60)

    private var storage: StorageServiceProtocol { StorageService(context: modelContext) }

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
        try? storage.save()
        if let id = item.id {
            NotificationService.shared.scheduleReminder(
                id: id.uuidString,
                title: "待办提醒",
                body: item.text,
                at: date
            )
        }
        dismiss()
    }

    private func removeReminder() {
        item.reminderDate = nil
        try? storage.save()
        if let id = item.id {
            NotificationService.shared.cancelReminder(id: id.uuidString)
        }
        dismiss()
    }
}
