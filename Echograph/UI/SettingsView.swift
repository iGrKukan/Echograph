import StoreKit
import SwiftUI

struct SettingsView: View {
    @Environment(PurchaseManager.self) private var purchases
    @Environment(AnalysisService.self) private var analysisService
    @Environment(\.dismiss) private var dismiss

    @AppStorage("Echograph.preferredLanguage") private var preferredLanguageRaw: String = TranscriptionLanguage.auto.rawValue
    @AppStorage("Echograph.customVocabulary") private var customVocabulary: String = ""
    @AppStorage("Voicekeep.analyzerURL") private var analyzerURL: String = ""
    @AppStorage("Voicekeep.analyzerToken") private var analyzerToken: String = ""

    @State private var showingVocabularySheet = false
    @State private var showingPaywall = false
    @State private var showingManageSubs = false
    @State private var connectionStatus: ConnectionStatus = .unknown
    @State private var isTestingConnection = false

    private enum ConnectionStatus {
        case unknown, ok, failed
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Transcription") {
                    Picker("Default Language", selection: Binding(
                        get: { TranscriptionLanguage(rawValue: preferredLanguageRaw) ?? .auto },
                        set: { preferredLanguageRaw = $0.rawValue }
                    )) {
                        ForEach(TranscriptionLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }

                    Button {
                        showingVocabularySheet = true
                    } label: {
                        HStack {
                            Label("Custom Vocabulary", systemImage: "text.book.closed")
                            Spacer()
                            Text(vocabularyTermsCount > 0 ? "\(vocabularyTermsCount) terms" : "None")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("AI Analyzer") {
                    TextField("Server URL (e.g. http://100.x.x.x:19847)", text: $analyzerURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .onChange(of: analyzerURL) { _, _ in connectionStatus = .unknown }
                    SecureField("Bearer token", text: $analyzerToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: analyzerToken) { _, _ in connectionStatus = .unknown }
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(connectionStatusText)
                            .foregroundStyle(connectionStatusColor)
                    }
                    Button {
                        Task { await testConnection() }
                    } label: {
                        if isTestingConnection {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Testing…")
                            }
                        } else {
                            Label("Test connection", systemImage: "antenna.radiowaves.left.and.right")
                        }
                    }
                    .disabled(analyzerURL.isEmpty || isTestingConnection)
                }

                Section("Subscription") {
                    HStack {
                        Label("Current Tier", systemImage: "person.crop.circle.badge.checkmark")
                        Spacer()
                        Text(currentTierLabel)
                            .foregroundStyle(.secondary)
                    }

                    if !purchases.hasPro {
                        Button {
                            showingPaywall = true
                        } label: {
                            Label("Upgrade to Pro", systemImage: "sparkles")
                        }
                    }

                    Button {
                        Task { await purchases.restorePurchases() }
                    } label: {
                        Label("Restore Purchases", systemImage: "arrow.clockwise")
                    }

                    if purchases.hasProPlus {
                        Button {
                            showingManageSubs = true
                        } label: {
                            Label("Manage Subscription", systemImage: "creditcard")
                        }
                    }
                }

                Section("Privacy") {
                    Label("Audio never leaves your device.", systemImage: "lock.shield.fill")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Link(destination: URL(string: "mailto:support@timberbid.by")!) {
                        Label("Contact Support", systemImage: "envelope")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingVocabularySheet) {
                VocabularySettingsSheet(text: $customVocabulary)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .manageSubscriptionsSheet(isPresented: $showingManageSubs)
        }
    }

    private var vocabularyTermsCount: Int {
        customVocabulary
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
    }

    private var currentTierLabel: String {
        if purchases.hasProPlus { return "Pro+" }
        if purchases.hasPro { return "Pro" }
        return "Free"
    }

    private var connectionStatusText: String {
        switch connectionStatus {
        case .unknown: return analyzerURL.isEmpty ? "Not configured" : "Unknown"
        case .ok:      return "Connected"
        case .failed:  return "Not reachable"
        }
    }

    private var connectionStatusColor: Color {
        switch connectionStatus {
        case .unknown: return .secondary
        case .ok:      return .green
        case .failed:  return .red
        }
    }

    private func testConnection() async {
        isTestingConnection = true
        defer { isTestingConnection = false }
        let ok = await analysisService.healthCheck()
        connectionStatus = ok ? .ok : .failed
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

private struct VocabularySettingsSheet: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add proper nouns, technical terms, brand names — Whisper will be biased toward recognizing them. One per line works best.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                TextEditor(text: $text)
                    .font(.body.monospaced())
                    .padding(.horizontal, 12)
                    .focused($focused)
            }
            .padding(.top, 8)
            .navigationTitle("Custom Vocabulary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear", role: .destructive) { text = "" }
                        .disabled(text.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
    }
}
