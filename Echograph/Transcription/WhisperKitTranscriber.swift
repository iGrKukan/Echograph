@preconcurrency import Foundation
@preconcurrency import WhisperKit

/// On-device Whisper engine. Lazily loads the WhisperKit pipeline (which downloads
/// the model on first use) and reuses it for subsequent transcriptions.
actor WhisperKitTranscriber: TranscriptionEngine {
    nonisolated let displayName: String
    nonisolated let modelKind: TranscriptionModel
    private let model: WhisperModel
    private var pipeline: WhisperKit?

    init(model: WhisperModel) {
        self.model = model
        self.displayName = model.displayName
        self.modelKind = model.transcriptionKind
    }

    func transcribe(fileURL: URL, languageHint: String?) async throws -> Transcript {
        try await transcribe(fileURL: fileURL, languageHint: languageHint, vocabularyPrompt: nil)
    }

    /// Pro tier overload: passes a free-form vocabulary prompt to Whisper. The
    /// prompt is tokenized and fed as `promptTokens`, biasing decoding toward
    /// the listed names/terms.
    func transcribe(fileURL: URL, languageHint: String?, vocabularyPrompt: String?) async throws -> Transcript {
        print("[Whisper] transcribe start file=\(fileURL.lastPathComponent) lang=\(languageHint ?? "auto") model=\(model.identifier) vocab=\(vocabularyPrompt?.count ?? 0)c")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("[Whisper] file not found")
            throw TranscriptionError.fileNotFound(fileURL)
        }

        let attrs = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)) ?? [:]
        print("[Whisper] file size=\(attrs[.size] ?? "?")")

        let pipeline: WhisperKit
        if let existing = self.pipeline {
            pipeline = existing
            print("[Whisper] using cached pipeline")
        } else {
            do {
                print("[Whisper] loading WhisperKit pipeline (downloads model on first run)…")
                pipeline = try await WhisperKit(model: model.identifier)
                self.pipeline = pipeline
                print("[Whisper] pipeline ready")
            } catch {
                print("[Whisper] pipeline init failed: \(error)")
                throw TranscriptionError.engineUnavailable(error.localizedDescription)
            }
        }

        // Whisper expects ISO-639-1 codes ("ru"), not BCP-47 ("ru-RU"). Mapping
        // full locales straight in causes WhisperKit to reject all decoded
        // tokens and emit only special tokens — looks like "no speech".
        let whisperLanguage: String? = languageHint.flatMap { hint in
            String(hint.split(separator: "-").first ?? Substring(hint))
        }
        print("[Whisper] mapped language hint \(languageHint ?? "auto") -> \(whisperLanguage ?? "auto")")

        // Encode the user's custom vocabulary prompt into Whisper tokens so
        // model decoding is biased toward the listed names/terms.
        let promptTokens: [Int]? = {
            guard let p = vocabularyPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !p.isEmpty else { return nil }
            // Whisper convention: prefix prompt with a space.
            let encoded = pipeline.tokenizer?.encode(text: " " + p) ?? []
            // Truncate to the last 224 tokens (Whisper hard limit for prompt).
            let limit = 224
            let trimmed = encoded.count > limit ? Array(encoded.suffix(limit)) : encoded
            return trimmed.isEmpty ? nil : trimmed
        }()
        if let promptTokens {
            print("[Whisper] vocabulary prompt: \(promptTokens.count) tokens")
        }

        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: whisperLanguage,
            // Default WhisperKit thresholds are tuned for clean studio audio
            // and reject anything mildly noisy. Loosen them for real-world use.
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: true,
            promptTokens: promptTokens,
            suppressBlank: true,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.5,
            noSpeechThreshold: 0.3
        )

        let results: [TranscriptionResult]
        do {
            print("[Whisper] calling transcribe on path=\(fileURL.path)")
            results = try await pipeline.transcribe(
                audioPath: fileURL.path,
                decodeOptions: options
            )
            print("[Whisper] transcribe returned \(results.count) results")
            for (i, r) in results.enumerated() {
                print("[Whisper] result[\(i)] text=\(r.text.prefix(200)) segments=\(r.segments.count)")
            }
        } catch {
            print("[Whisper] transcribe threw: \(error)")
            throw TranscriptionError.engineFailed(error.localizedDescription)
        }

        return try Self.makeTranscript(
            results: results,
            model: modelKind,
            language: languageHint ?? "en"
        )
    }

    private static func makeTranscript(
        results: [TranscriptionResult],
        model: TranscriptionModel,
        language: String
    ) throws -> Transcript {
        var segments: [Transcript.Segment] = []
        for result in results {
            for seg in result.segments {
                let cleanedText = stripSpecialTokens(seg.text).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanedText.isEmpty else { continue }
                let words: [Transcript.Word] = (seg.words ?? [])
                    .map { w in
                        Transcript.Word(
                            text: stripSpecialTokens(w.word),
                            startTime: TimeInterval(w.start),
                            endTime: TimeInterval(w.end),
                            confidence: Double(w.probability)
                        )
                    }
                    .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
                segments.append(
                    Transcript.Segment(
                        startTime: TimeInterval(seg.start),
                        endTime: TimeInterval(seg.end),
                        text: cleanedText,
                        speaker: nil,
                        words: words
                    )
                )
            }
        }

        if segments.isEmpty {
            // Whisper produced only special tokens like <|startoftranscript|><|endoftext|>,
            // which means it didn't detect any speech.
            throw TranscriptionError.engineFailed(
                "No speech detected. Try a longer recording, speak closer to the microphone, or pick a larger Whisper model."
            )
        }

        return Transcript(
            segments: segments,
            language: language,
            modelUsed: model
        )
    }

    /// Whisper occasionally emits raw special tokens like
    /// `<|startoftranscript|>`, `<|endoftext|>`, `<|ru|>`, `<|nospeech|>`,
    /// `<|0.00|>` etc. We strip them before showing text to the user.
    private static func stripSpecialTokens(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<\\|[^|]*\\|>") else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}
