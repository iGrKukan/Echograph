import SwiftUI

@main
struct EchographApp: App {
    @State private var store: RecordingStore
    @State private var transcription: TranscriptionService
    @State private var watchSync: WatchConnectivityCoordinator
    @State private var purchases: PurchaseManager
    @State private var summary: SummaryService
    @State private var analysisStore: AnalysisStore

    @AppStorage("Echograph.didShowConsentDisclaimer") private var didShowConsentDisclaimer = false
    @State private var showingConsent = false

    init() {
        UITestHooks.applyIfNeeded()

        let store = RecordingStore()
        _store = State(initialValue: store)
        _transcription = State(initialValue: TranscriptionService(store: store))
        _watchSync = State(initialValue: WatchConnectivityCoordinator(store: store))
        _purchases = State(initialValue: PurchaseManager())
        _summary = State(initialValue: SummaryService(store: store))
        _analysisStore = State(initialValue: AnalysisStore())
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
                .environment(transcription)
                .environment(watchSync)
                .environment(purchases)
                .environment(summary)
                .environment(analysisStore)
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
