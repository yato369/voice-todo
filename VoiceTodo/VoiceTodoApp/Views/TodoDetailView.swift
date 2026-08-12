import SwiftUI
import SwiftData
import AVFoundation

struct TodoDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var item: TodoItem

    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false

    private var storage: StorageServiceProtocol { StorageService(context: modelContext) }

    var body: some View {
        Form {
            Section("文字") {
                TextField("待办内容", text: $item.text, axis: .vertical)
                    .lineLimit(1...6)
                    .onChange(of: item.text) { _, _ in
                        try? storage.save()
                    }
            }

            if let fileName = item.audioFileName {
                Section("录音") {
                    Button {
                        togglePlayback(fileName)
                    } label: {
                        Label(
                            isPlaying ? "停止播放" : "播放录音",
                            systemImage: isPlaying ? "stop.fill" : "play.fill"
                        )
                    }
                }
            }

            Section("提醒") {
                if let reminder = item.reminderDate {
                    Label(reminder.formatted(), systemImage: "bell.fill")
                        .foregroundStyle(.orange)
                } else {
                    Text("未设置提醒")
                        .foregroundStyle(.secondary)
                }
                NavigationLink {
                    ReminderEditView(item: item)
                } label: {
                    Text(item.reminderDate == nil ? "添加提醒" : "修改提醒")
                }
            }

            Section {
                Button("删除待办", role: .destructive) {
                    if let id = item.id {
                        NotificationService.shared.cancelReminder(id: id.uuidString)
                    }
                    try? storage.delete(item)
                }
            }
        }
        .navigationTitle("详情")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            audioPlayer?.stop()
        }
    }

    private func togglePlayback(_ fileName: String) {
        if isPlaying {
            audioPlayer?.stop()
            isPlaying = false
            return
        }
        guard let url = audioFileURL(fileName) else { return }
        audioPlayer = try? AVAudioPlayer(contentsOf: url)
        audioPlayer?.play()
        isPlaying = true
    }

    private func audioFileURL(_ fileName: String) -> URL? {
        let docs = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return docs?.appendingPathComponent("Recordings").appendingPathComponent(fileName)
    }
}
