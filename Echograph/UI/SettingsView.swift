import StoreKit
import SwiftUI

struct SettingsView: View {
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    @AppStorage("Echograph.preferredLanguage") private var preferredLanguageRaw: String = TranscriptionLanguage.auto.rawValue
    @AppStorage("Echograph.customVocabulary") private var customVocabulary: String = ""

    @State private var showingVocabularySheet = false
    @State private var showingPaywall = false
    @State private var showingManageSubs = false

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

                Section("Subscription") {
                    HStack {
                        Label("Current Tier", systemImage: "person.crop.circle.badge.checkmark")
                        Spacer()
                        Text(currentTierLabel)
                            .foregroundStyle(.secondary)
                    }

                    if !purchases.hasPro {
                        HStack {
                            Label("Free Transcriptions", systemImage: "waveform")
                            Spacer()
                            Text(freeTranscriptionsRemainingLabel)
                                .foregroundStyle(.secondary)
                        }
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
                    Text("On-device AI: Qwen3 (Apache-2.0)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(DS.Color.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(DS.Color.accent)
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

    private var freeTranscriptionsRemainingLabel: String {
        let remaining = FreeTranscriptionLimiter.remaining
        return String(localized: "\(remaining) of \(FreeTranscriptionLimiter.freeTranscriptionLimit)")
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
                Text("Add proper nouns, technical terms, brand names you want the transcript to get right. One per line works best.")
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
