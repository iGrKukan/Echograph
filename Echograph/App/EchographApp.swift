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

    /// Synchronizes the AI-Analyzer URL/token with DevDefaults.
    ///
    /// On dev machines where DevDefaults.swift carries non-empty values,
    /// we force-overwrite UserDefaults on every launch. This means the
    /// dev's paired iPhone always tracks the current Cloudflare quick-tunnel
    /// URL without any manual re-entry — bumping DevDefaults + reinstall
    /// is enough.
    ///
    /// On production builds (and on machines where DevDefaults.swift is
    /// the gitignored stub with empty strings), the function is a no-op
    /// and the user's manually entered values stay untouched.
    private static func seedAnalyzerDefaultsIfEmpty() {
        let defaults = UserDefaults.standard
        let urlKey = "Voicekeep.analyzerURL"
        let tokenKey = "Voicekeep.analyzerToken"

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
