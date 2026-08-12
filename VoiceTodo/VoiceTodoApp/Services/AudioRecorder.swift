import Foundation
import AVFoundation

protocol AudioRecorderProtocol {
    func startRecording() async throws -> URL
    func stopRecording()
    var isRecording: Bool { get }
    var currentTime: TimeInterval { get }
}

/// Records audio to Documents/Recordings as m4a.
final class AudioRecorder: NSObject, ObservableObject, AudioRecorderProtocol, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var currentTime: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var audioURL: URL?

    /// Requests microphone permission, then starts recording. Returns the output URL.
    func startRecording() async throws -> URL {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            throw RecordingError.microphoneDenied
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default)
        try session.setActive(true)

        let dir = try recordingsDirectory()
        let url = dir.appendingPathComponent(UUID().uuidString + ".m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.delegate = self
        guard rec.record() else {
            throw RecordingError.cannotStart
        }
        self.recorder = rec
        self.audioURL = url
        self.isRecording = true
        self.currentTime = 0

        self.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let self.recorder else { return }
            self.currentTime = self.recorder.currentTime
        }
        return url
    }

    func stopRecording() {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
    }

    private func recordingsDirectory() throws -> URL {
        let docs = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = docs.appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    enum RecordingError: LocalizedError {
        case microphoneDenied
        case cannotStart

        var errorDescription: String? {
            switch self {
            case .microphoneDenied: return "麦克风权限被拒绝，请在 设置 > 隐私与安全性 > 麦克风 中开启。"
            case .cannotStart: return "无法开始录音。"
            }
        }
    }
}
