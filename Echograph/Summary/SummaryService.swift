import Foundation
import Observation

#if canImport(FoundationModels)
import FoundationModels
#endif

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

    /// Indicates whether on-device LLM is available on the running device.
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

    private func generateSummary(text: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession {
                """
                You are a concise meeting-summary assistant. Given a transcript, produce:
                1. A 2-3 sentence summary of the conversation.
                2. A bulleted list of action items (if any), prefixed with "- ".
                Keep tone neutral and factual.
                """
            }
            let prompt = "Transcript:\n\n\(text)"
            let response = try await session.respond(to: prompt)
            return response.content
        }
        #endif
        throw SummaryError.unavailable
    }

    /// Suggests 3-6 short topical tags for the transcript. Returned tags are
    /// lowercased single tokens (kebab-case) suitable for direct use as Recording.tags.
    func suggestTags(for transcript: Transcript) async throws -> [String] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession {
                """
                You suggest 3-6 short topical tags for a transcript.
                Rules:
                - Respond with a comma-separated list ONLY.
                - Each tag is 1-3 lowercase words, no punctuation, no #.
                - Use kebab-case for multi-word tags (e.g. ai-ethics).
                - Prefer concrete topics over generic ones.
                """
            }
            let response = try await session.respond(to: transcript.fullText)
            return response.content
                .components(separatedBy: CharacterSet(charactersIn: ",\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines)
                          .replacingOccurrences(of: "#", with: "")
                          .lowercased() }
                .filter { !$0.isEmpty }
                .prefix(6)
                .map { String($0) }
        }
        #endif
        throw SummaryError.unavailable
    }

    /// Answer an arbitrary user question about the given transcript using
    /// Apple Foundation Models, on-device. Returns the model's reply.
    func ask(_ question: String, about transcript: Transcript) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession {
                """
                You answer questions about a recorded transcript. Rules:
                - Only use information from the transcript.
                - If the answer is not in the transcript, say so plainly.
                - Be concise: 1-3 sentences unless the user asks for detail.
                """
            }
            let prompt = """
            Transcript:
            \(transcript.fullText)

            Question:
            \(question)
            """
            let response = try await session.respond(to: prompt)
            return response.content
        }
        #endif
        throw SummaryError.unavailable
    }
}

enum SummaryError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "On-device summarization requires iOS 26 with Apple Intelligence enabled."
        }
    }
}
