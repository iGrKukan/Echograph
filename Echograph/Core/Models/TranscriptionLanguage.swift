import Foundation

enum TranscriptionLanguage: String, CaseIterable, Identifiable, Hashable, Sendable {
    case auto
    case english = "en-US"
    case russian = "ru-RU"
    case german = "de-DE"
    case french = "fr-FR"
    case spanish = "es-ES"
    case italian = "it-IT"
    case portuguese = "pt-PT"
    case japanese = "ja-JP"
    case korean = "ko-KR"
    case chineseSimplified = "zh-CN"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto-detect"
        case .english: return "English"
        case .russian: return "Русский"
        case .german: return "Deutsch"
        case .french: return "Français"
        case .spanish: return "Español"
        case .italian: return "Italiano"
        case .portuguese: return "Português"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .chineseSimplified: return "简体中文"
        }
    }

    /// Returns nil for `auto` — Apple Speech then falls back to `Locale.current`
    /// instead of a hinted locale.
    var languageHint: String? {
        self == .auto ? nil : rawValue
    }
}
