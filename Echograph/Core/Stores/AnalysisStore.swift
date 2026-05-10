import Foundation
import Observation

/// Observes `<container>/Documents/processed/*.analysis.md` and exposes a
/// `recording.id → markdown` map. Updates as iCloud syncs new analyses
/// from the Mac.
@MainActor
@Observable
final class AnalysisStore {
    private(set) var analyses: [UUID: String] = [:]
    private(set) var lastError: String?

    private let query = NSMetadataQuery()

    init() {
        startObserving()
    }

    // No explicit deinit — NSMetadataQuery is released with the instance,
    // and our notification observers capture self weakly so any late
    // callback is a no-op.

    func markdown(for recordingId: UUID) -> String? {
        analyses[recordingId]
    }

    private func startObserving() {
        guard FileManager.default
            .url(forUbiquityContainerIdentifier: AnalysisExport.containerIdentifier) != nil else {
            lastError = "iCloud unavailable"
            return
        }

        query.searchScopes = [NSMetadataQueryUbiquitousDataScope]
        query.predicate = NSPredicate(format: "%K LIKE '*.analysis.md'", NSMetadataItemFSNameKey)
        query.notificationBatchingInterval = 0.5

        let center = NotificationCenter.default
        center.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        center.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        query.start()
    }

    private func refresh() {
        query.disableUpdates()
        defer { query.enableUpdates() }

        var fresh: [UUID: String] = [:]
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            // We only care about files inside our `Documents/processed/` folder.
            guard url.pathComponents.contains("processed") else { continue }
            // Filename pattern: <UUID>.analysis.md
            let stem = url.deletingPathExtension().deletingPathExtension().lastPathComponent
            guard let id = UUID(uuidString: stem) else { continue }
            // Trigger download if iCloud hasn't materialised the file yet.
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                fresh[id] = text
            }
        }
        analyses = fresh
    }
}
