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

        // NOTE: `.appleSpeech` is deliberately exempt from
        // `FreeTranscriptionLimiter` — once the 10 free Parakeet
        // transcriptions run out, the app must still transcribe
        // (just with the free engine), not turn into a paperweight.

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

    /// - Parameter unlimited: pass `purchases.hasPro` (or `hasProPlus`) from
    ///   the caller. Subscribers bypass `FreeTranscriptionLimiter` entirely —
    ///   the free-transcription counter is never read or written for them.
    func transcribe(
        _ recording: Recording,
        using engine: Engine = .parakeet,
        languageHint: String? = nil,
        vocabularyPrompt: String? = nil,
        unlimited: Bool = false
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
                vocabularyPrompt: vocabularyPrompt,
                unlimited: unlimited
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
        vocabularyPrompt: String?,
        unlimited: Bool
    ) async throws -> Transcript {
        switch engine {
        case .appleSpeech:
            // Apple Speech doesn't accept biasing prompts via SFSpeechRecognizer.
            // Never limited — see the note on Engine.displayName.
            return try await appleTranscriber().transcribe(
                fileURL: recording.fileURL,
                languageHint: languageHint
            )
        case .parakeet:
            // Defensive fallback for a call site that skipped the
            // paywall-vs-transcribe check the UI is expected to do before
            // ever reaching here (see RecordingDetailView).
            if !unlimited && FreeTranscriptionLimiter.isExhausted {
                throw TranscriptionError.freeLimitReached
            }
            do {
                let result = try await parakeetTranscriber().transcribe(
                    fileURL: recording.fileURL,
                    languageHint: languageHint,
                    vocabularyPrompt: vocabularyPrompt
                )
                // Only an actual Parakeet success spends the free quota — a
                // fallback to Apple Speech below does not (it's caught
                // separately, this line is unreached in that case).
                if !unlimited {
                    FreeTranscriptionLimiter.recordSuccessfulTranscription()
                }
                return result
            } catch let error as TranscriptionError {
                switch error {
                case .languageNotSupported, .engineUnavailable, .engineFailed:
                    // Silent fallback: Parakeet either doesn't cover this
                    // language or failed to load/run. Retry with Apple Speech
                    // instead of surfacing an error to the user. Does NOT
                    // spend the free Parakeet quota — Parakeet didn't run.
                    print("[TranscriptionService] Parakeet unavailable (\(error.localizedDescription)); falling back to Apple Speech")
                    return try await appleTranscriber().transcribe(
                        fileURL: recording.fileURL,
                        languageHint: languageHint
                    )
                case .permissionDenied, .fileNotFound, .freeLimitReached:
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
