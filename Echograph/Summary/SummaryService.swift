import Foundation
import Observation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// A note appended to every system prompt below so replies match whichever
/// language the recording happens to be in — transcripts are frequently
/// Russian, but the prompts themselves stay in English.
private let respondInTranscriptLanguage = "Answer in the same language as the transcript."

@MainActor
@Observable
final class SummaryService {
    enum State: Equatable {
        case idle
        case running(recordingID: UUID)
        case failed(recordingID: UUID, message: String)
    }

    /// Which engine actually answers AI requests right now.
    enum Backend {
        /// Apple Foundation Models — iPhone 15 Pro+, iOS 26, Apple Intelligence on.
        case appleIntelligence
        /// Local Qwen3 via MLX — everything else, once the model is downloaded.
        case localModel
        /// Neither is usable (e.g. Simulator, or Apple Intelligence off with no
        /// local model support).
        case none
    }

    private(set) var state: State = .idle
    private let store: RecordingStore
    private let localLLM: LocalLLMService

    init(store: RecordingStore, localLLM: LocalLLMService = LocalLLMService()) {
        self.store = store
        self.localLLM = localLLM
    }

    /// Which backend a call to `generate` would actually use right now.
    /// Apple Intelligence is preferred when available (faster, nothing to
    /// download); the local model is the fallback for every other iPhone.
    var activeBackend: Backend {
        if isAppleIntelligenceAvailable { return .appleIntelligence }
        if localLLM.isSupported { return .localModel }
        return .none
    }

    /// True as long as *some* backend can answer — Apple Intelligence, or
    /// the local model (whether or not it's downloaded yet: the UI offers a
    /// download button rather than hiding the feature).
    var isAvailable: Bool { activeBackend != .none }

    private var isAppleIntelligenceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    // MARK: - Local model status (surfaced for the UI's download prompt)

    /// True once the local model's weights are downloaded and ready to load
    /// — the UI can show the normal AI buttons instead of a download prompt.
    var isLocalModelReady: Bool { localLLM.isModelReady }

    /// 0...1 while the local model is downloading.
    var localModelDownloadProgress: Double { localLLM.downloadProgress }

    /// Approximate download size, for the "Download AI model (938 MB)" label.
    var localModelSizeMB: Int { localLLM.modelChoice.approximateDownloadMB }

    /// Downloads and loads the local model. Only meaningful when
    /// `activeBackend == .localModel`; the caller drives the "Downloading… N%"
    /// UI off `localModelDownloadProgress` while this runs.
    func prepareLocalModel() async throws {
        try await localLLM.prepare()
    }

    /// Releases the local model's memory — call from
    /// `applicationDidEnterBackground`. No-op if Apple Intelligence is the
    /// active backend (nothing local is loaded) or nothing was loaded yet.
    func releaseLocalModelMemory() {
        localLLM.unload()
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

    /// Routes one system/user prompt pair to whichever backend is active.
    /// Every public generation method below funnels through here so the
    /// Apple Intelligence ↔ local-model choice lives in exactly one place.
    private func generate(system: String, user: String, maxTokens: Int) async throws -> String {
        switch activeBackend {
        case .appleIntelligence:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                let session = LanguageModelSession { system }
                let response = try await session.respond(to: user)
                return response.content
            }
            #endif
            throw SummaryError.unavailable
        case .localModel:
            return try await localLLM.respond(system: system, user: user, maxTokens: maxTokens)
        case .none:
            throw SummaryError.unavailable
        }
    }

    private func generateSummary(text: String) async throws -> String {
        let system = """
        You are a concise meeting-summary assistant. Given a transcript, produce:
        1. A 2-3 sentence summary of the conversation.
        2. A bulleted list of action items (if any), prefixed with "- ".
        Keep tone neutral and factual.
        \(respondInTranscriptLanguage)
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
        \(respondInTranscriptLanguage)
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

    /// Produce a multi-section markdown analysis of the transcript. This is
    /// a deeper, structured alternative to `summarize()` — closer to a
    /// "report" than a summary. Persists the markdown into Recording.analysis.
    func analyze(_ recording: Recording) async {
        guard let transcript = recording.transcript else { return }
        state = .running(recordingID: recording.id)
        do {
            let markdown = try await generateAnalysis(text: transcript.fullText)
            var updated = recording
            updated.analysis = markdown
            store.update(updated)
            state = .idle
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            state = .failed(recordingID: recording.id, message: msg)
        }
    }

    private func generateAnalysis(text: String) async throws -> String {
        let system = """
        You are a thorough conversation analyst. Given a transcript,
        produce a structured markdown report with these sections:

        ## Overview
        Two or three sentences capturing what the recording is about.

        ## Key topics
        Bulleted list, one topic per line.

        ## Decisions
        Bulleted list of any decisions reached. Use "—" if none.

        ## Action items
        GitHub-flavored task list:
        - [ ] description
        Use "—" if none.

        ## Open questions
        Bulleted list. Use "—" if none.

        ## Notable quotes
        Up to three direct quotes in italics (no speaker attribution
        unless it's clearly in the transcript). Use "—" if none.

        Output ONLY GitHub-flavored markdown. Do not add disclaimers
        about not having the transcript — work with whatever is given.
        \(respondInTranscriptLanguage)
        """
        return try await generate(system: system, user: "Transcript:\n\n\(text)", maxTokens: 1200)
    }

    /// Answer an arbitrary user question about the given transcript. Returns
    /// the model's reply.
    func ask(_ question: String, about transcript: Transcript) async throws -> String {
        let system = """
        You answer questions about a recorded transcript. Rules:
        - Only use information from the transcript.
        - If the answer is not in the transcript, say so plainly.
        - Be concise: 1-3 sentences unless the user asks for detail.
        \(respondInTranscriptLanguage)
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
            return "On-device AI is unavailable — Apple Intelligence is off and the local model isn't ready."
        }
    }
}
