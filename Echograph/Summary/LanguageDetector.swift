import Foundation
import NaturalLanguage

/// Detects the dominant language of a transcript so `SummaryService` can
/// tell the AI backend exactly which language to reply in. A generic
/// "answer in the same language as the input" instruction turned out not to
/// be reliable enough on its own — Russian transcripts kept coming back
/// summarized in English.
enum LanguageDetector {
    /// English names for the languages `NLLanguageRecognizer` can identify.
    /// Only languages we're confident the app's users will actually dictate
    /// in are listed; anything else falls through to `detect(in:)` returning
    /// `nil` rather than guessing.
    private static let englishNames: [NLLanguage: String] = [
        .russian: "Russian",
        .english: "English",
        .german: "German",
        .french: "French",
        .spanish: "Spanish",
        .italian: "Italian",
        .portuguese: "Portuguese",
        .japanese: "Japanese",
        .korean: "Korean",
        .simplifiedChinese: "Chinese",
        .traditionalChinese: "Chinese",
        .ukrainian: "Ukrainian",
        .dutch: "Dutch",
        .polish: "Polish",
        .turkish: "Turkish",
        .arabic: "Arabic",
    ]

    /// Best-effort (ISO code, English name) for the dominant language of
    /// `text`. Only the first 1000 characters are sampled — plenty for
    /// `NLLanguageRecognizer` to work with, and cheap even on long
    /// transcripts. Returns `nil` when the text is empty or the detected
    /// language isn't one we recognize by name.
    static func detect(in text: String) -> (code: String, name: String)? {
        let sample = String(text.prefix(1000))
        guard !sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let language = recognizer.dominantLanguage,
              let name = englishNames[language]
        else { return nil }
        return (language.rawValue, name)
    }
}
