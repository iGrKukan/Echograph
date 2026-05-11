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

    /// Public Tailscale Funnel fallback URL for the AI Analyzer. Not a
    /// secret — Funnel exposes the Mac to the public internet but every
    /// POST /analyze still requires the bearer token to do anything.
    private static let analyzerFallbackURL = "https://maru.tail4504ee.ts.net"

    /// Substrings that mark an obsolete transport. Any stored URL matching
    /// one of these gets purged on launch so the fallback can take over.
    private static let analyzerStaleURLPatterns = ["trycloudflare.com"]

    /// Synchronizes the AI-Analyzer URL/token with DevDefaults and the
    /// public fallback. Order on every launch:
    ///   1. If stored URL matches a known-dead pattern → clear it.
    ///   2. If DevDefaults has values → force-overwrite (dev machine).
    ///   3. Else if stored URL is empty → fall back to the public Funnel
    ///      URL. Token still has to come from DevDefaults or manual entry
    ///      in Settings — we never hardcode the bearer.
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
        } else if (defaults.string(forKey: urlKey) ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            defaults.set(analyzerFallbackURL, forKey: urlKey)
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
