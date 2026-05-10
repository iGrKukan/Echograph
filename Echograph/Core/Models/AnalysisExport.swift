import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// Wraps a `Recording` for export via Share Sheet to the Voicekeep CLI
/// analyzer (see `cli/README.md` and the v1 schema in
/// `cli/test/expected_schema.json`).
struct AnalysisExport {
    let recording: Recording
}

extension AnalysisExport: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { export in
            let url = try export.writeTemporaryFile()
            return SentTransferredFile(url)
        }
        .suggestedFileName { export in export.suggestedFileName }
    }

    var suggestedFileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        let stamp = formatter.string(from: recording.createdAt)
        let safe = sanitize(recording.title)
        return "\(stamp)-\(safe).voicekeep.json"
    }

    fileprivate func writeTemporaryFile() throws -> URL {
        let payload = Payload(recording: recording)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(suggestedFileName)
        try? FileManager.default.removeItem(at: url)
        try data.write(to: url, options: [.atomic])
        return url
    }

    private func sanitize(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics
            .union(.init(charactersIn: " -_"))
        let cleaned = s.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "_" }
            .map(String.init)
            .joined()
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Recording" : cleaned
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
