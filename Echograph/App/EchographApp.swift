import SwiftUI

@main
struct EchographApp: App {
    @State private var store: RecordingStore
    @State private var transcription: TranscriptionService
    @State private var watchSync: WatchConnectivityCoordinator
    @State private var purchases: PurchaseManager
    @State private var summary: SummaryService

    @AppStorage("Echograph.didShowConsentDisclaimer") private var didShowConsentDisclaimer = false
    @State private var showingConsent = false

    init() {
        UITestHooks.applyIfNeeded()
        Self.purgeRemovedAdminAnalyzerDefaults()

        let store = RecordingStore()
        _store = State(initialValue: store)
        _transcription = State(initialValue: TranscriptionService(store: store))
        _watchSync = State(initialValue: WatchConnectivityCoordinator(store: store))
        _purchases = State(initialValue: PurchaseManager())
        _summary = State(initialValue: SummaryService(store: store))
    }

    /// Миграция: скрытый режим администратора (PIN-код) и связанный с ним
    /// анализатор "AI на Mac" удалены из приложения. У тех, кто успел
    /// включить admin-режим или ввести адрес/токен своего сервера, эти
    /// значения остаются в UserDefaults мусором — подчищаем их при каждом
    /// запуске, чтобы они не всплыли снова после переустановки логики.
    private static func purgeRemovedAdminAnalyzerDefaults() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "Voicekeep.analyzerURL")
        defaults.removeObject(forKey: "Voicekeep.analyzerToken")
        defaults.removeObject(forKey: "Voicekeep.adminMode")
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
                .environment(transcription)
                .environment(watchSync)
                .environment(purchases)
                .environment(summary)
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
