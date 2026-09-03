import Foundation
import Observation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Fallback instruction appended to a system prompt when `LanguageDetector`
/// can't confidently name the transcript's language — better than nothing,
/// but far less reliable than naming the language outright (see
/// `languageInstruction(for:)`), which is why it's only a fallback.
private let respondInTranscriptLanguageFallback = "Answer in the same language as the transcript."

/// Builds the line appended as the LAST line of every system prompt below,
/// telling the model explicitly which language to reply in. Transcripts are
/// frequently Russian while the prompts themselves stay in English; a
/// generic "answer in the same language as the transcript" instruction
/// wasn't reliably followed, so this names the language outright instead.
/// Detection runs on `text` (the transcript itself, not the prompt), and the
/// instruction goes last because models follow it more reliably there.
private func languageInstruction(for text: String) -> String {
    guard let detected = LanguageDetector.detect(in: text) else {
        return respondInTranscriptLanguageFallback
    }
    return "Write your entire response in \(detected.name)."
}

@MainActor
@Observable
final class SummaryService {
    enum State: Equatable {
        case idle
        case running(recordingID: UUID)
        case failed(recordingID: UUID, message: String)
    }

    private(set) var state: State = .idle
    private let store: RecordingStore

    init(store: RecordingStore) {
        self.store = store
    }

    /// True when Apple Foundation Models can answer right now — iPhone 15
    /// Pro+, iOS 26, Apple Intelligence on. The only backend the app uses.
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    func summarize(_ recording: Recording) async {
        guard let transcript = recording.transcript else { return }
        state = .running(recordingID: recording.id)

        do {
            let summary = try await generateSummary(text: transcript.fullText)
            var updated = recording
            updated.summary = summary
            store.update(updated)
            state = .idle
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            state = .failed(recordingID: recording.id, message: msg)
        }
    }

    func clearError() {
        if case .failed = state { state = .idle }
    }

    func isRunning(for id: UUID) -> Bool {
        if case .running(let r) = state, r == id { return true }
        return false
    }

    func errorMessage(for id: UUID) -> String? {
        if case .failed(let r, let m) = state, r == id { return m }
        return nil
    }

    // MARK: - Backend dispatch

    /// Routes one system/user prompt pair to Apple Foundation Models — the
    /// only backend the app uses. `maxTokens` is accepted for call-site
    /// symmetry with the prompt builders below; Foundation Models has no
    /// token-cap parameter to pass it through to.
    private func generate(system: String, user: String, maxTokens: Int) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession { system }
            let response = try await session.respond(to: user)
            return response.content
        }
        #endif
        throw SummaryError.unavailable
    }

    private func generateSummary(text: String) async throws -> String {
        let system = """
        You are a concise meeting-summary assistant. Given a transcript, produce:
        1. A 2-3 sentence summary of the conversation.
        2. A bulleted list of action items (if any), prefixed with "- ".
        Keep tone neutral and factual.
        \(languageInstruction(for: text))
        """
        return try await generate(system: system, user: "Transcript:\n\n\(text)", maxTokens: 500)
    }

    /// Suggests 3-6 short topical tags for the transcript. Returned tags are
    /// lowercased single tokens (kebab-case) suitable for direct use as Recording.tags.
    func suggestTags(for transcript: Transcript) async throws -> [String] {
        let system = """
        You suggest 3-6 short topical tags for a transcript.
        Rules:
        - Respond with a comma-separated list ONLY.
        - Each tag is 1-3 lowercase words, no punctuation, no #.
        - Use kebab-case for multi-word tags (e.g. ai-ethics).
        - Prefer concrete topics over generic ones.
        \(languageInstruction(for: transcript.fullText))
        """
        let content = try await generate(system: system, user: transcript.fullText, maxTokens: 60)
        return content
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines)
                      .replacingOccurrences(of: "#", with: "")
                      .lowercased() }
            .filter { !$0.isEmpty }
            .prefix(6)
            .map { String($0) }
    }

    /// Answer an arbitrary user question about the given transcript. Returns
    /// the model's reply.
    func ask(_ question: String, about transcript: Transcript) async throws -> String {
        let system = """
        You answer questions about a recorded transcript. Rules:
        - Only use information from the transcript.
        - If the answer is not in the transcript, say so plainly.
        - Be concise: 1-3 sentences unless the user asks for detail.
        \(languageInstruction(for: transcript.fullText))
        """
        let user = """
        Transcript:
        \(transcript.fullText)

        Question:
        \(question)
        """
        return try await generate(system: system, user: user, maxTokens: 600)
    }
}

enum SummaryError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Apple Intelligence required."
        }
    }
}
