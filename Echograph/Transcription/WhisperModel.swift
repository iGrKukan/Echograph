import Foundation

/// User-facing Whisper model choices. Identifiers match argmaxinc/whisperkit-coreml
/// repo names so WhisperKit can resolve them automatically.
enum WhisperModel: String, CaseIterable, Identifiable, Hashable, Sendable {
    case tiny
    case base
    case small
    case largeV3Turbo

    var id: String { rawValue }

    /// HuggingFace-side identifier used by WhisperKit at download time.
    var identifier: String {
        switch self {
        case .tiny: return "openai_whisper-tiny"
        case .base: return "openai_whisper-base"
        case .small: return "openai_whisper-small"
        case .largeV3Turbo: return "openai_whisper-large-v3-v20240930_turbo"
        }
    }

    var displayName: String {
        switch self {
        case .tiny: return "Whisper Tiny"
        case .base: return "Whisper Base"
        case .small: return "Whisper Small"
        case .largeV3Turbo: return "Whisper Large v3 Turbo"
        }
    }

    /// Approximate download size for UX-only display.
    var downloadSizeMB: Int {
        switch self {
        case .tiny: return 75
        case .base: return 145
        case .small: return 470
        case .largeV3Turbo: return 600
        }
    }

    var transcriptionKind: TranscriptionModel {
        switch self {
        case .tiny: return .whisperTiny
        case .base: return .whisperBase
        case .small: return .whisperSmall
        case .largeV3Turbo: return .whisperLargeV3Turbo
        }
    }

    /// Picks a sensible default based on physical RAM. Conservative; user can override.
    static var recommendedForCurrentDevice: WhisperModel {
        let ram = Int64(ProcessInfo.processInfo.physicalMemory)
        let gigs = Double(ram) / (1024.0 * 1024.0 * 1024.0)
        if gigs >= 7.5 { return .largeV3Turbo } // iPhone 15+, iPad Pro M-series
        if gigs >= 5.5 { return .small }        // iPhone 13/14
        return .base                             // iPhone 12 / older / heavy multitasking
    }
}
