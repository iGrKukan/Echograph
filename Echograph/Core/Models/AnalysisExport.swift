import Foundation

/// Encodes a `Recording` as the v1 JSON payload sent to the Mac analyzer
/// (`POST /analyze`). See the schema reference in `cli/test/expected_schema.json`.
enum AnalysisExport {
    /// Serialise a recording into the v1 JSON body. Throws if encoding fails.
    static func makeJSON(_ recording: Recording) throws -> Data {
        let payload = Payload(recording: recording)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }
}

// MARK: - v1 export schema (mirror of cli/test/expected_schema.json)

private extension AnalysisExport {
    struct Payload: Encodable {
        let version: Int
        let id: String
        let title: String
        let createdAt: Date
        let duration: TimeInterval
        let language: String
        let speakerCount: Int
        let tags: [String]
        let transcript: TranscriptPayload?

        init(recording: Recording) {
            self.version = 1
            self.id = recording.id.uuidString
            self.title = recording.title
            self.createdAt = recording.createdAt
            self.duration = recording.duration
            self.language = recording.transcript?.language ?? ""
            self.speakerCount = recording.speakerCount
            self.tags = recording.tags
            self.transcript = recording.transcript.map(TranscriptPayload.init(from:))
        }
    }

    struct TranscriptPayload: Encodable {
        let fullText: String
        let segments: [SegmentPayload]

        init(from t: Transcript) {
            self.fullText = t.fullText
            self.segments = t.segments.map(SegmentPayload.init(from:))
        }
    }

    struct SegmentPayload: Encodable {
        let startTime: TimeInterval
        let endTime: TimeInterval
        let text: String
        let speaker: String?
        let highlighted: Bool?

        init(from s: Transcript.Segment) {
            self.startTime = s.startTime
            self.endTime = s.endTime
            self.text = s.text
            self.speaker = s.speaker?.label
            self.highlighted = s.isHighlighted ? true : nil
        }
    }
}
