import SwiftUI

@main
struct EchographApp: App {
    @State private var store: RecordingStore
    @State private var transcription: TranscriptionService
    @State private var watchSync: WatchConnectivityCoordinator
    @State private var purchases: PurchaseManager
    @State private var summary: SummaryService
    @State private var analysisService: AnalysisService

    @AppStorage("Echograph.didShowConsentDisclaimer") private var didShowConsentDisclaimer = false
    @State private var showingConsent = false

    init() {
        UITestHooks.applyIfNeeded()
        Self.seedAnalyzerDefaultsIfEmpty()

        let store = RecordingStore()
        _store = State(initialValue: store)
        _transcription = State(initialValue: TranscriptionService(store: store))
        _watchSync = State(initialValue: WatchConnectivityCoordinator(store: store))
        _purchases = State(initialValue: PurchaseManager())
        _summary = State(initialValue: SummaryService(store: store))
        _analysisService = State(initialValue: AnalysisService())
    }

    /// Substrings that mark an obsolete or private transport. Any stored URL
    /// matching one of these is purged on launch: it can never answer, and
    /// leaving it in Settings only produces a hang on the connection test.
    private static let analyzerStaleURLPatterns = ["trycloudflare.com", "tail4504ee.ts.net"]

    /// Synchronizes the AI-Analyzer URL/token with DevDefaults. Order on
    /// every launch:
    ///   1. If the stored URL matches a known-dead pattern → clear it.
    ///   2. If DevDefaults has values → force-overwrite (dev machine).
    /// There is no built-in fallback server: the analyzer is an optional
    /// self-hosted feature, so an unconfigured install simply shows
    /// "Not configured" instead of pointing at somebody else's machine.
    private static func seedAnalyzerDefaultsIfEmpty() {
        let defaults = UserDefaults.standard
        let urlKey = "Voicekeep.analyzerURL"
        let tokenKey = "Voicekeep.analyzerToken"

        if let stored = defaults.string(forKey: urlKey),
           analyzerStaleURLPatterns.contains(where: { stored.contains($0) }) {
            defaults.removeObject(forKey: urlKey)
        }

        if !DevDefaults.analyzerURL.isEmpty {
            defaults.set(DevDefaults.analyzerURL, forKey: urlKey)
        }

        if !DevDefaults.analyzerToken.isEmpty {
            defaults.set(DevDefaults.analyzerToken, forKey: tokenKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
                .environment(transcription)
                .environment(watchSync)
                .environment(purchases)
                .environment(summary)
                .environment(analysisService)
                .sheet(isPresented: $showingConsent) {
                    ConsentDisclaimerView {
                        didShowConsentDisclaimer = true
                        showingConsent = false
                    }
                }
                .task {
                    if !didShowConsentDisclaimer { showingConsent = true }
                }
        }
    }
}
