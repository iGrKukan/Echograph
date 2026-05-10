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

    /// Pre-fills the AI-Analyzer URL/token from DevDefaults the first time
    /// they're missing in UserDefaults. Once the user types anything in
    /// Settings → AI Analyzer it sticks; we never overwrite a non-empty
    /// existing value. DevDefaults.swift is gitignored.
    private static func seedAnalyzerDefaultsIfEmpty() {
        let defaults = UserDefaults.standard
        let urlKey = "Voicekeep.analyzerURL"
        let tokenKey = "Voicekeep.analyzerToken"

        let currentURL = defaults.string(forKey: urlKey) ?? ""
        if currentURL.isEmpty, !DevDefaults.analyzerURL.isEmpty {
            defaults.set(DevDefaults.analyzerURL, forKey: urlKey)
        }

        let currentToken = defaults.string(forKey: tokenKey) ?? ""
        if currentToken.isEmpty, !DevDefaults.analyzerToken.isEmpty {
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
