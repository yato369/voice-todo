import SwiftUI
import SwiftData

/// Record a voice memo, transcribe it, and save it as a to-do item.
struct RecordView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @StateObject private var recorder = AudioRecorder()
    @State private var phase: Phase = .idle
    @State private var errorMessage: String?

    private let transcriber: SpeechTranscriberProtocol = SpeechTranscriber()
    private var storage: StorageServiceProtocol { StorageService(context: modelContext) }

    enum Phase {
        case idle
        case recording
        case transcribing
    }

    var body: some View {
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
                handleTap()
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

            Button("取消") {
                recorder.stopRecording()
                dismiss()
            }
            .padding(.bottom, 16)
        }
        .task {
            _ = await SpeechTranscriber.requestAuthorization()
        }
    }

    private func handleTap() {
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
