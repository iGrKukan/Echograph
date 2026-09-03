import Foundation

protocol TranscriptionEngine: Sendable {
    var displayName: String { get }
    var modelKind: TranscriptionModel { get }

    /// Transcribe an on-disk audio file and return a structured transcript.
    /// Throws on permission errors, language-not-supported, or engine failure.
    func transcribe(fileURL: URL, languageHint: String?) async throws -> Transcript
}

enum TranscriptionError: LocalizedError {
    case permissionDenied
    case languageNotSupported(String)
    case engineUnavailable(String)
    case engineFailed(String)
    case fileNotFound(URL)
    /// The free transcription quota (`FreeTranscriptionLimiter`) is used up
    /// and the caller isn't a subscriber. Callers should check
    /// `FreeTranscriptionLimiter.isExhausted` before calling `transcribe`
    /// and show the paywall directly instead — this is the defensive
    /// fallback for a call site that skips that check.
    case freeLimitReached

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Speech recognition permission was denied. Open Settings to enable it."
        case .languageNotSupported(let lang):
            return "The selected engine does not support \(lang) on this device."
        case .engineUnavailable(let detail):
            return "Transcription engine unavailable: \(detail)"
        case .engineFailed(let detail):
            return "Transcription failed: \(detail)"
        case .fileNotFound(let url):
            return "Recording file not found at \(url.lastPathComponent)."
        case .freeLimitReached:
            return "You've used all your free transcriptions. Subscribe to keep transcribing."
        }
    }
}
