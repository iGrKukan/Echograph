import Foundation
import Observation

@MainActor
@Observable
final class TranscriptionService {
    enum Engine: Hashable, Sendable {
        case appleSpeech
        case parakeet

        var displayName: String {
            switch self {
            case .appleSpeech: return "Apple Speech"
            case .parakeet: return "Parakeet v3"
            }
        }

        var requiresDownload: Bool {
            if case .parakeet = self { return true }
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
    private var parakeet: ParakeetTranscriber?

    init(store: RecordingStore) {
        self.store = store
    }

    func transcribe(
        _ recording: Recording,
        using engine: Engine = .parakeet,
        languageHint: String? = nil,
        vocabularyPrompt: String? = nil
    ) async {
        let phase = engine.requiresDownload
            ? "Loading model & transcribing…"
            : "Transcribing on-device…"
        state = .running(recordingID: recording.id, phase: phase)

        do {
            let transcript = try await transcript(
                for: recording,
                engine: engine,
                languageHint: languageHint,
                vocabularyPrompt: vocabularyPrompt
            )
            var updated = recording
            updated.transcript = transcript
            store.update(updated)
            state = .idle
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            state = .failed(recordingID: recording.id, message: message)
        }
    }

    private func transcript(
        for recording: Recording,
        engine: Engine,
        languageHint: String?,
        vocabularyPrompt: String?
    ) async throws -> Transcript {
        switch engine {
        case .appleSpeech:
            // Apple Speech doesn't accept biasing prompts via SFSpeechRecognizer.
            return try await appleTranscriber().transcribe(
                fileURL: recording.fileURL,
                languageHint: languageHint
            )
        case .parakeet:
            do {
                return try await parakeetTranscriber().transcribe(
                    fileURL: recording.fileURL,
                    languageHint: languageHint,
                    vocabularyPrompt: vocabularyPrompt
                )
            } catch let error as TranscriptionError {
                switch error {
                case .languageNotSupported, .engineUnavailable, .engineFailed:
                    // Silent fallback: Parakeet either doesn't cover this
                    // language or failed to load/run. Retry with Apple Speech
                    // instead of surfacing an error to the user.
                    print("[TranscriptionService] Parakeet unavailable (\(error.localizedDescription)); falling back to Apple Speech")
                    return try await appleTranscriber().transcribe(
                        fileURL: recording.fileURL,
                        languageHint: languageHint
                    )
                case .permissionDenied, .fileNotFound:
                    throw error
                }
            }
        }
    }

    private func appleTranscriber() -> AppleSpeechTranscriber {
        if let apple { return apple }
        let new = AppleSpeechTranscriber()
        apple = new
        return new
    }

    private func parakeetTranscriber() -> ParakeetTranscriber {
        if let parakeet { return parakeet }
        let new = ParakeetTranscriber()
        parakeet = new
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
}
