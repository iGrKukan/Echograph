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
        }
    }
}
