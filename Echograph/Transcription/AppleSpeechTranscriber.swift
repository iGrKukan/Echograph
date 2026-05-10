import Foundation
import Speech

/// Apple's built-in speech recognizer (SFSpeechRecognizer).
/// On iOS 17+ runs on-device for supported locales when `requiresOnDeviceRecognition`
/// is set to true. Falls back to server-side transcription only if the user's locale
/// has no on-device model — we deliberately disallow that path to keep our
/// "audio never leaves your device" promise.
struct AppleSpeechTranscriber: TranscriptionEngine {
    let displayName = "Apple Speech (on-device)"
    let modelKind: TranscriptionModel = .appleSpeechAnalyzer

    func transcribe(fileURL: URL, languageHint: String?) async throws -> Transcript {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw TranscriptionError.fileNotFound(fileURL)
        }

        let authStatus = await SpeechPermission.request()
        guard authStatus == .granted else {
            throw TranscriptionError.permissionDenied
        }

        let locale = preferredLocale(hint: languageHint)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw TranscriptionError.languageNotSupported(locale.identifier)
        }

        // Simulator quirks: `isAvailable` and `supportsOnDeviceRecognition` are
        // unreliable. On real devices we enforce on-device only; on simulator we
        // let the request through and let the system fall back as it can.
        #if !targetEnvironment(simulator)
        guard recognizer.isAvailable else {
            throw TranscriptionError.engineUnavailable("Recognizer not available right now")
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw TranscriptionError.languageNotSupported(locale.identifier)
        }
        #endif

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        #if targetEnvironment(simulator)
        // Simulator has no on-device speech model installed; allow cloud fallback
        // for development. Real devices stay strictly on-device.
        request.requiresOnDeviceRecognition = false
        #else
        request.requiresOnDeviceRecognition = true
        #endif
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        if #available(iOS 16, *) {
            request.addsPunctuation = true
        }

        return try await recognize(
            request: request,
            recognizer: recognizer,
            languageCode: locale.identifier
        )
    }

    private func preferredLocale(hint: String?) -> Locale {
        if let hint, !hint.isEmpty {
            return Locale(identifier: hint)
        }
        return Locale.current
    }

    private func recognize(
        request: SFSpeechURLRecognitionRequest,
        recognizer: SFSpeechRecognizer,
        languageCode: String
    ) async throws -> Transcript {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Transcript, Error>) in
            nonisolated(unsafe) var didResume = false
            let task = recognizer.recognitionTask(with: request) { result, error in
                if didResume { return }
                if let error {
                    didResume = true
                    continuation.resume(throwing: TranscriptionError.engineFailed(error.localizedDescription))
                    return
                }
                guard let result, result.isFinal else { return }
                didResume = true
                let transcript = Self.makeTranscript(
                    result: result,
                    languageCode: languageCode
                )
                continuation.resume(returning: transcript)
            }
            _ = task
        }
    }

    private static func makeTranscript(
        result: SFSpeechRecognitionResult,
        languageCode: String
    ) -> Transcript {
        let segments: [Transcript.Segment] = result.bestTranscription.segments.map { seg in
            Transcript.Segment(
                startTime: seg.timestamp,
                endTime: seg.timestamp + seg.duration,
                text: seg.substring,
                speaker: nil,
                words: [
                    Transcript.Word(
                        text: seg.substring,
                        startTime: seg.timestamp,
                        endTime: seg.timestamp + seg.duration,
                        confidence: Double(seg.confidence)
                    )
                ]
            )
        }

        return Transcript(
            segments: segments.isEmpty
                ? [.init(startTime: 0, endTime: 0, text: result.bestTranscription.formattedString)]
                : segments,
            language: languageCode,
            modelUsed: .appleSpeechAnalyzer
        )
    }
}
