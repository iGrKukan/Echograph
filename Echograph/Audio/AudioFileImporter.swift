import AVFoundation
import Foundation

enum AudioFileImporter {
    enum Failure: LocalizedError {
        case notAccessible
        case copyFailed(String)
        case unsupportedFormat(String)

        var errorDescription: String? {
            switch self {
            case .notAccessible: return "Couldn't access the file. Make sure it's in Files or iCloud Drive."
            case .copyFailed(let s): return "Couldn't copy the file: \(s)"
            case .unsupportedFormat(let ext): return "Audio format “.\(ext)” isn't supported."
            }
        }
    }

    private static let supportedExtensions: Set<String> = ["m4a", "mp3", "wav", "aiff", "aif", "caf"]

    /// Copies a user-picked audio file into the Recordings/ directory and
    /// returns a Recording entry ready to add to the store.
    static func `import`(from sourceURL: URL) async throws -> Recording {
        let needsScope = sourceURL.startAccessingSecurityScopedResource()
        defer { if needsScope { sourceURL.stopAccessingSecurityScopedResource() } }

        let ext = sourceURL.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            throw Failure.unsupportedFormat(ext)
        }

        let destFilename = "imported-\(UUID().uuidString.prefix(8)).\(ext)"
        let destURL = Recording.recordingsDirectory.appendingPathComponent(destFilename)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        } catch {
            throw Failure.copyFailed(error.localizedDescription)
        }

        let asset = AVURLAsset(url: destURL)
        let duration: TimeInterval = (try? await asset.load(.duration).seconds) ?? 0

        let title = sourceURL.deletingPathExtension().lastPathComponent
        return Recording(
            title: title.isEmpty ? "Imported recording" : title,
            duration: duration,
            filename: destFilename
        )
    }
}
