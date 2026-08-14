import SwiftUI
import SwiftData

/// Record a voice memo or type text, then save it as a to-do item.
struct RecordView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let mode: InputMode

    @StateObject private var recorder = AudioRecorder()
    @State private var phase: Phase = .idle
    @State private var errorMessage: String?
    @State private var textInput: String = ""
    @FocusState private var isTextEditorFocused: Bool

    private let transcriber: SpeechTranscriberProtocol = SpeechTranscriber()
    private var storage: StorageServiceProtocol { StorageService(context: modelContext) }

    enum Phase {
        case idle
        case recording
        case transcribing
    }

    enum InputMode {
        case voice
        case text
    }

    private var title: String {
        switch mode {
        case .voice: return "语音输入"
        case .text: return "文字输入"
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if mode == .voice {
                    voiceContent
                } else {
                    textContent
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        recorder.stopRecording()
                        dismiss()
                    }
                }
            }
            .task {
                _ = await SpeechTranscriber.requestAuthorization()
            }
        }
    }

    // MARK: - Voice input

    @ViewBuilder
    private var voiceContent: some View {
        VStack(spacing: 32) {
            Spacer()

            if phase == .transcribing {
                ProgressView("正在转写…")
                    .font(.headline)
            } else {
                Text(phase == .recording ? "正在录音…" : "点击开始，说一句话")
                    .font(.headline)
                    .foregroundStyle(phase == .recording ? Color.red : Color.secondary)

                Text(formatDuration(recorder.currentTime))
                    .font(.system(size: 56, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            Button {
                handleVoiceTap()
            } label: {
                Image(systemName: phase == .recording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 88))
                    .foregroundStyle(phase == .recording ? Color.red : Color.accentColor)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(phase == .transcribing)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
        }
    }

    // MARK: - Text input

    @ViewBuilder
    private var textContent: some View {
        VStack(spacing: 16) {
            TextEditor(text: $textInput)
                .focused($isTextEditorFocused)
                .font(.body)
                .padding(12)
                .frame(maxHeight: .infinity)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .overlay(alignment: .topLeading) {
                    if textInput.isEmpty {
                        Text("在这里输入待办事项…")
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                saveTextInput()
            } label: {
                Label("保存", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.horizontal)
        }
        .padding(.horizontal, 8)
        .onAppear {
            isTextEditorFocused = true
        }
    }

    // MARK: - Actions

    private func handleVoiceTap() {
        errorMessage = nil
        if phase == .recording {
            stopAndTranscribe()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        Task {
            do {
                _ = try await recorder.startRecording()
                phase = .recording
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func stopAndTranscribe() {
        recorder.stopRecording()
        phase = .transcribing

        let dir = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Recordings", isDirectory: true)

        guard let dir else {
            errorMessage = "录音目录不可用。"
            phase = .idle
            return
        }

        let latestURL = latestRecording(in: dir)
        guard let latestURL else {
            errorMessage = "没有找到录音文件。"
            phase = .idle
            return
        }

        Task {
            do {
                let text = try await transcriber.transcribe(url: latestURL)
                let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let item = TodoItem(
                    text: cleaned.isEmpty ? "（无文字内容）" : cleaned,
                    audioFileName: latestURL.lastPathComponent
                )
                try storage.insert(item)
                dismiss()
            } catch {
                errorMessage = "转写失败：\(error.localizedDescription)"
                phase = .idle
            }
        }
    }

    private func saveTextInput() {
        let cleaned = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        let item = TodoItem(text: cleaned)
        do {
            try storage.insert(item)
            dismiss()
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private func latestRecording(in dir: URL) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey],
            options: []
        )) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "m4a" }
            .max { $0.creationDate() < $1.creationDate() }
    }
}

private extension URL {
    func creationDate() -> Date {
        (try? resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }
}
