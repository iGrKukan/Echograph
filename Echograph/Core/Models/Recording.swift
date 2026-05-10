import Foundation

struct Recording: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    /// Filename inside the Documents/Recordings directory. Stored as relative
    /// path because absolute Documents URL changes between app installs.
    var filename: String
    var transcript: Transcript?
    var summary: String?
    /// Markdown analysis returned by the Mac-side `cli/server.py` analyzer.
    /// Persisted with the recording so it survives app restarts.
    var analysis: String?
    var speakerCount: Int
    var tags: [String]

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        duration: TimeInterval,
        filename: String,
        transcript: Transcript? = nil,
        summary: String? = nil,
        analysis: String? = nil,
        speakerCount: Int = 1,
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.filename = filename
        self.transcript = transcript
        self.summary = summary
        self.analysis = analysis
        self.speakerCount = speakerCount
        self.tags = tags
    }

    enum CodingKeys: String, CodingKey {
        case id, title, createdAt, duration, filename, transcript, summary, analysis, speakerCount, tags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.duration = try c.decode(TimeInterval.self, forKey: .duration)
        self.filename = try c.decode(String.self, forKey: .filename)
        self.transcript = try c.decodeIfPresent(Transcript.self, forKey: .transcript)
        self.summary = try c.decodeIfPresent(String.self, forKey: .summary)
        self.analysis = try c.decodeIfPresent(String.self, forKey: .analysis)
        self.speakerCount = try c.decodeIfPresent(Int.self, forKey: .speakerCount) ?? 1
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    var fileURL: URL {
        Recording.recordingsDirectory.appendingPathComponent(filename)
    }

    static var recordingsDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = documents.appendingPathComponent("Recordings", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
