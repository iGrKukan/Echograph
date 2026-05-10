import Foundation

/// Writes a `Recording` as JSON into the app's iCloud Drive inbox so the
/// Mac-side `cli/voicekeep_analyze.sh` watcher can pick it up. The result
/// `<recording.id>.analysis.md` lands in the same container's `processed/`
/// folder and is observed by `AnalysisStore`.
enum AnalysisExport {
    static let containerIdentifier = "iCloud.by.timberbid.echograph"

    enum ExportError: LocalizedError {
        case iCloudUnavailable
        case noTranscript
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .iCloudUnavailable:
                return String(localized: "iCloud Drive is not available. Sign into iCloud and enable Voicekeep in Settings → Apple ID → iCloud Drive.")
            case .noTranscript:
                return String(localized: "Recording has no transcript yet. Transcribe it first.")
            case .writeFailed(let detail):
                return String(localized: "Could not save the export: \(detail)")
            }
        }
    }

    /// Returns the URL of the JSON file in `<container>/Documents/inbox/`.
    @discardableResult
    static func send(_ recording: Recording) async throws -> URL {
        guard recording.transcript != nil else {
            throw ExportError.noTranscript
        }
        let inbox = try inboxURL()
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

        let payload = Payload(recording: recording)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data: Data
        do {
            data = try encoder.encode(payload)
        } catch {
            throw ExportError.writeFailed(String(describing: error))
        }

        let url = inbox.appendingPathComponent("\(recording.id.uuidString).voicekeep.json")
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw ExportError.writeFailed(String(describing: error))
        }
        return url
    }

    static func inboxURL() throws -> URL {
        try documentsURL().appendingPathComponent("inbox", isDirectory: true)
    }

    static func processedURL() throws -> URL {
        try documentsURL().appendingPathComponent("processed", isDirectory: true)
    }

    static func documentsURL() throws -> URL {
        guard let root = FileManager.default
            .url(forUbiquityContainerIdentifier: containerIdentifier) else {
            throw ExportError.iCloudUnavailable
        }
        return root.appendingPathComponent("Documents", isDirectory: true)
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
