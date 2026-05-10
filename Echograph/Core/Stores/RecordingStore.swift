import Foundation
import Observation

@MainActor
@Observable
final class RecordingStore {
    private(set) var recordings: [Recording] = []

    private let metadataURL: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("recordings.json")
    }()

    init() {
        load()
    }

    func add(_ recording: Recording) {
        recordings.insert(recording, at: 0)
        persist()
    }

    func update(_ recording: Recording) {
        guard let idx = recordings.firstIndex(where: { $0.id == recording.id }) else { return }
        recordings[idx] = recording
        persist()
    }

    func delete(_ recording: Recording) {
        recordings.removeAll { $0.id == recording.id }
        try? FileManager.default.removeItem(at: recording.fileURL)
        persist()
    }

    func rename(_ recording: Recording, to newTitle: String) {
        guard let idx = recordings.firstIndex(where: { $0.id == recording.id }) else { return }
        recordings[idx].title = newTitle
        persist()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: metadataURL.path) else { return }
        do {
            let data = try Data(contentsOf: metadataURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            recordings = try decoder.decode([Recording].self, from: data)
        } catch {
            recordings = []
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(recordings)
            try data.write(to: metadataURL, options: [.atomic])
        } catch {
            // best-effort persistence; fall back silently
        }
    }
}
