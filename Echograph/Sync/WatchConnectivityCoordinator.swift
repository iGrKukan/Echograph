import AVFoundation
import Foundation
import Observation
@preconcurrency import WatchConnectivity

@MainActor
@Observable
final class WatchConnectivityCoordinator: NSObject {
    private let store: RecordingStore

    init(store: RecordingStore) {
        self.store = store
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }
}

extension WatchConnectivityCoordinator: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let metadata = file.metadata ?? [:]
        let filename = (metadata["filename"] as? String) ?? "watch-\(UUID().uuidString).m4a"
        let duration = (metadata["duration"] as? TimeInterval) ?? 0
        let createdAtRaw = metadata["createdAt"] as? TimeInterval

        let dest = Recording.recordingsDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: file.fileURL, to: dest)
        } catch {
            return
        }

        let createdAt = createdAtRaw.map(Date.init(timeIntervalSince1970:)) ?? .now

        Task { @MainActor in
            let resolvedDuration = duration > 0
                ? duration
                : await Self.duration(of: dest)

            let recording = Recording(
                title: "From Apple Watch",
                createdAt: createdAt,
                duration: resolvedDuration,
                filename: filename
            )
            self.store.add(recording)
        }
    }

    private static func duration(of url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        do {
            let cm = try await asset.load(.duration)
            return CMTimeGetSeconds(cm)
        } catch {
            return 0
        }
    }
}
