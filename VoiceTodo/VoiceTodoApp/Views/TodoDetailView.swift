import SwiftUI
import SwiftData
import AVFoundation
import PhotosUI

struct TodoDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TodoList.position) private var lists: [TodoList]
    @Query(sort: \Tag.createdAt) private var tags: [Tag]
    @Bindable var item: TodoItem

    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var newTagName: String = ""
    @State private var newLink: String = ""
    @State private var pickerItems: [PhotosPickerItem] = []

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
            imageSection
            linkSection
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
    private var imageSection: some View {
        Section("图片") {
            if item.imageFileNames.isEmpty {
                Text("暂无图片")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(item.imageFileNames, id: \.self) { name in
                        imageThumb(name)
                    }
                }
                .padding(.vertical, 4)
            }
            PhotosPicker(selection: $pickerItems, matching: .images) {
                Label("添加图片", systemImage: "photo.badge.plus")
            }
            .onChange(of: pickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                let toLoad = newItems
                pickerItems = []
                Task { await loadPickedImages(toLoad) }
            }
        }
    }

    private func imageThumb(_ name: String) -> some View {
        Group {
            if let image = UIImage(contentsOfFile: ImageStore.url(for: name).path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 90)
                    .clipped()
                    .cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(height: 90)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                deleteImage(name)
            } label: {
                Label("删除图片", systemImage: "trash")
            }
        }
    }

    private func loadPickedImages(_ picked: [PhotosPickerItem]) async {
        for pickerItem in picked {
            if let data = try? await pickerItem.loadTransferable(type: Data.self),
               let name = ImageStore.save(data) {
                item.imageFileNames.append(name)
            }
        }
        try? storage.save()
    }

    private func deleteImage(_ name: String) {
        ImageStore.delete(name)
        item.imageFileNames.removeAll { $0 == name }
        try? storage.save()
    }

    @ViewBuilder
    private var linkSection: some View {
        Section("链接") {
            if item.links.isEmpty {
                Text("暂无链接")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(item.links, id: \.self) { link in
                    if let url = URL(string: link) {
                        Link(destination: url) {
                            Label(linkLabel(link), systemImage: "link")
                                .lineLimit(1)
                        }
                    } else {
                        Text(link)
                            .font(.subheadline)
                    }
                }
                .onDelete { offsets in
                    item.links.remove(atOffsets: offsets)
                    try? storage.save()
                }
            }
            HStack {
                TextField("添加链接（如 example.com）", text: $newLink)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("添加") { addLink() }
                    .disabled(newLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    /// Short display label for a URL: host + trimmed path.
    private func linkLabel(_ link: String) -> String {
        if let url = URL(string: link) {
            let host = url.host() ?? link
            let path = url.path()
            return path.isEmpty ? host : host + path
        }
        return link
    }

    private func addLink() {
        var link = newLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !link.isEmpty else { return }
        if !link.hasPrefix("http://") && !link.hasPrefix("https://") {
            link = "https://" + link
        }
        guard URL(string: link) != nil else { return }
        item.links.append(link)
        newLink = ""
        try? storage.save()
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
