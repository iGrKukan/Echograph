import Foundation
import Observation

@MainActor
@Observable
final class TranscriptionService {
    enum State: Equatable {
        case idle
        case running(recordingID: UUID, phase: String)
        case failed(recordingID: UUID, message: String)
    }

    private(set) var state: State = .idle

    private let store: RecordingStore
    private var apple: AppleSpeechTranscriber?

    init(store: RecordingStore) {
        self.store = store
    }

    /// Apple Speech (`AppleSpeechTranscriber`) is the only transcription
    /// engine — Parakeet was removed (its Hugging Face model download
    /// silently failed on real devices, leaving zero-byte weight files in
    /// the cache while reporting success).
    ///
    /// - Parameter unlimited: pass `purchases.hasPro` (or `hasProPlus`) from
    ///   the caller. Subscribers bypass `FreeTranscriptionLimiter` entirely —
    ///   the free-transcription counter is never read or written for them.
    func transcribe(
        _ recording: Recording,
        languageHint: String? = nil,
        unlimited: Bool = false
    ) async {
        state = .running(recordingID: recording.id, phase: "Transcribing on-device…")

        do {
            let transcript = try await transcript(
                for: recording,
                languageHint: languageHint,
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
        languageHint: String?,
        unlimited: Bool
    ) async throws -> Transcript {
        // Defensive fallback for a call site that skipped the paywall-vs-
        // transcribe check the UI is expected to do before ever reaching
        // here (see RecordingDetailView.transcribeRecording).
        if !unlimited && FreeTranscriptionLimiter.isExhausted {
            throw TranscriptionError.freeLimitReached
        }
        let result = try await appleTranscriber().transcribe(
            fileURL: recording.fileURL,
            languageHint: languageHint
        )
        // Only an actual transcription success spends the free quota — a
        // thrown error above doesn't reach this line.
        if !unlimited {
            FreeTranscriptionLimiter.recordSuccessfulTranscription()
        }
        return result
    }

    private func appleTranscriber() -> AppleSpeechTranscriber {
        if let apple { return apple }
        let new = AppleSpeechTranscriber()
        apple = new
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
