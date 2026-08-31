import SwiftUI
import SwiftData
import AVFoundation

struct TodoDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TodoList.position) private var lists: [TodoList]
    @Query(sort: \Tag.createdAt) private var tags: [Tag]
    @Bindable var item: TodoItem

    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var newTagName: String = ""

    private var storage: StorageServiceProtocol { StorageService(context: modelContext) }

    /// Flattened list tree with depth, so the picker shows the hierarchy.
    private var flattenedLists: [(list: TodoList, depth: Int)] {
        var out: [(TodoList, Int)] = []
        func walk(_ roots: [TodoList], _ depth: Int) {
            for l in roots.sorted(by: { $0.position < $1.position }) {
                out.append((l, depth))
                walk(l.children, depth + 1)
            }
        }
        walk(lists.filter { $0.parent == nil }, 0)
        return out
    }

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
                audioSection(fileName)
            }

            listSection
            tagSection
            reminderSection
            deleteSection
        }
        .navigationTitle("详情")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            audioPlayer?.stop()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func audioSection(_ fileName: String) -> some View {
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

    @ViewBuilder
    private var listSection: some View {
        Section("列表") {
            if flattenedLists.isEmpty {
                Text("未创建列表")
                    .foregroundStyle(.secondary)
            } else {
                Picker("归属列表", selection: Binding(
                    get: { item.list?.id ?? flattenedLists.first?.list.id },
                    set: { id in
                        item.list = lists.first { $0.id == id }
                        try? storage.save()
                    }
                )) {
                    ForEach(flattenedLists, id: \.list.id) { entry in
                        Text(String(repeating: "　", count: entry.depth) + "・" + entry.list.name)
                            .tag(Optional(entry.list.id))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var tagSection: some View {
        Section("标签") {
            ForEach(tags) { tag in
                tagRow(tag)
            }
            HStack {
                TextField("新标签", text: $newTagName)
                Button("添加") { addTag() }
                    .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func tagRow(_ tag: Tag) -> some View {
        let isOn = item.tags.contains { $0.id == tag.id }
        let hasColor = tag.color != Color.accentColor
        return Button {
            toggleTag(tag)
        } label: {
            HStack {
                Label(tag.name, systemImage: hasColor ? "tag.fill" : "tag")
                    .foregroundStyle(hasColor ? tag.color : Color.primary)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    @ViewBuilder
    private var reminderSection: some View {
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
    }

    @ViewBuilder
    private var deleteSection: some View {
        Section {
            Button("删除待办", role: .destructive) {
                NotificationService.shared.cancelReminder(id: item.id.uuidString)
                try? storage.delete(item)
            }
        }
    }

    private func toggleTag(_ tag: Tag) {
        if let index = item.tags.firstIndex(where: { $0.id == tag.id }) {
            item.tags.remove(at: index)
        } else {
            item.tags.append(tag)
        }
        try? storage.save()
    }

    private func addTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let existing = tags.first { $0.name == trimmed }
        let tag = existing ?? {
            let newTag = Tag(name: trimmed)
            modelContext.insert(newTag)
            return newTag
        }()
        if !item.tags.contains(where: { $0.id == tag.id }) {
            item.tags.append(tag)
        }
        newTagName = ""
        try? modelContext.save()
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
