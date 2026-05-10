import Foundation
import Observation

@MainActor
@Observable
final class TranscriptionService {
    enum Engine: Hashable, Sendable {
        case appleSpeech
        case whisper(WhisperModel)

        var displayName: String {
            switch self {
            case .appleSpeech: return "Apple Speech"
            case .whisper(let model): return model.displayName
            }
        }

        var requiresDownload: Bool {
            if case .whisper = self { return true }
            return false
        }
    }

    enum State: Equatable {
        case idle
        case running(recordingID: UUID, phase: String)
        case failed(recordingID: UUID, message: String)
    }

    private(set) var state: State = .idle

    private let store: RecordingStore
    private var apple: AppleSpeechTranscriber?
    private var whisper: [WhisperModel: WhisperKitTranscriber] = [:]

    init(store: RecordingStore) {
        self.store = store
    }

    func transcribe(
        _ recording: Recording,
        using engine: Engine = .appleSpeech,
        languageHint: String? = nil,
        vocabularyPrompt: String? = nil
    ) async {
        let phase = engine.requiresDownload
            ? "Loading model & transcribing…"
            : "Transcribing on-device…"
        state = .running(recordingID: recording.id, phase: phase)

        do {
            let transcript: Transcript
            switch engine {
            case .appleSpeech:
                // Apple Speech doesn't accept biasing prompts via SFSpeechRecognizer.
                transcript = try await transcriber(for: engine).transcribe(
                    fileURL: recording.fileURL,
                    languageHint: languageHint
                )
            case .whisper(let model):
                let whisper = whisperTranscriber(for: model)
                transcript = try await whisper.transcribe(
                    fileURL: recording.fileURL,
                    languageHint: languageHint,
                    vocabularyPrompt: vocabularyPrompt
                )
            }
            var updated = recording
            updated.transcript = transcript
            store.update(updated)
            state = .idle
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            state = .failed(recordingID: recording.id, message: message)
        }
    }

    private func whisperTranscriber(for model: WhisperModel) -> WhisperKitTranscriber {
        if let cached = whisper[model] { return cached }
        let new = WhisperKitTranscriber(model: model)
        whisper[model] = new
        return new
    }

    func clearError() {
        if case .failed = state {
            state = .idle
        }
    }

    func isRunning(for recordingID: UUID) -> Bool {
        if case .running(let id, _) = state, id == recordingID { return true }
        return false
    }

    func phase(for recordingID: UUID) -> String? {
        if case .running(let id, let phase) = state, id == recordingID { return phase }
        return nil
    }

    func errorMessage(for recordingID: UUID) -> String? {
        if case .failed(let id, let message) = state, id == recordingID { return message }
        return nil
    }

    private func transcriber(for engine: Engine) -> any TranscriptionEngine {
        switch engine {
        case .appleSpeech:
            if let apple { return apple }
            let new = AppleSpeechTranscriber()
            apple = new
            return new
        case .whisper(let model):
            if let cached = whisper[model] { return cached }
            let new = WhisperKitTranscriber(model: model)
            whisper[model] = new
            return new
        }
    }
}
