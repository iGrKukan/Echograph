import FluidAudio
import Foundation

/// On-device NVIDIA Parakeet TDT 0.6B v3 engine (via the FluidAudio package).
/// Lazily downloads and loads the CoreML model bundle (~460 MB, cached by the
/// package after the first run) and reuses the loaded `AsrManager` for every
/// subsequent transcription — mirrors the old WhisperKitTranscriber's
/// load-once-and-cache shape.
actor ParakeetTranscriber: TranscriptionEngine {
    nonisolated let displayName = "Parakeet v3"
    nonisolated let modelKind: TranscriptionModel = .parakeetTDT

    /// ISO-639-1 codes the multilingual Parakeet TDT 0.6B v3 checkpoint covers
    /// (NVIDIA/FluidInference model card, 25 European languages) — the same
    /// set FluidAudio's own `Language` enum accepts for script-aware decoding.
    /// Anything outside this set throws `.languageNotSupported` so
    /// `TranscriptionService` can fall back to Apple Speech.
    static let supportedLanguageCodes: Set<String> = [
        "bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu",
        "it", "lv", "lt", "mt", "pl", "pt", "ro", "sk", "sl", "es", "sv", "ru", "uk",
    ]

    /// Approximate size of the required model files (Preprocessor + Encoder +
    /// Decoder + JointDecision + vocabulary), for UX-only display.
    static let downloadSizeMB = 460

    private var manager: AsrManager?

    func transcribe(fileURL: URL, languageHint: String?) async throws -> Transcript {
        try await transcribe(fileURL: fileURL, languageHint: languageHint, vocabularyPrompt: nil)
    }

    /// - Parameter vocabularyPrompt: Accepted for call-site parity with the old
    ///   Whisper path (the Pro "Custom Vocabulary" feature) but currently
    ///   unused. FluidAudio's plain `AsrManager.transcribe` has no bias
    ///   prompt; term boosting only exists via its separate CTC-based
    ///   `configureVocabularyBoosting` API, which needs its own additional
    ///   model download and was out of scope for this engine swap.
    func transcribe(fileURL: URL, languageHint: String?, vocabularyPrompt: String?) async throws -> Transcript {
        print("[Parakeet] transcribe start file=\(fileURL.lastPathComponent) lang=\(languageHint ?? "auto")")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("[Parakeet] file not found")
            throw TranscriptionError.fileNotFound(fileURL)
        }

        let code = languageHint.flatMap { Self.languageCode(from: $0) }
        if let code, !Self.supportedLanguageCodes.contains(code) {
            print("[Parakeet] language \(languageHint ?? "?") (\(code)) not in supported set")
            throw TranscriptionError.languageNotSupported(languageHint ?? code)
        }
        // Script-aware decoding hint (skips top-K tokens whose script doesn't
        // match, e.g. rejects stray Cyrillic candidates while decoding Polish).
        // `nil` lets the model auto-detect, same as leaving language unset.
        let language = code.flatMap { Language(rawValue: $0) }

        let manager: AsrManager
        if let existing = self.manager {
            manager = existing
            print("[Parakeet] using cached AsrManager")
        } else {
            do {
                print("[Parakeet] downloading/loading Parakeet TDT v3 models (first run only, cached afterwards)…")
                let models = try await AsrModels.downloadAndLoad(version: .v3)
                let newManager = AsrManager(config: .default, models: models)
                self.manager = newManager
                manager = newManager
                print("[Parakeet] AsrManager ready")
            } catch {
                print("[Parakeet] model load failed: \(error)")
                throw TranscriptionError.engineUnavailable(error.localizedDescription)
            }
        }

        let result: ASRResult
        do {
            print("[Parakeet] calling transcribe on path=\(fileURL.path)")
            // AsrManager.transcribe(url:) reads the file and resamples it to
            // 16kHz mono Float32 internally via its own AudioConverter — no
            // manual AVAudioConverter step needed on our side. Each call gets
            // its own fresh decoder state since recordings are transcribed
            // independently (no cross-file streaming context to carry).
            var decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
            result = try await manager.transcribe(fileURL, decoderState: &decoderState, language: language)
            print("[Parakeet] transcribe returned text=\(result.text.prefix(200)) tokens=\(result.tokenTimings?.count ?? 0)")
        } catch {
            print("[Parakeet] transcribe threw: \(error)")
            throw TranscriptionError.engineFailed(error.localizedDescription)
        }

        return try Self.makeTranscript(result: result, language: languageHint ?? "auto")
    }

    /// Whisper-style ISO-639-1 mapping: Parakeet's supported-language set and
    /// FluidAudio's `Language` enum both key off bare codes, not full BCP-47
    /// locales ("ru-RU" -> "ru").
    private static func languageCode(from hint: String) -> String? {
        String(hint.split(separator: "-").first ?? Substring(hint)).lowercased()
    }

    // MARK: - Transcript assembly

    /// Gap between two words, in seconds, that is treated as a paragraph
    /// break when synthesizing segments.
    private static let pauseGapThreshold: TimeInterval = 1.2
    /// Upper bound on a single synthesized segment's duration, so a long
    /// run of unpunctuated speech still gets split into readable chunks.
    private static let maxSegmentDuration: TimeInterval = 20
    private static let sentenceEndings: Set<Character> = [".", "!", "?", "…"]

    /// FluidAudio doesn't return sentence/paragraph-level segments the way
    /// WhisperKit does — only a flat `text` string and, when available,
    /// per-token `tokenTimings`. We use the package's own `buildWordTimings`
    /// to reassemble SentencePiece pieces into words (it already handles the
    /// `▁`/leading-space boundary marker and blank/pad tokens), then
    /// synthesize reading segments by breaking on sentence-ending
    /// punctuation, a pause, or a max-duration cap — approximating what
    /// WhisperKit's own segmenter produced, so the transcript screen's
    /// per-segment editing, highlighting and speaker assignment keep working.
    ///
    /// If no token timings come back at all, we fall back to a single segment
    /// spanning the whole recording: still fully readable and editable, but
    /// with no per-word highlighting and no mid-transcript speaker splitting.
    private static func makeTranscript(result: ASRResult, language: String) throws -> Transcript {
        let wordTimings = buildWordTimings(from: result.tokenTimings ?? [])
        // `WordTiming` (unlike `TokenTiming`) carries no per-word confidence;
        // fall back to the utterance-level confidence for every word.
        let words = wordTimings.map {
            Transcript.Word(text: $0.word, startTime: $0.startTime, endTime: $0.endTime, confidence: Double(result.confidence))
        }

        let segments: [Transcript.Segment]
        if words.isEmpty {
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            segments = text.isEmpty ? [] : [Transcript.Segment(startTime: 0, endTime: result.duration, text: text)]
        } else {
            segments = segmentsFromWords(words)
        }

        guard !segments.isEmpty else {
            throw TranscriptionError.engineFailed(
                "No speech detected. Try a longer recording or speak closer to the microphone."
            )
        }

        return Transcript(segments: segments, language: language, modelUsed: .parakeetTDT)
    }

    private static func segmentsFromWords(_ words: [Transcript.Word]) -> [Transcript.Segment] {
        var segments: [Transcript.Segment] = []
        var current: [Transcript.Word] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            segments.append(
                Transcript.Segment(
                    startTime: first.startTime,
                    endTime: last.endTime,
                    text: current.map(\.text).joined(separator: " "),
                    words: current
                )
            )
            current = []
        }

        for word in words {
            if let last = current.last {
                let gap = word.startTime - last.endTime
                let endsSentence = last.text.last.map { sentenceEndings.contains($0) } ?? false
                let tooLong = word.endTime - current[0].startTime > maxSegmentDuration
                if gap > pauseGapThreshold || endsSentence || tooLong {
                    flush()
                }
            }
            current.append(word)
        }
        flush()
        return segments
    }
}
