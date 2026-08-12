import Foundation
import Speech

protocol SpeechTranscriberProtocol {
    func transcribe(url: URL) async throws -> String
}

/// Uses Apple Speech framework to transcribe an audio file to text (zh-CN).
final class SpeechTranscriber: SpeechTranscriberProtocol {
    private let recognizer: SFSpeechRecognizer?

    init(locale: Locale = Locale(identifier: "zh-CN")) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    func transcribe(url: URL) async throws -> String {
        guard let recognizer, recognizer.isAvailable else {
            throw TranscribeError.recognizerUnavailable
        }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw TranscribeError.notAuthorized
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            var didFinish = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !didFinish else { return }
                if let error {
                    didFinish = true
                    continuation.resume(throwing: error)
                } else if let result, result.isFinal {
                    didFinish = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }

    /// Requests speech recognition permission. Should be called early in the flow.
    static func requestAuthorization() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized { return true }
        guard status == .notDetermined else { return false }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { newStatus in
                continuation.resume(returning: newStatus == .authorized)
            }
        }
    }

    enum TranscribeError: LocalizedError {
        case recognizerUnavailable
        case notAuthorized

        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable: return "语音识别当前不可用，请稍后重试。"
            case .notAuthorized: return "语音识别权限被拒绝，请在 设置 > 隐私与安全性 > 语音识别 中开启。"
            }
        }
    }
}
