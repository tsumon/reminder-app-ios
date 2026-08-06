import Speech
import AVFoundation

/// 语音识别服务（iOS 原生 SFSpeechRecognizer）
@MainActor
final class VoiceRecognizer: ObservableObject {
    static let shared = VoiceRecognizer()

    @Published var isRecording = false
    @Published var transcribedText = ""

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    /// 请求权限
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// 开始录音识别
    func startRecording() throws {
        // 停止之前的
        stopRecording()

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw VoiceError.notAvailable
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        isRecording = true
        transcribedText = ""

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            // SFSpeechRecognitionTask 的 resultHandler 不保证主线程回调，
            // 而本类标注 @MainActor——必须显式切回主线程再写 @Published / 操作 AVAudioEngine
            if let result = result {
                Task { @MainActor [weak self] in
                    self?.transcribedText = result.bestTranscription.formattedString
                }
            }
            if error != nil || result?.isFinal == true {
                Task { @MainActor [weak self] in
                    self?.stopRecordingInternal()
                }
            }
        }
    }

    /// 停止录音
    func stopRecording() {
        stopRecordingInternal()
    }

    private func stopRecordingInternal() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false

        try? AVAudioSession.sharedInstance().setActive(false)
    }
}

enum VoiceError: LocalizedError {
    case notAvailable
    var errorDescription: String? { "语音识别不可用" }
}
