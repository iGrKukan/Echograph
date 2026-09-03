import Foundation

struct Transcript: Hashable, Codable, Sendable {
    var segments: [Segment]
    var language: String
    var modelUsed: TranscriptionModel

    var fullText: String {
        segments.map(\.text).joined(separator: " ")
    }
}

extension Transcript {
    struct Segment: Identifiable, Hashable, Codable, Sendable {
        let id: UUID
        var startTime: TimeInterval
        var endTime: TimeInterval
        var text: String
        var speaker: Speaker?
        var words: [Word]
        var isHighlighted: Bool

        init(
            id: UUID = UUID(),
            startTime: TimeInterval,
            endTime: TimeInterval,
            text: String,
            speaker: Speaker? = nil,
            words: [Word] = [],
            isHighlighted: Bool = false
        ) {
            self.id = id
            self.startTime = startTime
            self.endTime = endTime
            self.text = text
            self.speaker = speaker
            self.words = words
            self.isHighlighted = isHighlighted
        }

        // Backward-compatible decoding: existing JSON without `isHighlighted`
        // continues to load as `false`.
        enum CodingKeys: String, CodingKey {
            case id, startTime, endTime, text, speaker, words, isHighlighted
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try c.decode(UUID.self, forKey: .id)
            self.startTime = try c.decode(TimeInterval.self, forKey: .startTime)
            self.endTime = try c.decode(TimeInterval.self, forKey: .endTime)
            self.text = try c.decode(String.self, forKey: .text)
            self.speaker = try c.decodeIfPresent(Speaker.self, forKey: .speaker)
            self.words = try c.decodeIfPresent([Word].self, forKey: .words) ?? []
            self.isHighlighted = try c.decodeIfPresent(Bool.self, forKey: .isHighlighted) ?? false
        }
    }

    struct Word: Hashable, Codable, Sendable {
        var text: String
        var startTime: TimeInterval
        var endTime: TimeInterval
        var confidence: Double
    }

    struct Speaker: Identifiable, Hashable, Codable, Sendable {
        let id: UUID
        var label: String

        init(id: UUID = UUID(), label: String) {
            self.id = id
            self.label = label
        }
    }
}

enum TranscriptionModel: String, Hashable, Codable, Sendable {
    case appleSpeechAnalyzer
    case parakeetTDT
    // Whisper was removed as an engine (replaced by Parakeet TDT), but these
    // cases stay so previously saved transcripts (already-transcribed
    // recordings on a subscriber's device) keep decoding instead of throwing.
    case whisperTiny
    case whisperBase
    case whisperSmall
    case whisperLargeV3Turbo

    var displayName: String {
        switch self {
        case .appleSpeechAnalyzer: return "Apple Speech"
        case .parakeetTDT: return "Parakeet v3"
        case .whisperTiny: return "Whisper Tiny"
        case .whisperBase: return "Whisper Base"
        case .whisperSmall: return "Whisper Small"
        case .whisperLargeV3Turbo: return "Whisper Large v3 Turbo"
        }
    }
}
